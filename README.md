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
- [TrueNAS Scale](https://www.truenas.com/truenas-scale) — [Custom 400TB (raw, 250TB usable) build](https://www.truenas.com/community/threads/hw-build-review-truenas-scale-plex.109434/#post-755881)

## How this repo is organized

The compose stack is divided across **multiple hosts** and **multiple projects per host**. Each compose file at the top has a two-line header (`# host:` / `# project:`) that names its host and a one-line purpose statement — those headers are the authoritative source of truth. [`scripts/projects.conf`](./scripts/projects.conf) is what the helper scripts read to know which projects belong to the current `$HOSTNAME`. [HOSTS.md](./HOSTS.md) is a human-readable mirror of that mapping.

### Evolution: themed projects → trust zones

The original layout split services by *theme* — one project for user-facing stuff, another, "media" for the arr stack, "music", "abook", "photo", "sys", "rpt", etc. That made sense as a portability move (I could `down` a project on one host, copy the config, `up` it on another). But from a security perspective, this theme based organization ended up comingling services with different risk profiles on the same docker networks. For example the public-facing reverse proxy (huge blast radius) lived alongside the personal dashboard (tiny).

In May 2026 I restructured into **trust zones** — projects grouped by risk class and outbound-network needs, not by topic. Each zone has its own docker networks, and the higher-risk zones (anything that touches attacker-controlled content, like indexers and downloaders) sit on `internal: true` bridges with no host egress except via the zones they explicitly need to talk to. The was followed up with capability dropping, no-new-privileges, network isolation as well. See Hardening below for more on this.

If you want to compare the older shape, the 12-themed-project layout (`nas` `sys` `monproxy` `media` `music` `abook` `ebook` `photo` `rpt` `files` `games`) is preserved in this repo's git history before the Phase 4 commit on `main`.

### Current stack contents (by trust zone/project)

Main host `server` (TrueNAS Scale, runs everything user-facing):
- **[edge/](./edge/docker-compose.yml)** — Public ingress + auth/security perimeter
    - [Traefik](https://github.com/traefik/traefik) — Reverse proxy (the only thing other than Plex exposed to the WAN)
    - [oauth2-proxy](https://github.com/oauth2-proxy/oauth2-proxy) + [Plex OIDC Bridge](https://github.com/tikibozo/plex-oidc-bridge) — Plex-account-backed SSO for non-plex services
    - [CrowdSec](https://www.crowdsec.net/) + firewall bouncer — log-driven IP banning
    - [Wizarr](https://github.com/Wizarrrr/wizarr) Occasional new user signups
- **[monitor/](./monitor/docker-compose.yml)** — Observability
    - [Zabbix](https://www.zabbix.com/), [autoheal](https://github.com/willfarrell/docker-autoheal) Monitoring proxy + agent (server lives off-host, see below)
    - [Uptime Kuma](https://github.com/louislam/uptime-kuma) Monitor for the monitoring
    - [Dozzle](https://github.com/amir20/dozzle) Log wrangling
    - [Organizr](https://github.com/causefx/Organizr) + [Homepage](https://github.com/benphelps/homepage) Dashboard
    - [Postfix](https://github.com/bokysan/docker-postfix) SMTP relay
    - [rclone](https://rclone.org/) backups
- **[acquire/](./acquire/docker-compose.yml)** — VPN-fronted downloaders + indexers (highest risk class — fetches attacker-controlled content)
    - [Gluetun](https://github.com/qdm12/gluetun) ×3 — VPN egress
    - [qBittorrent](https://www.qbittorrent.org/) + [Qui](https://github.com/autobrr/qui) for torrents
    - [SABnzbd](https://sabnzbd.org/) for usenet
    - [slskd](https://github.com/slskd/slskd) + [Soularr](https://github.com/mrusse/soularr) — Soulseek bridge for Lidarr
    - [Prowlarr](https://github.com/Prowlarr/Prowlarr), [FlareSolverr](https://github.com/FlareSolverr/FlareSolverr) for indexer management
    - [autobrr](https://autobrr.com/), [TheLounge](https://thelounge.chat/) for IRC releases
- **[manage/](./manage/docker-compose.yml)** — *arr managers
    - [Sonarr](https://sonarr.tv/) ×2 (1080/4k) TV
    - [Radarr](https://radarr.video/) ×2 (1080/4k) Movies
    - [Lidarr](https://lidarr.audio/) + [Aurral](https://github.com/lklynet/aurral) Audio
    - [Bazarr](https://www.bazarr.media/) ×2 Subtitles
- **[serve-plex/](./serve-plex/docker-compose.yml)** — Plex + request frontends
    - [Plex](https://plex.tv) Media server
    - [Seerr](https://seerr.dev/) + [Requestrr](https://github.com/thomst08/requestrr) User requests
- **[serve-books/](./serve-books/docker-compose.yml)** — Audiobooks + ebooks
    - [ReadMeABook](https://github.com/kikootwo/readmeabook) + [Audiobookshelf](https://github.com/advplyr/audiobookshelf) + [abs-tract](https://github.com/ahobsonsayers/abs-tract) for Audiobooks
    - [Shelfmark](https://github.com/calibrain/shelfmark), [Grimmory](https://github.com/grimmory-tools/grimmory) for eBooks
- **[serve-games/](./serve-games/docker-compose.yml)** — Retro gaming
    - [RomM](https://github.com/rommapp/romm) for game organization/browsing/playing
- **[process/](./process/docker-compose.yml)** — Post-processing + analytics
    - [Tdarr](https://home.tdarr.io/) for download post-processing to expected formats
    - [Whisper](https://github.com/ahmetoner/whisper-asr-webservice) to create otherwise-unavailable subtitles
    - [Unpackerr](https://github.com/Unpackerr/unpackerr) for archive management
    - [Kometa](https://kometa.wiki/) - collections
    - [Recyclarr](https://github.com/recyclarr/recyclarr) TRaSH guide deployment
    - [Fetcharr](https://github.com/egg82/fetcharr) to keep things fresh
    - [Tautulli](https://tautulli.com/) + [Tracearr](https://github.com/connorgallopo/tracearr) for reporting
    - [Checkrr](https://github.com/aetaric/checkrr) bitrot detection & remediation (so far unneeded on zfs with ecc)
- **[personal/](./personal/docker-compose.yml)** — High-data-sensitivity stacks (private docker networks, no cross-talk by default)
    - [Immich](https://immich.app/) — Self-hosted photo/video
    - [Nextcloud](https://nextcloud.com/) + Postgres + Redis + ClamAV + Elasticsearch

Off-site host `cloud-server` (small cloud VM, exists so an outage of `server` still notifies):
- **[zabbix/](./zabbix/docker-compose.yml)** — Zabbix server stack
    - Zabbix server + web + MySQL + agent + postfix + rclone

A million thanks to the countless contributors to all of those amazing projects! $upport them if you can <3

## Filesystem
Here's how I've mapped storage hardware to functional usage:
- SSD - Apps (Mirrored)
    - /mnt/app/db — Docker config volumes, databases
    - /mnt/app/docker — Docker service (images, etc.)
    - /mnt/app/home — Home dir with private version of this repo
    - /mnt/app/vm — VM image storage
- SSD - Downloads (Single)
    - /mnt/download — Temporary download directories by client (sabnzbd, qbittorrent, etc.)
    - /mnt/transcode/plex — Plex transcoding temp storage
    - /mnt/transcode/tdarr — Tdarr transcoding temp storage
- HDDs - Data (RAIDZ2 w/ NVMEs for ZFS cache)
    - /mnt/data/media — Media storage
    - /mnt/data2/media — Media storage

## Hardening

### Overview
Every container in this repo runs with `no-new-privileges:true` and `cap_drop: [ALL]`, with the small set of Linux capabilities each image actually needs added back explicitly. There's also a layered network design (internal/egress bridges per zone), SOPS-encrypted secrets, image pinning, healthchecks + an autoheal sidecar, and a handful of hard-earned gotchas.

This stack started as a vanilla "stick everything in compose and let it run as root with default Docker capabilities" homelab. Over a few months of iterative passes (Phases 5, 6a/b/c, etc.) it picked up:

- `cap_drop: [ALL]` + targeted `cap_add` per service
- `no-new-privileges:true` everywhere except a couple of services that genuinely need setuid
- `internal: true` docker networks for any zone that doesn't need direct host egress
- SOPS+age encryption for every secret in the repo
- Image pinning (`semver@sha256:...`) so Renovate PRs stay reviewable
- Healthchecks on long-lived services with an autoheal sidecar that restarts unhealthy containers
- A small library of triage rules for the specific classes of breakage these patterns introduce

This section explains the patterns and the *why* behind each one — if you're copying anything from this repo into your own stack, this is the portion to read alongside the compose files themselves.

### Anchors: `x-defaults` and `x-hardened`

Each compose file declares two YAML anchors at the top and `<<: *hardened` on every service:

```yaml
x-defaults: &defaults
  restart: unless-stopped
  security_opt:
    - no-new-privileges:true
  logging: &log
    driver: json-file
    options:
      max-size: "10m"
      max-file: "3"

x-hardened: &hardened
  restart: unless-stopped
  security_opt:
    - no-new-privileges:true
  cap_drop:
    - ALL
  logging: *log
```

Anchors are duplicated **per compose file**, not pulled in from a central `compose.common.yml`, because compose `include:` does not preserve YAML anchors across files (verified against compose v2.38.1 in May 2026). The alternative — using `extends:` — works but is noisier per-service than `<<: *hardened`.

`x-defaults` is the older, looser baseline (no cap drop); `x-hardened` is what every service uses post Phase 5. Both are kept because some scratch services start with `<<: *defaults` and graduate to `<<: *hardened` once their capability needs are understood.

### `cap_drop: [ALL]` + targeted `cap_add`

By default Docker grants containers 14 Linux capabilities. Most images don't need most of them. Dropping all and adding back only what's needed shrinks the container's privilege surface considerably (e.g. removing `SYS_PTRACE`, `MKNOD`, `NET_RAW`, `SYS_CHROOT`, etc. when they're not used).

Common "recipes" you'll see repeated across services in this repo:

- **LSIO 5-cap baseline** — for [linuxserver.io](https://www.linuxserver.io/) images and anything else that uses an s6/gosu init to chown `/config` and drop to a non-root user. The init needs:
    ```yaml
    cap_add:
      - CHOWN
      - FOWNER
      - DAC_OVERRIDE
      - SETUID
      - SETGID
    ```
    Some images need a 6th (`NET_BIND_SERVICE` for DLNA stack binding UDP 1900 inside a container; `KILL` for services that signal child processes).
- **3-cap "drop to user" baseline** — for images that start as root and `su-exec`/`gosu` to a non-root user without doing chowns:
    ```yaml
    cap_add:
      - SETUID
      - SETGID
      - DAC_OVERRIDE  # only if bind-mounted host dirs aren't already owned by the runtime UID
    ```
- **NET_ADMIN + NET_RAW** — for VPN containers (Gluetun) and the CrowdSec firewall bouncer.

The principle: start from `cap_drop: [ALL]`, watch the container fail, add back the one capability that fixed it, and document *why* in a comment next to the `cap_add`. The capability list is small enough to grok one entry at a time, but the reasoning fades fast — comments age better than memory.

#### The triage rule (silent-breakage gotcha)

The most painful class of failure from cap_drop is **silent breakage where a container appears to run but quietly fails to write somewhere it expected to**.

Triage rule Claude internalized:

> **uid 0 inside container + CapEff = 0 + read/write bind into a non-root-owned host directory → likely silent breakage.**

When a process runs as root *and* has no capabilities, it loses the DAC bypass that normally lets root read/write any file regardless of mode. If a host directory is `0700 plex:plex` and the container's root tries to read it, the read fails with `EACCES` — and depending on the application, that can manifest as logs going to /dev/null, scheduled jobs silently no-op'ing, or a healthcheck passing while the actual workload is broken.

Two real examples from this stack:

- **rclone backups** — broke after the cap_drop pass; rclone was reading source trees with mode `0770 plex:plex` from container-root with no DAC bypass. Fix: `cap_add: [DAC_READ_SEARCH]` (read-only is enough since rclone reads from `/data` and writes to a separate destination).
- **Kometa log rotation** — silently failed every daily run for three days post-cap_drop. Kometa rotates `/config/logs/meta-*.log` inside a directory owned by plex:plex 0755 on the host; container root couldn't `rename(2)` without DAC override. Fix: `cap_add: [DAC_OVERRIDE]` — needs the *write* variant because rotation is a write operation.

Use `DAC_READ_SEARCH` when the container only needs to read; `DAC_OVERRIDE` when it also needs to write. Granting only what's needed keeps the principle intact.

### `no-new-privileges:true`

Set on every service. Blocks the `setuid` bit from elevating privileges — so even if an attacker gets shell in a container, they can't run `mount`/`ping`/etc. to gain capabilities the container wasn't started with.

Two documented exceptions in this repo:
- **zabbix-agent** — uses setuid `fping` for ICMP host availability monitoring. Adding `no-new-privileges` here silently broke ICMP checks; the agent kept running but every ping returned "permission denied". The agent runs in a constrained network namespace anyway, so the trade is acceptable. (See `feedback_zabbix_proxy_nnp_breaks_icmp.md` in my private notes — that's the lesson commit that made me write this section.)
- Any container with `cap_add: [NET_RAW]` for similar reasons.

If you're copying from this repo and your version of an image bundles a different ICMP helper, recheck.

### SOPS + age secrets pipeline

Every secret in this repo is encrypted at rest with [SOPS](https://github.com/getsops/sops) using [age](https://age-encryption.org/) recipients. See [`common/secrets/README.md`](./common/secrets/README.md) for the layout. The short version:

- `common/secrets/*.sops.yaml` — checked-in encrypted dotenvs
- `common/secrets/.runtime/*.env` — decrypted plaintext, gitignored, materialized at compose-up time, mode 0600
- Each service that needs secrets references the runtime path via `env_file:`
- `scripts/dco` and `scripts/up` wrap `docker compose` and call `decrypt_secrets` before any subcommand that needs them (`up`, `restart`, `create`, `run`). Decryption is mtime-cached so steady-state is fast.

The age **private** key lives at `~/.config/sops/age/keys.txt` (mode 0600) on each authorized host plus a backup in 1Password. The age **public** key is in the repo root's `.sops.yaml` so anyone with the private key can re-encrypt with `sops updatekeys`.

The encrypted `*.sops.yaml` files themselves are intentionally not included in this public mirror — they'd be useless to anyone but me (encrypted to my age recipients) and they'd add noise without value. If you're bootstrapping your own version: generate an age keypair (`age-keygen -o ~/.config/sops/age/keys.txt`), put the **public** key in `.sops.yaml` at the repo root with a `path_regex` matching `common/secrets/.*\.sops\.yaml$`, and `sops -e -i common/secrets/yourstack.sops.yaml`.

One nuance: the SOPS pipeline is per-host. On hosts that don't run any project referencing `common/secrets/.runtime/...`, `decrypt_secrets` short-circuits and returns immediately — this matters because the official `mozilla/sops` docker image is amd64-only, and you don't want it to be a hard dependency on arm64 boxes that have no secrets to decrypt.

### Image pinning

Two formats used in this repo:

- `image: foo/bar:1.2.3@sha256:abc123...` — semver tag pinned to a specific digest. Renovate (the bot I use for dependency PRs) writes PRs against the semver part, which includes release notes from the upstream. The digest pin makes the build reproducible.
- `image: foo/bar:latest@sha256:abc123...` — used for images that don't publish semver tags. Less informative when Renovate PRs an update, but still reproducible.

Renovate's `digest@sha256` updates and semver updates are configured to be grouped where it makes sense (e.g. all linuxserver.io image updates in one PR per week) so the PR firehose stays manageable. See `renovate.json` for the rules.

### Healthchecks + autoheal opt-in

Many services define a `healthcheck:` (or inherit a sensible one from the image). For services where an unhealthy state is recoverable by a restart, opt them into the autoheal sidecar by adding a label:

```yaml
labels:
  - "autoheal=true"
```

The [autoheal](https://github.com/willfarrell/docker-autoheal) sidecar in `monitor/` watches for containers with `autoheal=true` that have been unhealthy for too long and restarts them. It is **opt-in**, not opt-out — a healthcheck failing on a service that wasn't designed for restart-recovery (e.g. a database doing a long migration) shouldn't be auto-bounced.

Two healthcheck gotchas I've hit:

- **`CMD-SHELL` invokes `/bin/sh`, not bash** — if your healthcheck uses `/dev/tcp/...` or other bashisms, use `["CMD", "bash", "-c", "..."]` explicitly. Otherwise it fails silently with the dash error swallowed.
- **Healthchecks during long-running rescans** — slskd does periodic full filesystem rescans during which the HTTP API becomes unresponsive. A strict healthcheck will mark the container unhealthy and (if `autoheal=true`) loop-restart it forever. Build leniency in (longer timeouts, retries, or a more specific health probe).

### Network design: zones and `internal: true`

Each trust zone has its own set of docker networks. The naming convention:

- `<zone>_ingress` — only `edge/` has this; it's where the public Traefik routes inbound
- `<zone>_internal` — inter-service control plane within the zone; `internal: true` means **no host egress** on this network
- `<zone>_egress` — bridge network with host egress for services that need outbound (TRaSH-Guides repo pulls, GitHub API calls, etc.)

By splitting "talks to peers" from "reaches the internet" into separate networks, a compromised service inside an `_internal` zone has to also be attached to an `_egress` network to exfil — and most services in this repo aren't.

#### The `internal: true` + port-publishing gotcha

If a container is attached **only** to `internal: true` networks, Docker silently drops the port-publishing NAT for that container — `ports: ["8080:8080"]` becomes a no-op. Always pair an `internal: true` attachment with at least one bridge network if you also publish ports. The bridge can be a service-specific bridge that has no other members — its only job is to keep the NAT path intact.

The reverse problem: services on `internal: true` networks **cannot resolve host DNS** (which made my `unpackerr` config silently break for 36 hours during Phase 6c when I left `servername.mylocal:N` URLs in the env vars after flipping `arr_control` to internal). Use **container names**, not host DNS, for cross-service URLs once a zone is internal.

### Putting it together

The pattern that emerged for adding a new service to this stack:

1. Pick the trust zone (which compose file it belongs in).
2. Start with `<<: *hardened` — `cap_drop: [ALL]`, `no-new-privileges:true`, json-file logging caps.
3. Boot it. If it crashes, look at the logs for the missing capability and add it back with a comment explaining why.
4. If it appears to run but does nothing useful, apply the triage rule from above — silent breakage is almost always a missing DAC capability when the container runs as root.
5. Pick a network attachment that's the minimum it needs (internal for control plane, egress only if it talks to the outside world).
6. Add a healthcheck if the image doesn't have one. Add `autoheal=true` only if restart-recovery actually works for that service.
7. Pin the image with `@sha256:...`.
8. If it needs secrets, add them to a `common/secrets/<zone>.sops.yaml` and reference `../common/secrets/.runtime/<zone>.env` via `env_file:`.

That's the whole playbook. Everything in the compose files is an instance of it.

## Random notes
If you're going to make use of this then it's best to go through the docker-compose.yml files in this repo to see what it's doing, and otherwise just look at the configs and take what's useful to you.

That said, there are some random bits of context or ideas that may help you, so in no particular order:
- I'm not sanitizing all the container config files/databases and including them here, but feel free to ask if you have a question about something that's not configured via the compose files. Some things I do have copies of in the repo for source control, which when editing I copy manually into place in their docker config/db volume.
- UID/GID. Most all the files/directories are configured to use plex:plex on my system (uid 3001 in the source repo; sanitized to 999 here), though some containers prefer their config files to be owned by root.
- There are a bunch of dumb helper scripts in `scripts/` because I got tired of typing commands out. `scripts/up`, `scripts/dco`, and `scripts/update-docker-images` are the main entry points — they read `scripts/projects.conf` to know which projects belong on the current host, handle SOPS decryption, and ensure external docker networks exist. Add your user account to the docker group so you don't have to sudo every docker command.
- 1080p & 4k *arr instances. This is the "old" way of partitioning 4k content. I prefer it since I don't often use 4k media (yet) and by having separate instances it's easy to point dedicated Plex libraries at the 4k directories (and not share with Plex users.) Also Seerr supports this setup and lights up additional support for requesting in 1080/standard and 4k when you add multiple instances and configure them for 4k. Plex's editions support (or simply transcoding hw heft) can alleviate the need for the additional services, but extra sonarr/radarr instances are relatively cheap imho.
- If you're adapting this for a single host, you can collapse all projects onto one machine — most of the docker network topology stays exactly the same, only the host headers and `scripts/projects.conf` change.
