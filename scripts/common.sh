#!/bin/bash
# Shared config loader for compose scripts

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CONF="$SCRIPT_DIR/projects.conf"

LINE=$(grep "^$HOSTNAME:" "$CONF")

if [ -z "$LINE" ]; then
    echo "No config for host: $HOSTNAME"
    exit 1
fi

BASE=$(echo "$LINE" | cut -d: -f2)
PROJECTS=$(echo "$LINE" | cut -d: -f3)
