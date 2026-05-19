#!/usr/bin/env python3
"""Trim downloaded episodes for daily / tagged Sonarr series.

Semantic replacement for RandomNinjaAtk arr-scripts'
`DailySeriesEpisodeTrimmer.bash` (arr-scripts was removed — it ran
curl|bash on every container boot from a now-unmaintained repo).
arr-scripts ran this per series on import; this runs as a daily cronjob
sweeping every matching series, which is behaviourally equivalent (just
slightly delayed enforcement of the cap).

Rule, matching the original:
  * A series is in scope if Sonarr classifies it seriesType == "daily"
    OR it carries the tag TRIM_TAG (default "dailyseriestrim").
  * Keep count = MAX_DAILY (default 20) for daily-type series, or the
    latest season's episode count for tag-matched non-daily series.
  * Of the episodes that have a file, sorted by airDate descending,
    keep the newest <keep>; for the rest: unmonitor + delete the
    episode file. Refresh the series once if anything changed.

Safe by default: dry-run unless --apply is given. The API key is read
from $SONARR_0_API_KEY or the SOPS-decrypted runtime media.env (the same
var the fetcharr container uses) so no secret lands in git. Host/port is
overridable via --url or $SONARR_URL.
"""
import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request

DEFAULT_URL = os.environ.get("SONARR_URL", "http://localhost:8989")
# media.env resolves relative to this script's repo location
# (scripts/ -> ../common/secrets/.runtime/media.env), no hard-coded paths.
DEFAULT_ENV = os.path.join(
    os.path.dirname(os.path.realpath(__file__)),
    "..", "common", "secrets", ".runtime", "media.env")
TRIM_TAG = "dailyseriestrim"
MAX_DAILY = 20


def load_api_key(env_path: str) -> str:
    if os.environ.get("SONARR_0_API_KEY"):
        return os.environ["SONARR_0_API_KEY"]
    try:
        with open(env_path) as fh:
            for line in fh:
                m = re.match(r"\s*SONARR_0_API_KEY\s*=\s*(.+)\s*$", line)
                if m:
                    return m.group(1).strip().strip('"').strip("'")
    except OSError as e:
        sys.exit(f"cannot read API key from {env_path}: {e}")
    sys.exit(f"SONARR_0_API_KEY not in env or {env_path}")


class Sonarr:
    def __init__(self, base, key):
        self.base, self.key = base.rstrip("/"), key

    def _req(self, path, method="GET", body=None):
        req = urllib.request.Request(
            f"{self.base}/api/v3/{path}", method=method,
            headers={"X-Api-Key": self.key, "Content-Type": "application/json"},
            data=json.dumps(body).encode() if body is not None else None)
        with urllib.request.urlopen(req, timeout=60) as r:
            d = r.read()
            return json.loads(d) if d else None

    series = lambda self: self._req("series")
    episodes = lambda self, sid: self._req(f"episode?seriesId={sid}")

    def unmonitor(self, episode_ids):
        self._req("episode/monitor", "PUT",
                  {"episodeIds": episode_ids, "monitored": False})

    def delete_file(self, file_id):
        self._req(f"episodefile/{file_id}", "DELETE")

    def refresh(self, sid):
        self._req("command", "POST", {"name": "RefreshSeries", "seriesId": sid})


def keep_count(s, daily_default):
    if s.get("seriesType") == "daily":
        return daily_default
    seasons = sorted((x for x in s.get("seasons", []) if x.get("seasonNumber", 0) > 0),
                     key=lambda x: x["seasonNumber"], reverse=True)
    for season in seasons:
        n = (season.get("statistics") or {}).get("totalEpisodeCount")
        if n:
            return n
    return daily_default


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--url", default=DEFAULT_URL)
    ap.add_argument("--env-file", default=DEFAULT_ENV)
    ap.add_argument("--tag", default=TRIM_TAG)
    ap.add_argument("--max-daily", type=int, default=MAX_DAILY)
    ap.add_argument("--apply", action="store_true",
                    help="actually unmonitor + delete (default: dry-run)")
    args = ap.parse_args()

    sn = Sonarr(args.url, load_api_key(args.env_file))
    try:
        all_series = sn.series()
        tags = {t["id"]: t["label"] for t in sn._req("tag")}
    except urllib.error.URLError as e:
        sys.exit(f"Sonarr API unreachable at {args.url}: {e}")

    mode = "APPLY" if args.apply else "DRY-RUN"
    deleted = 0
    for s in sorted(all_series, key=lambda x: x["title"].lower()):
        labels = {tags.get(tid) for tid in s.get("tags", [])}
        is_daily = s.get("seriesType") == "daily"
        if not is_daily and args.tag not in labels:
            continue
        eps = [e for e in sn.episodes(s["id"]) if e.get("hasFile")]
        eps.sort(key=lambda e: (e.get("airDate") or ""), reverse=True)
        keep = keep_count(s, args.max_daily)
        scope = "daily" if is_daily else f"tag:{args.tag}"
        if len(eps) <= keep:
            print(f"[{mode}] {s['title']} ({scope}) — {len(eps)} files ≤ keep {keep}, skip")
            continue
        trim = eps[keep:]
        print(f"[{mode}] {s['title']} ({scope}) — {len(eps)} files, keep {keep}, "
              f"trim {len(trim)}")
        for e in trim:
            tag = f"S{e.get('seasonNumber'):>02}E{e.get('episodeNumber'):>02}"
            fid = e.get("episodeFileId")
            print(f"          - {tag} {e.get('title','')!r} airDate={e.get('airDate')} "
                  f"epId={e['id']} fileId={fid}")
            if args.apply:
                sn.unmonitor([e["id"]])
                if fid:
                    sn.delete_file(fid)
            deleted += 1
        if args.apply:
            sn.refresh(s["id"])
    print(f"[{mode}] done — {deleted} episode(s) "
          f"{'trimmed' if args.apply else 'would be trimmed'}")


if __name__ == "__main__":
    main()
