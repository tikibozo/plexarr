#!/bin/bash
# Shared config loader for compose scripts.
#
# Uses BASH_SOURCE[0] (the path of THIS file, common.sh) rather than $0
# (the parent script's path) so common.sh can be sourced from any depth
# in the repo tree (e.g. zabbix/agentscripts/arr-monitor.sh sources
# ../../scripts/common.sh and still resolves projects.conf correctly).
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
CONF="$SCRIPT_DIR/projects.conf"

LINE=$(grep "^$HOSTNAME:" "$CONF")

if [ -z "$LINE" ]; then
    echo "No config for host: $HOSTNAME"
    exit 1
fi

BASE=$(echo "$LINE" | cut -d: -f2)
PROJECTS=$(echo "$LINE" | cut -d: -f3)

# Phase 4: declarative list of external networks that compose projects
# reference via `networks: <name>: { external: true }`. TrueNAS periodically
# clobbers docker config (during TrueNAS app updates etc.) — we cannot rely
# on one-time bootstrap. ensure_external_networks() is idempotent and called
# from `up`, `dco` (for up/restart/create/run actions), and update-docker-images.
# server's truenas-postinit also calls scripts/up, so postinit gets
# coverage transitively.
#
# Format: <name>:<type> where type is "bridge" (default) or "internal"
# (same as bridge but with --internal, no host egress). Phase 6 flips
# the medium-trust networks to "internal".
EXTERNAL_NETWORKS_SERVER=(
    # Kept as a bridge — Plex and Jellyfin both retain nas_default as
    # their bridge attachment for port-publishing NAT (Plex would need a
    # restart to swap, and Jellyfin has no zone-egress to move to).
    # Other services dropped nas_default in 6b-1.
    "nas_default:bridge"

    # Ingress
    "edge_ingress:bridge"
    "edge_internal:internal"           # flipped in Phase 6b (2026-05-15)

    # Inter-service control planes
    "arr_control:internal"             # flipped in Phase 6c (2026-05-15)
    "serve_plex_api:internal"          # flipped in Phase 6c (2026-05-15)
    "mon_internal:internal"            # flipped in Phase 6a (2026-05-11)

    # Egress (regular bridges)
    "arr_egress:bridge"
    "vpn_egress:bridge"
    "mon_egress:bridge"
    "personal_egress:bridge"
    "misc_egress:bridge"
    "edge_egress:bridge"               # crowdsec + plex-oidc-bridge outbound

    # Per-app DB isolation (internal at create time)
    "process_tracearr_internal:internal"
    "process_subarr_internal:internal"
    "personal_immich_db:internal"
    "personal_nextcloud_db:internal"
    "serve_books_grimmory_db:internal"
    "serve_games_db:internal"
)

# cloud-server and home-server don't get the new zone networks — they have their own
# project layouts (zabbix/ and home/) and aren't part of the server restructure.
EXTERNAL_NETWORKS_CLOUD_SERVER=()
EXTERNAL_NETWORKS_HOME_SERVER=()

ensure_external_networks() {
    local -n nets
    case "$HOSTNAME" in
        server)  nets=EXTERNAL_NETWORKS_SERVER ;;
        cloud-server) nets=EXTERNAL_NETWORKS_CLOUD_SERVER ;;
        home-server)       nets=EXTERNAL_NETWORKS_HOME_SERVER ;;
        *)         return 0 ;;
    esac

    local entry name type
    for entry in "${nets[@]}"; do
        name="${entry%%:*}"
        type="${entry##*:}"
        if docker network inspect "$name" >/dev/null 2>&1; then
            continue
        fi
        if [ "$type" = "internal" ]; then
            docker network create --internal "$name" >/dev/null
        else
            docker network create "$name" >/dev/null
        fi
    done
}

# Decrypt SOPS-encrypted secrets into common/secrets/.runtime/.
#
# Each common/secrets/<name>.sops.yaml is decrypted via the ghcr.io/getsops/sops
# Docker image (no SOPS install on the host) into common/secrets/.runtime/<name>.env
# in dotenv (KEY=value) format, suitable for compose `env_file:` directives.
#
# Materialized files persist across compose invocations because docker reads
# the secret source file at container-create time and the path must remain
# valid for restarts/recreates. They are gitignored. Permissions are 0700 on
# .runtime/ and 0600 on each .env file inside.
#
# Idempotent — safe to call from any script that brings services up.
# No-op if common/secrets/ doesn't exist or contains no .sops.yaml files.
decrypt_secrets() {
    local sops_dir="$BASE/common/secrets"
    [ -d "$sops_dir" ] || return 0

    # Any .sops.yaml files to process?
    local found=0
    for f in "$sops_dir"/*.sops.yaml; do
        [ -e "$f" ] && { found=1; break; }
    done
    [ $found -eq 1 ] || return 0

    # Skip the whole step if none of this host's projects reference the
    # decrypted runtime dir. home-server (home/) is the case in point: it has no
    # SOPS-encrypted secrets, so there's no reason to pull and run the
    # ghcr.io/getsops/sops docker image. (getsops is multi-arch — amd64
    # and arm64 — so it would run fine on home-server; this skip is purely to
    # avoid a needless image pull and docker invocation.) Detection is
    # generic: grep the compose files for the runtime path.
    local needs_secrets=0 p
    for p in $PROJECTS; do
        if [ -f "$BASE/$p/docker-compose.yml" ] && \
           grep -q "common/secrets/\.runtime/" "$BASE/$p/docker-compose.yml" 2>/dev/null; then
            needs_secrets=1
            break
        fi
    done
    [ $needs_secrets -eq 1 ] || return 0

    local age_dir="$HOME/.config/sops/age"
    if [ ! -f "$age_dir/keys.txt" ]; then
        echo "decrypt_secrets: missing $age_dir/keys.txt — cannot decrypt SOPS files" >&2
        return 1
    fi

    mkdir -p "$sops_dir/.runtime"
    chmod 700 "$sops_dir/.runtime"
    local prev_umask
    prev_umask=$(umask)
    umask 077

    local rc=0
    for f in "$sops_dir"/*.sops.yaml; do
        [ -f "$f" ] || continue
        # Skip yaml-structured files — they're handled by decrypt_yaml_to
        # (output-type yaml, written to a service-specific path).
        case "$(basename "$f")" in
            traefik-middlewares.sops.yaml) continue ;;
        esac
        local base
        base="$(basename "$f" .sops.yaml)"
        local out="$sops_dir/.runtime/${base}.env"
        # Skip if the .runtime file is up to date — `-nt` is "newer than",
        # so this is true iff $out exists and was modified after $f. Each
        # docker-run for sops costs ~400ms; this skips it on steady-state
        # invocations (no secret changed since last decrypt).
        if [ -f "$out" ] && [ "$out" -nt "$f" ]; then
            continue
        fi
        if ! docker run --rm \
            --entrypoint sops \
            -v "$sops_dir:/secrets:ro" \
            -v "$age_dir:/age:ro" \
            -e SOPS_AGE_KEY_FILE=/age/keys.txt \
            ghcr.io/getsops/sops:v3.13.1 \
            -d --output-type dotenv "/secrets/$(basename "$f")" > "$out.tmp"; then
            echo "decrypt_secrets: failed to decrypt $f" >&2
            rm -f "$out.tmp"
            rc=1
            continue
        fi
        mv "$out.tmp" "$out"
        chmod 600 "$out"
    done

    umask "$prev_umask"
    return $rc
}

# Decrypt a single SOPS-encrypted secret file and export its KEY=VALUE pairs
# into the calling shell's environment. No `.runtime/` plaintext file written —
# secrets exist only in the script's process env and disappear when it exits.
#
# Usage:
#   source "$(dirname "$(readlink -f "$0")")/common.sh"
#   sops_export_env scripts.sops.yaml
#
# After this returns, $CLIENT_ID etc. are set for the rest of the script.
sops_export_env() {
    local file="$1"
    local sops_dir="$BASE/common/secrets"
    if [ ! -f "$sops_dir/$file" ]; then
        echo "sops_export_env: $sops_dir/$file not found" >&2
        return 1
    fi
    local age_dir="$HOME/.config/sops/age"
    if [ ! -f "$age_dir/keys.txt" ]; then
        echo "sops_export_env: missing $age_dir/keys.txt" >&2
        return 1
    fi
    local dotenv
    dotenv=$(docker run --rm \
        --entrypoint sops \
        -v "$sops_dir:/secrets:ro" \
        -v "$age_dir:/age:ro" \
        -e SOPS_AGE_KEY_FILE=/age/keys.txt \
        ghcr.io/getsops/sops:v3.13.1 \
        -d --output-type dotenv "/secrets/$file") || {
        echo "sops_export_env: failed to decrypt $file" >&2
        return 1
    }
    # Prefix each line with `export ` and source it
    eval "$(printf '%s\n' "$dotenv" | sed 's/^/export /')"
}

# Decrypt a SOPS-encrypted YAML-structured file (preserves nested structure)
# and write to a specific destination path with mode 0600.
#
# Used for things like Traefik dynamic config files where the file's YAML
# structure must be preserved (a dotenv flattening would corrupt it).
#
# Usage:
#   decrypt_yaml_to traefik-middlewares.sops.yaml \
#       "$BASE/common/secrets/.runtime/traefik-middlewares.yml"
decrypt_yaml_to() {
    local source_name="$1"     # filename in common/secrets/
    local dest_path="$2"       # absolute path for decrypted output
    local sops_dir="$BASE/common/secrets"
    [ -f "$sops_dir/$source_name" ] || return 0
    local age_dir="$HOME/.config/sops/age"
    if [ ! -f "$age_dir/keys.txt" ]; then
        echo "decrypt_yaml_to: missing $age_dir/keys.txt" >&2
        return 1
    fi

    mkdir -p "$(dirname "$dest_path")"

    # Skip if the destination is newer than the source — same caching
    # rationale as decrypt_secrets.
    if [ -f "$dest_path" ] && [ "$dest_path" -nt "$sops_dir/$source_name" ]; then
        return 0
    fi

    local prev_umask
    prev_umask=$(umask)
    umask 077

    if ! docker run --rm \
        --entrypoint sops \
        -v "$sops_dir:/secrets:ro" \
        -v "$age_dir:/age:ro" \
        -e SOPS_AGE_KEY_FILE=/age/keys.txt \
        ghcr.io/getsops/sops:v3.13.1 \
        -d --output-type yaml "/secrets/$source_name" > "$dest_path.tmp"; then
        echo "decrypt_yaml_to: failed to decrypt $source_name" >&2
        rm -f "$dest_path.tmp"
        umask "$prev_umask"
        return 1
    fi
    mv "$dest_path.tmp" "$dest_path"
    chmod 600 "$dest_path"
    umask "$prev_umask"
}
