# Host → project mapping

Canonical: `scripts/projects.conf`. This file is a human-readable mirror.

| Host | Base path | Projects | Purpose |
|---|---|---|---|
| **server** (main NAS) | `/mnt/app/home/user/compose` | `edge` `monitor` `acquire` `manage` `serve-plex` `serve-books` `serve-games` `process` `personal` | Primary compose host (TrueNAS Scale appliance in my deployment). All public-facing services. DMZ-homed. Phase 4 (2026-05-11) restructured from 12 themed projects to 10 trust zones. |
| **cloud-server** | `/home/user/compose` | `zabbix` | Off-site VM running the Zabbix server stack. Separates monitoring from the host it monitors so an outage of `server` still notifies. In my deployment this is a Hetzner Cloud VM with the home WAN IP whitelisted on its firewall. |

## Project quick reference

Each compose file at the top has a two-line header (`# host:` / `# project:`) that names its host and a one-line purpose statement. Use that as the source of truth when in doubt. This table is for navigation only.

### `server` (main, post Phase 4)
- `edge/` — Public ingress (Traefik :443) + auth/security perimeter: oauth2-proxy, plex-oidc-bridge, CrowdSec + bouncer. Highest blast radius for misconfig but stateless.
- `monitor/` — Observability + ops: Zabbix proxy + monitor-mysql + agent2, uptime-kuma, postfix relay, rclone, autoheal sidecar, dozzle, organizr + homepage + socket-proxy-homepage.
- `acquire/` — VPN-fronted downloaders + indexers (highest risk class — fetches attacker-controlled content). gluetun ×3 + qBittorrent + qui + Prowlarr + autobrr + FlareSolverr + slskd + soularr + slskd-port-sync + SABnzbd + TheLounge.
- `manage/` — *arr managers: Sonarr ×2 (1080/4k), Radarr ×2 (1080/4k), Lidarr, Bazarr ×2, Aurral.
- `serve-plex/` — Plex + Seerr + Requestrr.
- `serve-books/` — Audiobookshelf, abs-tract, ReadMeABook, plex-scan-watcher, Shelfmark, Grimmory + MariaDB.
- `serve-games/` — RomM + MariaDB.
- `process/` — Post-processing + analytics: Tdarr, Whisper, Unpackerr, Kometa, Recyclarr, Fetcharr, Tautulli, Checkrr, Tracearr + TimescaleDB + Redis.
- `personal/` — High-data-sensitivity stacks: Immich (server, ML, postgres, redis, power-tools), Nextcloud + Postgres + Redis + clamav + elasticsearch. Per-app DB networks `internal: true`.

Pre-Phase-4 layout (12 themed projects: `nas` `sys` `monproxy` `media` `music` `abook` `ebook` `photo` `rpt` `files` `games`) is preserved in this repo's git history if you want to compare the older shape — see `git log` before the trust-zone restructure commit on `main`.

### `cloud-server` (off-site)
- `zabbix/` — Zabbix server + web + MySQL + agent + rclone + postfix. Includes `agentscripts/` (intentionally not included in this public mirror — the scripts are tightly coupled to specific environment details) that run on the **main server** via its Zabbix agent. The agentscripts shipping under `zabbix/` is intentional in the source repo since they're shared between server and agent.

## Why this matters

This repo holds compose definitions for **multiple hosts**. Running `docker compose up -d` against the wrong project on the wrong host creates stale containers and networks. The per-file `# host:` header at the top of each compose file makes the binding unambiguous, and `scripts/projects.conf` is what the helper scripts read to know which projects belong to the current `$HOSTNAME`.

If you're adapting this for a single host, you can collapse all projects onto one machine (most of the docker network topology stays exactly the same — only the host headers and `projects.conf` change).
