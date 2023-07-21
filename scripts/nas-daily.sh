#!/bin/bash
#
# Pull image updates and restart containers for docker compose
#
echo Update nas
docker compose -f /path/to/repo/nas/docker-compose.yml pull -q
docker compose -f /path/to/repo/nas/docker-compose.yml up -d --always-recreate-deps 
echo ""

echo Update media 
docker compose -f /path/to/repo/media/docker-compose.yml pull -q
docker compose -f /path/to/repo/media/docker-compose.yml up -d --always-recreate-deps
echo ""

echo Update sys 
docker compose -f /path/to/repo/sys/docker-compose.yml pull -q
docker compose -f /path/to/repo/sys/docker-compose.yml up -d --always-recreate-deps
echo ""

echo Update monproxy 
docker compose -f /path/to/repo/monproxy/docker-compose.yml pull -q
docker compose -f /path/to/repo/monproxy/docker-compose.yml up -d --always-recreate-deps
echo ""

docker image prune -f
echo ""

echo Update subcleaner
cd /path/to/docker/config/bazarr/subcleaner
sudo -u docker git pull
docker compose -f /path/to/repo/media/docker-compose.yml up -d --force-recreate --no-deps bazarr 
echo ""

echo Restart rClone to clear statistics
docker restart rclone
echo ""

echo Back up PFSense config files
scp user@pfsense:/conf.default/config.xml /path/to/docker/config/pfsense/config.xml
ls -al /path/to/docker/config/pfsense/config.xml
echo ""
