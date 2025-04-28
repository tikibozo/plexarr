# plexarr
One bozo's example of how to automate your entertainment.

So this is a sanitized version of what I'm running. My hope is someone getting started finds this and it helps them in some way. Linux filesystems, permissions, docker compose, networking, etc. knowledge is assumed. I did all this with a lot of searching around the internet to cobble everything together - so it's all out there.

In order to adapt this for your use it'll help to know some details about my topology so you can copy them or adjust as appropriate. While I've consolidated everything down to one router and one server (below), this was originally distributed such that storage + plex was on one system, and another system had all the arrs to manage media. Essentially which system you use the various compose projects on is up to you. Similarly, I moved monitoring into Azure with a local proxy, but you could either not use that stuff at all, or run the server on your network as I was initially doing.

Using Homepage inside Organizer to replace it's summary page is pretty slick it turns out:
![Dashboard using Homepage in Organizr](./homepage_organizr.png?raw=true "Dashboard using Homepage in Organizr")

## Hardware
From a network & hardware perspective it's straightforward:
Internet <-> PFSense <-> TrueNAS Scale
- [PFsense+ (Home/free)](https://www.netgate.com/pfsense-plus-software/software-types) on a [Protectli FW6](https://protectli.com/vault-6-port/)
- [TrueNAS Scale](https://www.truenas.com/truenas-scale) - [Custom 200TB build](https://www.truenas.com/community/threads/hw-build-review-truenas-scale-plex.109434/#post-755881)

## Software
On to the software stack. I've divided the system into multiple compose projects. This was initially for portability, so I could "down" a project on one system, copy the config files to another, and with an "up" have moved the whole stack somewhere else. Now that it's all on the same system, it also allows me to rebuild the media project without affecting user facing services.

Stack contents:
-  [media](https://github.com/tikibozo/plexarr/blob/main/media/docker-compose.yml): This is the main arr stack, which includes
    - [Radarr](https://radarr.video/) / [Sonarr](https://sonarr.tv/) / [Lidarr](https://lidarr.audio/) / [Arr Scripts](https://github.com/RandomNinjaAtk/arr-scripts) / [Huntarr](https://github.com/plexguide/Huntarr.io) - Media management
    - [Bazarr](https://www.bazarr.media/) / [Subcleaner](https://github.com/KBlixt/subcleaner) / [Whisper](https://github.com/ahmetoner/whisper-asr-webservice) - Subtitles
    - [Recyclarr](https://github.com/recyclarr/recyclarr) / [TRaSH Guides](https://trash-guides.info/) - Release picking optimizations 
    - [Prowlarr](https://github.com/prowlarr/prowlarr) / [FlareSolverr](https://github.com/FlareSolverr/FlareSolverr) - Indexer management
    - [Gluetun](https://github.com/qdm12/gluetun) / [GSP-Qbittorrent-Gluetun-sync-port-mod](https://github.com/t-anc/GSP-Qbittorent-Gluetun-sync-port-mod) - VPN
    - [Tautulli](https://tautulli.com/) - Plex monitoring/notifications
    - [Kometa](https://kometa.wiki/en/latest/) - Dynamic collections/overlays
    - [qBittorrent](https://www.qbittorrent.org/) / [SABnzbd](https://sabnzbd.org/) - Download
    - [Autobrr](https://autobrr.com/) / [TheLounge](https://thelounge.chat/) - IRC Announces
    - [Unpackerr](https://github.com/Unpackerr/unpackerr) - Archive extraction
    - [Tdarr](https://home.tdarr.io/) - Transcoding
    - [Organizr](https://github.com/causefx/Organizr) + [Homepage](https://github.com/benphelps/homepage) - Dashboard
- [nas](https://github.com/tikibozo/plexarr/blob/main/nas/docker-compose.yml): User facing services
    - [Plex](https://plex.tv) - Media server
    - [Overseerr](https://overseerr.dev/) - Web requests/notifications
    - [Requestrr](https://github.com/thomst08/requestrr) - Discord requests
    - [Wizarr](https://github.com/Wizarrrr/wizarr) - New user signup
    - [Traefik](https://github.com/traefik/traefik)  - Reverse proxy
- [sys](https://github.com/tikibozo/plexarr/blob/main/sys/docker-compose.yml): System services
    - [Postfix](https://github.com/loganmarchione/docker-postfixrelay) - SMTP relay
    - [Checkrr](https://github.com/aetaric/checkrr) - Bitrot detection & remediation 
    - [Rclone](https://rclone.org/) - Backups
- [mon](https://github.com/tikibozo/plexarr/blob/main/mon/docker-compose.yml)/[monproxy](https://github.com/tikibozo/plexarr/blob/main/monproxy/docker-compose.yml): Monitoring
    - [Zabbix](https://www.zabbix.com/) - Monitoring & alerting server
    - [Pushover](https://pushover.net/) - Mobile push notifications

A million thanks to the countless contributors to all of those amazing projects! $upport them if you can <3

## Filesystem
Here's how I've mapped storage hardware to functional usage:
- SSD (Mirrored)
    - /mnt/app/db - Docker config volumes, databases
    - /mnt/app/download - Temporary download directories by client
    - /mnt/app/docker - Docker service (images, etc.)
    - /mnt/app/home - Home dir with private version of this repo
    - /mnt/app/vm - VM image storage for Ubuntu VM w/ PIA client
- NVME
    - /mnt/transcode/plex - Plex transcoding temp storage
    - /mnt/transcode/tdarr - Tdarr transcoding temp storage
- HDDs (RAIDZ2)
    - /mnt/data/media - Media storage

## Random notes
If you're going to make use of this then it's best to go through the docker-compose.yml files in this repo to see what it's doing, and otherwise just look at the configs and take what's useful to you.

That said, there are some random bits of context or ideas that may help you, so in no particular order:
- I'm not sanitizing all the container config files/databases and including them here, but feel free to ask if you have a question about something that's not configured via the compose files. Some things I do have copies of in the repo for source control, which when editing I copy manually into place in their docker config/db volume. 
- Multiple SABnzbd instances. I found that I could get extra bandwidth out of having multiple usenet download instances. These are targeting 3 providers with each instance's server priority list the inverse of the other. I've also recently realized that I can use the client priority in the *arr's to dump content refreshes into one instance, flip that instance's priority to lowest, and not clog up the pipes for incoming user requests which then go to the ready instance.
- UID/GID. Most all the files/directories are configured to use docker:docker (999:999), though some containers prefer their config files to be owned by root.
- There are a bunch of dumb helper scripts in /scripts because I got tired of typing commands out. There's also nas-daily.sh which updates docker images (pull & up) and a script to update Azure firewall rules based on dynamic IP changes. Add your user account to the docker group so you don't have to sudo every docker command.
- 1080p & 4k *arr instances. This is the "old" way of partitioning 4k content. I prefer it since I don't often use 4k media (yet) and by having seperate instances it's easy to point dedicated Plex libraries at the 4k directories (and not share with Plex users.) Also Overseerr supports this setup and lights up additional support for requesting in 1080/standard and 4k when you add multiple instances and configure them for 4k. Plex's editions support (or simply transcoding hw heft) can alleviate the need for the addionional services, but extra sonarr/radarr instances are relatively cheap imho.
