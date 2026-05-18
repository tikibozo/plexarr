#!/bin/bash
#
# Update Hetzner Cloud Firewall with home WAN IP (dynamic)
# Enhanced with Zabbix monitoring integration
# Replaces update-azure-nsg-ip.sh for the cloud-server VM migration
#

LOGFILE="/var/log/hetzner-fw-update.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
UNIX_TIMESTAMP=$(date +%s)

FIREWALL_NAME="cloud-server-fw"

# This script runs on cloud-server, which is not yet a SOPS recipient (deferred
# per the cloud-server-pass section of the hardening plan). HCLOUD_TOKEN is also
# encrypted in common/secrets/scripts.sops.yaml — once cloud-server is added as
# a SOPS recipient, swap this to:
#     source "$(dirname "$(readlink -f "$0")")/common.sh"
#     sops_export_env scripts.sops.yaml
#     export HCLOUD_TOKEN
export HCLOUD_TOKEN="WGxM30IPkTSDoJsU0OqwWYdFe4X3A7vX5YFTOlpKTeOnxclT0bHkMn6rSfCWgJ5N"

# Function to send data to Zabbix
send_to_zabbix() {
    local key="$1"
    local value="$2"
    docker exec zabbix-agent zabbix_sender -z 127.0.0.1 -s cloud-server -k "hetzner_fw_update.$key" -o "$value" >/dev/null 2>&1
}

# Function to handle script exit
cleanup_and_exit() {
    local exit_code="$1"
    local message="$2"

    if [ "$exit_code" -eq 0 ]; then
        echo "[$TIMESTAMP] Script completed successfully" >> $LOGFILE
        send_to_zabbix "status" "0"
        send_to_zabbix "message" "Success: $message"
    else
        echo "[$TIMESTAMP] Script completed with errors: $message" >> $LOGFILE
        send_to_zabbix "status" "1"
        send_to_zabbix "message" "Error: $message"
    fi

    send_to_zabbix "last_run" "$UNIX_TIMESTAMP"
    exit $exit_code
}

# Log script start
echo "[$TIMESTAMP] Hetzner Firewall IP Update Script Started" >> $LOGFILE
send_to_zabbix "message" "Script started"

homeip=$(dig +short home.yourdomain.com)

if [ -z "$homeip" ]; then
    cleanup_and_exit 1 "Unable to determine home IP"
fi

homecidr="${homeip}/32"

# Get current firewall rules and extract the source IP from the first rule
current_ip=$(hcloud firewall describe "$FIREWALL_NAME" -o json 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d['rules'][0]['source_ips'][0] if d['rules'] else '')" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$current_ip" ]; then
    cleanup_and_exit 1 "Failed to query Hetzner firewall rules"
fi

echo "[$TIMESTAMP] Current Home IP: $homecidr" >> $LOGFILE
echo "[$TIMESTAMP] Current Firewall IP: $current_ip" >> $LOGFILE

if [ "$current_ip" != "$homecidr" ]; then
    echo "[$TIMESTAMP] IP Change Detected - Updating Firewall Rules" >> $LOGFILE
    echo "Detected home IP of $homecidr (was $current_ip)"
    echo "Updating Hetzner Cloud Firewall rules..."

    # hcloud requires replacing all rules at once via --rules-file
    RULES_FILE=$(mktemp)
    cat > "$RULES_FILE" << RULES
[
  {"direction":"in","protocol":"tcp","port":"22","source_ips":["${homecidr}"],"description":"SSH from home"},
  {"direction":"in","protocol":"tcp","port":"443","source_ips":["${homecidr}"],"description":"HTTPS from home"},
  {"direction":"in","protocol":"udp","port":"51820","source_ips":["${homecidr}"],"description":"WireGuard from home"},
  {"direction":"in","protocol":"tcp","port":"10051","source_ips":["${homecidr}"],"description":"Zabbix agent from home"}
]
RULES

    result=$(hcloud firewall replace-rules "$FIREWALL_NAME" --rules-file "$RULES_FILE" 2>&1)
    rc=$?
    rm -f "$RULES_FILE"

    if [ $rc -ne 0 ]; then
        cleanup_and_exit 1 "Failed to update firewall rules: $result"
    fi

    echo "[$TIMESTAMP] Firewall Rules Updated Successfully" >> $LOGFILE

    # Re-resolve WireGuard endpoint so tunnel reconnects with new WAN IP
    WG_PEER="89ByM4t9l3kC9bU7WZtkiqy9mhCWguzL9Qplq8PfWV8="
    WG_ENDPOINT="home.yourdomain.com:51820"
    if sudo wg set wg0 peer "$WG_PEER" endpoint "$WG_ENDPOINT" 2>&1; then
        echo "[$TIMESTAMP] WireGuard endpoint re-resolved to $homeip:51820" >> $LOGFILE
    else
        echo "[$TIMESTAMP] WARNING: Failed to update WireGuard endpoint" >> $LOGFILE
    fi

    cleanup_and_exit 0 "Updated firewall rules to $homecidr and re-resolved WireGuard endpoint"
else
    echo "[$TIMESTAMP] No IP change detected - firewall rules current" >> $LOGFILE
    cleanup_and_exit 0 "No update needed - rules already match home IP"
fi
