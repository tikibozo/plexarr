#!/bin/bash
#
# Pull image updates and restart containers for docker compose
#
echo Update mon
docker compose -f /path/to/repo/mon/docker-compose.yml pull -q
docker compose -f /path/to/repo/mon/docker-compose.yml up -d --always-recreate-deps
echo ""

docker image prune -f
echo ""
