#!/bin/sh
# Polls gluetun control servers for the PIA dynamic forwarded port and writes
# it into the corresponding slskd.yml listen_port so incoming Soulseek peers
# can reach slskd. slskd hot-reloads the YAML on change.
set -u

PAIRS="gluetun|http://gluetun:8011|/configs/slskd/slskd.yml
gluetun2|http://gluetun2:8011|/configs/slskd2/slskd.yml"

POLL_INTERVAL="${POLL_INTERVAL:-60}"

log() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*"
}

get_port() {
  # Try the current endpoint first, fall back to the legacy one.
  for path in /v1/portforward /v1/openvpn/portforwarded; do
    port=$(wget -qO- -T 5 "$1$path" 2>/dev/null |
      sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
    if [ -n "${port:-}" ]; then
      printf '%s' "$port"
      return 0
    fi
  done
}

get_current() {
  grep -E '^[[:space:]]*listen_port:' "$1" 2>/dev/null | head -1 | awk '{print $2}'
}

update_config() {
  config="$1"
  port="$2"
  tmp="${config}.tmp.$$"
  if grep -qE '^[[:space:]]*listen_port:' "$config"; then
    sed "s/^\([[:space:]]*\)listen_port:.*/\1listen_port: $port/" "$config" > "$tmp"
  elif grep -q '^soulseek:' "$config"; then
    awk -v p="$port" '
      { print }
      /^soulseek:$/ && !done { print "  listen_port: " p; done=1 }
    ' "$config" > "$tmp"
  else
    printf '\nsoulseek:\n  listen_port: %s\n' "$port" >> "$config"
    return 0
  fi
  mv "$tmp" "$config"
}

sync_one() {
  name="$1"
  url="$2"
  config="$3"
  port=$(get_port "$url")
  if [ -z "${port:-}" ] || [ "$port" -le 0 ] 2>/dev/null; then
    return 0
  fi
  current=$(get_current "$config")
  if [ "${current:-0}" != "$port" ]; then
    log "[$name] listen_port ${current:-unset} -> $port"
    update_config "$config" "$port"
  fi
}

log "slskd-port-sync starting (interval ${POLL_INTERVAL}s)"
while true; do
  printf '%s\n' "$PAIRS" | while IFS='|' read -r name url config; do
    [ -z "$name" ] && continue
    sync_one "$name" "$url" "$config"
  done
  sleep "$POLL_INTERVAL"
done
