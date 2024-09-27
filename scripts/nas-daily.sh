#!/bin/bash
#
# Pull image updates and restart containers for docker compose
#
echo Update nas
docker compose -f /mnt/app/home/user/compose/nas/docker-compose.yml pull -q
docker compose -f /mnt/app/home/user/compose/nas/docker-compose.yml up -d --always-recreate-deps 
echo ""

echo Update media 
docker compose -f /mnt/app/home/user/compose/media/docker-compose.yml pull -q
docker compose -f /mnt/app/home/user/compose/media/docker-compose.yml up -d --always-recreate-deps
echo ""

echo Update sys 
docker compose -f /mnt/app/home/user/compose/sys/docker-compose.yml pull -q
docker compose -f /mnt/app/home/user/compose/sys/docker-compose.yml up -d --always-recreate-deps
echo ""

echo Update monproxy 
docker compose -f /mnt/app/home/user/compose/monproxy/docker-compose.yml pull -q
docker compose -f /mnt/app/home/user/compose/monproxy/docker-compose.yml up -d --always-recreate-deps
echo ""

docker image prune -f
echo ""

echo Update subcleaner
cd /mnt/app/db//bazarr/subcleaner
sudo -u docker git pull
docker compose -f /mnt/app/home/user/compose/media/docker-compose.yml up -d --force-recreate --no-deps bazarr 
echo ""
