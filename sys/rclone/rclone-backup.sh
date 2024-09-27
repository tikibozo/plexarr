#!/bin/bash

# Log
hostlog="/tmp/rclone/$(date +"%Y-%m-%d")_backup.txt"
containerlog="/htmp/$(date +"%Y-%m-%d")_backup.txt"

# Connection string/flags
args="--copy-links --fast-list --b2-hard-delete -v --log-file $containerlog" 

run_backup()
{
    echo "Backing up $1 to $2" >> "$hostlog"
    echo "------" >> "$hostlog"
    docker exec -t rclone /bin/ash -c "rclone sync $1 $2 $args $3 $4" >> "$hostlog" 2>&1
    echo "==================================================" >> "$hostlog"
    echo "" >> "$hostlog"
}

# Grab PFSense config so it's backed up
echo "Back up PFSense config file" >> "$hostlog"
scp user@host:/conf.default/config.xml /mnt/app/db/pfsense/config.xml >> "$hostlog" 2>&1
ls -al /mnt/app/db/pfsense/config.xml >> "$hostlog"
echo "" >> "$hostlog"

# Run the backups
run_backup /data/media/whatever B2-crypt-media:/whatever/

# Send report 
to="user@host.com"
subject="$(hostname) Backup Report"
body="rclone backup report, see attached."
cat $hostlog | mailx -s "$subject" "$to"

# Clean up log
rm $hostlog
