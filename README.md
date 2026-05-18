# plexarr
One bozo's example of how to automate your entertainment.

So this is a sanitized version of what I'm running. My hope is someone getting started finds this and it helps them in some way. Linux filesystems, permissions, docker compose, networking, etc. knowledge is assumed. I did all this with a lot of searching around the internet to cobble everything together — so it's all out there.

In order to adapt this for your use it'll help to know some details about my topology so you can copy them or adjust as appropriate. While the bulk of services live on one TrueNAS Scale box, monitoring lives off-site on a cheap cloud VM, and there's a small Raspberry Pi handling smart-home stuff. See [HOSTS.md](./HOSTS.md) for the host → project map.

Using Homepage inside Organizr to replace its summary page is pretty slick it turns out:
![Dashboard using Homepage in Organizr](./homepage_organizr.png?raw=true "Dashboard using Homepage in Organizr")

## Hardware
From a network & hardware perspective it's straightforward:
Internet <-> PFSense <-> TrueNAS Scale
- [PFsense+ (Home/free)](https://www.netgate.com/pfsense-plus-software/software-types) on a [Protectli FW6](https://protectli.com/vault-6-port/)
- [TrueNAS Scale](https://www.truenas.com/truenas-scale) — [Custom 200TB build](https://www.truenas.com/community/threads/hw-build-review-truenas-scale-plex.109434/#post-755881)

## How this repo is organized

The compose stack is divided across **multiple hosts** and **multiple projects per host**. Each compose file at the top has a two-line header (`# host:` / `# project:`) that names its host and a one-line purpose statement — those headers are the authoritative source of truth. [`scripts/projects.conf`](./scripts/projects.conf) is what the helper scripts read to know which projects belong to the current `$HOSTNAME`. [HOSTS.md](./HOSTS.md) is a human-readable mirror of that mapping.

### Evolution: themed projects → trust zones

The original layout split services by *theme* — "nas" for user-facing stuff, "media" for the *arr stack, "music", "abook", "photo", "sys", "rpt", etc. That made sense as a portability move (I could `down` a project on one host, copy the config, `up` it on another). But once everything settled onto one host, the theme-based split stopped paying for itself. Worse, it scattered services with very different *blast radii* into the same project: the public-facing reverse proxy (huge blast radius) lived alongside the personal dashboard (tiny) inside `nas/`.

In **Phase 4 (May 2026)** I restructured into **trust zones** — projects grouped by risk class and outbound-network needs, not by topic. Each zone has its own docker networks, and the higher-risk zones (anything that touches attacker-controlled content, like indexers and downloaders) sit on `internal: true` bridges with no host egress except via the zones they explicitly need to talk to. The trust-zone layout also lined up cleanly with **Phase 5/6 hardening** (capability dropping, no-new-privileges, network isolation) — see [HARDENING.md](./HARDENING.md).

If you want to compare the older shape, the 12-themed-project layout (`nas` `sys` `monproxy` `media` `music` `abook` `ebook` `photo` `rpt` `files` `games` `x`) is preserved in this repo's git history before the Phase 4 commit on `main`.

### Current stack contents (post Phase 4, by trust zone)

Main host `server` (TrueNAS Scale, runs everything user-facing):
- **[edge/](./edge/docker-compose.yml)** — Public ingress + auth/security perimeter
    - [Traefik](https://github.com/traefik/traefik) — Reverse proxy (the only thing exposed to the WAN)
    - [oauth2-proxy](https://github.com/oauth2-proxy/oauth2-proxy) + [Plex OIDC Bridge](https://github.com/Blacktirion/plex-oidc-bridge) — Plex-account-backed SSO
    - [CrowdSec](https://www.crowdsec.net/) + firewall bouncer — log-driven IP banning
- **[monitor/](./monitor/docker-compose.yml)** — Observability + ops glue
    - [Zabbix](https://www.zabbix.com/) proxy + agent (server lives off-host, see below)
    - [Uptime Kuma](https://github.com/louislam/uptime-kuma), [Dozzle](https://github.com/amir20/dozzle), [Organizr](https://github.com/causefx/Organizr) + [Homepage](https://github.com/benphelps/homepage)
    - [Postfix](https://github.com/bokysan/docker-postfix) SMTP relay, [rclone](https://rclone.org/) backups, [autoheal](https://github.com/willfarrell/docker-autoheal)
- **[acquire/](./acquire/docker-compose.yml)** — VPN-fronted downloaders + indexers (highest risk class — fetches attacker-controlled content)
    - [Gluetun](https://github.com/qdm12/gluetun) ×3 — VPN egress
    - [qBittorrent](https://www.qbittorrent.org/) + [Qui](https://github.com/autobrr/qui), [SABnzbd](https://sabnzbd.org/)
    - [Prowlarr](https://github.com/Prowlarr/Prowlarr), [autobrr](https://autobrr.com/), [FlareSolverr](https://github.com/FlareSolverr/FlareSolverr), [TheLounge](https://thelounge.chat/)
    - [slskd](https://github.com/slskd/slskd) + [Soularr](https://github.com/mrusse/soularr) — Soulseek bridge for Lidarr
- **[manage/](./manage/docker-compose.yml)** — *arr managers
    - [Sonarr](https://sonarr.tv/) ×2 (1080/4k), [Radarr](https://radarr.video/) ×2 (1080/4k), [Lidarr](https://lidarr.audio/), [Bazarr](https://www.bazarr.media/) ×2, [Aurral](https://github.com/lklynet/aurral)
- **[serve-plex/](./serve-plex/docker-compose.yml)** — Plex + request frontends
    - [Plex](https://plex.tv), [Seerr](https://seerr.dev/), [Requestrr](https://github.com/thomst08/requestrr)
- **[serve-books/](./serve-books/docker-compose.yml)** — Audiobooks + ebooks
    - [Audiobookshelf](https://github.com/advplyr/audiobookshelf), [abs-tract](https://github.com/arranHS/abs-tract), [ReadMeABook](https://github.com/kikootwo/readmeabook), [plex-scan-watcher](https://github.com/kikootwo/plex-scan-watcher), Shelfmark, Grimmory + MariaDB
- **[serve-games/](./serve-games/docker-compose.yml)** — Retro gaming
    - [RomM](https://github.com/rommapp/romm) + MariaDB
- **[process/](./process/docker-compose.yml)** — Post-processing + analytics
    - [Tdarr](https://home.tdarr.io/), [Whisper](https://github.com/ahmetoner/whisper-asr-webservice), [Unpackerr](https://github.com/Unpackerr/unpackerr)
    - [Maintainerr](https://github.com/jorenn92/maintainerr), [Kometa](https://kometa.wiki/), [Recyclarr](https://github.com/recyclarr/recyclarr), [Fetcharr](https://github.com/egg82/fetcharr)
    - [Tautulli](https://tautulli.com/), [Checkrr](https://github.com/aetaric/checkrr)
    - [Tracearr](https://github.com/connorgallopo/tracearr) + TimescaleDB + Redis
- **[personal/](./personal/docker-compose.yml)** — High-data-sensitivity stacks (private docker networks, no cross-talk by default)
    - [Immich](https://immich.app/) — Self-hosted photo/video
    - [Nextcloud](https://nextcloud.com/) + Postgres + Redis + ClamAV + Elasticsearch
    - [Vikunja](https://vikunja.io/) — Self-hosted todo/projects
- **[misc/](./misc/docker-compose.yml)** — Personal/internal media + small utilities
    - [Jellyfin](https://jellyfin.org/) — Internal media server (Plex is the user-facing one)
    - [gallery-dl](https://github.com/mikf/gallery-dl)

Off-site host `cloud-server` (small cloud VM, exists so an outage of `server` still notifies):
- **[zabbix/](./zabbix/docker-compose.yml)** — Zabbix server stack
    - Zabbix server + web + MySQL + agent + postfix + rclone

A million thanks to the countless contributors to all of those amazing projects! $upport them if you can <3

## Filesystem
Here's how I've mapped storage hardware to functional usage:
- SSD (Mirrored)
    - /mnt/app/db — Docker config volumes, databases
    - /mnt/app/docker — Docker service (images, etc.)
    - /mnt/app/home — Home dir with private version of this repo
    - /mnt/app/vm — VM image storage
- SSD (Downloads)
    - /mnt/download — Temporary download directories by client (sabnzbd, qbittorrent, etc.)
- NVME
    - /mnt/transcode/plex — Plex transcoding temp storage
    - /mnt/transcode/tdarr — Tdarr transcoding temp storage
- HDDs (RAIDZ2)
    - /mnt/data/media — Media storage

## Hardening

Every container in this repo runs with `no-new-privileges:true` and `cap_drop: [ALL]`, with the small set of Linux capabilities each image actually needs added back explicitly. There's also a layered network design (internal/egress bridges per zone), SOPS-encrypted secrets, image pinning, healthchecks + an autoheal sidecar, and a handful of hard-earned gotchas. [HARDENING.md](./HARDENING.md) walks through the patterns and explains the *why* behind each one — including the triage rule I use when a container silently breaks after a hardening pass.

## Random notes
If you're going to make use of this then it's best to go through the docker-compose.yml files in this repo to see what it's doing, and otherwise just look at the configs and take what's useful to you.

That said, there are some random bits of context or ideas that may help you, so in no particular order:
- I'm not sanitizing all the container config files/databases and including them here, but feel free to ask if you have a question about something that's not configured via the compose files. Some things I do have copies of in the repo for source control, which when editing I copy manually into place in their docker config/db volume.
- UID/GID. Most all the files/directories are configured to use plex:plex on my system (uid 3001 in the source repo; sanitized to 999 here), though some containers prefer their config files to be owned by root.
- There are a bunch of dumb helper scripts in `scripts/` because I got tired of typing commands out. `scripts/up`, `scripts/dco`, and `scripts/update-docker-images` are the main entry points — they read `scripts/projects.conf` to know which projects belong on the current host, handle SOPS decryption, and ensure external docker networks exist. Add your user account to the docker group so you don't have to sudo every docker command.
- 1080p & 4k *arr instances. This is the "old" way of partitioning 4k content. I prefer it since I don't often use 4k media (yet) and by having separate instances it's easy to point dedicated Plex libraries at the 4k directories (and not share with Plex users.) Also Seerr supports this setup and lights up additional support for requesting in 1080/standard and 4k when you add multiple instances and configure them for 4k. Plex's editions support (or simply transcoding hw heft) can alleviate the need for the additional services, but extra sonarr/radarr instances are relatively cheap imho.
- If you're adapting this for a single host, you can collapse all projects onto one machine — most of the docker network topology stays exactly the same, only the host headers and `scripts/projects.conf` change.
