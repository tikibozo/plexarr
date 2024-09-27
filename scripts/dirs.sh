#!/bin/bash
# Return compose dir path for local host
#
# Usage:
# COMPOSE_PATH=$( getComposePath ) 
# echo $COMPOSE_PATH

# Get the script directory, resolving symlinks
SOURCE=${BASH_SOURCE[0]}
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  SOURCE=$(readlink "$SOURCE")
  [[ $SOURCE != /* ]] && SOURCE=$DIR/$SOURCE # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
ROOT=${DIR%/*}/

# This version does not resolve symlinks
#SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
#ROOT=${SCRIPT_DIR%/*}/

function getComposePath()
{
    case $HOSTNAME in
        (server1)
            echo "$ROOT"media/"" 
            return 0
        ;;

        (server2) 
            echo "$ROOT"nas/"" 
            return 0
        ;;

    esac

    echo ""
}

function getComposeFile()
{
    P=$( getComposePath )
    if [[ $P ]]
    then
        echo "$P"docker-compose.yml""
    fi
}

#echo $( getComposePath )
#echo $( getComposeFile )
