#!/bin/ash
# Daily rclone backup script
#

# Connection string/flags 
ARGS="--copy-links _async=true --url yourserver.domain:5572 --user rclone --pass rclone"

# install jq if not present
echo Install jq if necessary
apk add jq
echo

# Sync 
echo RClone sync docker volumes
echo rclone rc sync/sync srcFs=/opt dstFs=B2-crypt-docker:/docker/ $ARGS
JOB=$(rclone rc sync/sync srcFs=/opt dstFs=B2-crypt-docker:/docker/ $ARGS | jq .jobid)
echo Job ID: $JOB

echo
echo RClone sync music 
echo rclone rc sync/sync srcFs=/data/media/music dstFs=B2-crypt-media:/music/ $ARGS
JOB=$(rclone rc sync/sync srcFs=/data/media/music dstFs=B2-crypt-media:/music/ $ARGS | jq .jobid)
echo Job ID: $JOB

echo
echo RClone sync movies 
echo rclone rc sync/sync srcFs=/data/media/movies dstFs=B2-crypt-media:/movies/ $ARGS
JOB=$(rclone rc sync/sync srcFs=/data/media/movies-backup dstFs=B2-crypt-media:/movies/ $ARGS | jq .jobid)
echo Job ID: $JOB

echo
echo RClone sync tv 
echo rclone rc sync/sync srcFs=/data/media/tv dstFs=B2-crypt-media:/tv/ $ARGS
JOB=$(rclone rc sync/sync srcFs=/data/media/tv-backup dstFs=B2-crypt-media:/tv/ $ARGS | jq .jobid)
echo Job ID: $JOB
