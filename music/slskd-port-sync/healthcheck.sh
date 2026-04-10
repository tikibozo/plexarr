#!/bin/sh
# Healthcheck that verifies slskd is not just alive but actually logged in
# to the Soulseek network. Catches the "netns got yanked when gluetun
# restarted" state where slskd keeps running but can't resolve DNS or
# reach the Soulseek server.
port="${SLSKD_HTTP_PORT:-5030}"
key="${SLSKD_HEALTH_KEY:-}"

# Liveness: local HTTP server must respond.
wget -q -O- -T 3 "http://localhost:${port}/health" > /dev/null 2>&1 || exit 1

# Readiness: must be logged in to the Soulseek server.
[ -z "$key" ] && exit 0
state=$(wget -q -O- -T 3 --header="X-API-Key: $key" "http://localhost:${port}/api/v0/server" 2>/dev/null)
echo "$state" | grep -q '"isLoggedIn":true' || exit 2
exit 0
