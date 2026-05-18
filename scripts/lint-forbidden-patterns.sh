#!/bin/bash
# Custom regex hooks for compose files. Each rule is a pre-commit-friendly
# fail-on-match check: if the pattern is found, the lint fails.
#
# Strict mode flips on after Phase 2b finishes pinning images. Set
# STRICT=1 to enable the :latest gate; default is baseline-tolerant
# during 2a so existing :latest violations don't block CI before 2b lands.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

STRICT="${STRICT:-0}"
rc=0

# Glob of compose files to scan. Limited to */docker-compose.yml at the
# top level so we don't pick up examples or vendored content.
#
# All host projects in this repo are now in scope for STRICT image-pinning
# lint. zabbix/ joined 2026-05-18; home/ (pi5) joined the same day after
# pinning landed. Renovate's ignorePaths similarly only excludes the
# .runtime/ secrets dir now.
FILES=()
for f in */docker-compose.yml; do
    [ -f "$f" ] && FILES+=("$f")
done

# 1. Forbid raw 0.0.0.0: host port bindings. Use 127.0.0.1: or a specific
#    DMZ IP (e.g. 10.0.0.3:) when the port should be reachable from the
#    DMZ but not other interfaces. Or omit the host part entirely (just
#    container-side port) — docker binds 0.0.0.0 by default which we
#    flag.
#
# Match form: `- 0.0.0.0:NNNN:NNNN` or `- "0.0.0.0:NNNN:NNNN"`.
matches=$(grep -nE '^\s*-\s*"?0\.0\.0\.0:' "${FILES[@]}" 2>/dev/null || true)
if [ -n "$matches" ]; then
    echo "ERROR: explicit 0.0.0.0 host-port binding (use 127.0.0.1: or a specific IP, or omit):" >&2
    echo "$matches" | sed 's/^/  /' >&2
    rc=1
fi

# 2. Forbid mounting the raw docker socket directly into a service via a
#    volume bind. Match only on actual mount lines (start with `-`, host
#    path → container path), not comments or env-var values.
#
# Exempt services (specific, documented reasons):
#   - socket-proxy*   — the proxy itself; it's the ONE thing that should
#                       mount the raw socket.
#   - traefik         — docker provider auto-discovery is core Traefik
#                       behavior; the alternative (TCP API) duplicates
#                       what we already restrict via socket-proxy for
#                       Homepage. Out of scope to re-engineer.
#   - zabbix-agent /
#     zabbix-agent2   — privileged host-monitoring agent; the docker
#                       plugin only accepts unix:// endpoints, so a
#                       socat bridge would be needed and the user
#                       declared it unneeded (agent is privileged
#                       anyway).
#   - autoheal*       — the autoheal container needs the docker API to
#                       restart unhealthy peers. Could route through a
#                       socket-proxy in a future phase; tracked.
#
# Lines that begin with `#` (comments) are always skipped.
for f in "${FILES[@]}"; do
    bad=$(awk '
        # Strip leading whitespace once, look at the first non-whitespace char
        function trimmed(s,   t) { t = s; sub(/^[[:space:]]+/, "", t); return t }

        # Service block header: `  <name>:` at indent 2
        /^[[:space:]]{2}[a-zA-Z][a-zA-Z0-9_-]*:[[:space:]]*$/ {
            svc = $1; sub(":", "", svc)
            next
        }

        {
            line = trimmed($0)
            # Skip comments
            if (substr(line, 1, 1) == "#") next
            # Volume mount: starts with `- ` and contains the host:container socket pair
            if (line ~ /^-[[:space:]]+\/var\/run\/docker\.sock:\/var\/run\/docker\.sock/) {
                if (svc ~ /^socket-proxy/) next
                if (svc == "traefik") next
                if (svc == "zabbix-agent" || svc == "zabbix-agent2") next
                if (svc ~ /^autoheal/) next
                print FILENAME ":" NR " [" svc "]: " line
            }
        }
    ' "$f")
    if [ -n "$bad" ]; then
        echo "ERROR: raw /var/run/docker.sock mount on a non-exempt service in $f:" >&2
        echo "$bad" | sed 's/^/  /' >&2
        rc=1
    fi
done

# 3. (STRICT only) Forbid `image: ...:latest` / `:develop` / `:stable`.
#    During Phase 2a baseline, this is reported as a WARNING but doesn't
#    fail. Phase 2c flips STRICT=1 in the GitHub Actions workflow once
#    pinning is complete.
matches=$(grep -nE '^\s*image:\s+[^[:space:]]+:(latest|develop|stable)\s*$' "${FILES[@]}" 2>/dev/null || true)
if [ -n "$matches" ]; then
    if [ "$STRICT" = "1" ]; then
        echo "ERROR: unpinned image (use a specific semver tag):" >&2
        echo "$matches" | sed 's/^/  /' >&2
        rc=1
    else
        # Baseline-tolerant: emit a count to stderr but don't fail.
        count=$(echo "$matches" | wc -l | tr -d ' ')
        echo "WARN: $count unpinned image references (baseline-tolerant; STRICT=1 to enforce)" >&2
    fi
fi

exit "$rc"
