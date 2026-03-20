#!/bin/bash
#
# Update Azure network security group with home WAN IP (dynamic)
# Enhanced with Zabbix monitoring integration
#

LOGFILE="/var/log/azure-nsg-update.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
UNIX_TIMESTAMP=$(date +%s)

# Function to send data to Zabbix
send_to_zabbix() {
    local key="$1"
    local value="$2"
    docker exec zabbix-agent zabbix_sender -z monitoringserver -s monitoringserver -k "azure_nsg_update.$key" -o "$value" >/dev/null 2>&1
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
echo "[$TIMESTAMP] NSG IP Update Script Started" >> $LOGFILE
send_to_zabbix "message" "Script started"

homeip=$(dig +short your.domain.com)"/32"

if [ -z "$homeip" ] || [ "$homeip" = "/32" ]; then
  cleanup_and_exit 1 "Unable to determine home IP"
fi

stdArgs="--nsg-name nsg-name-here --resource-group rg-guiddddd -o json"

# Check Azure CLI authentication and get current NSG rules
webip=$(az network nsg rule show --name HTTPS $stdArgs 2>/dev/null | jq -r ".sourceAddressPrefix" 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$webip" ]; then
    cleanup_and_exit 1 "Azure CLI authentication failed or NSG query failed"
fi

wgip=$(az network nsg rule show --name WireGuard $stdArgs 2>/dev/null | jq -r ".sourceAddressPrefix" 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$wgip" ]; then
    cleanup_and_exit 1 "Failed to query WireGuard NSG rule"
fi

sship=$(az network nsg rule show --name SSH $stdArgs 2>/dev/null | jq -r ".sourceAddressPrefix" 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$sship" ]; then
    cleanup_and_exit 1 "Failed to query SSH NSG rule"
fi

# Log current status
echo "[$TIMESTAMP] Current Home IP: $homeip" >> $LOGFILE
echo "[$TIMESTAMP] Current NSG IPs - HTTPS: $webip, SSH: $sship, WireGuard: $wgip" >> $LOGFILE

if [ "$webip" != "$homeip" ] || [ "$sship" != "$homeip" ] || [ "$wgip" != "$homeip" ]; then
  echo "[$TIMESTAMP] IP Change Detected - Updating NSG Rules" >> $LOGFILE
  echo "Detected home IP of $homeip"
  echo "Azure Security Rules are using:"
  echo "$webip for HTTPS"
  echo "$sship for SSH"
  echo "$wgip for WireGuard"
  echo
  echo "Updating Network Security Group rules with new home IP."
  echo

  # Update rules and check for failures
  https_result=$(az network nsg rule update --name HTTPS --source-address-prefixes $homeip $stdArgs 2>/dev/null | jq -r "(.name)+\": \"+(.sourceAddressPrefix)+\", \"+(.provisioningState)" 2>/dev/null)
  if [ $? -ne 0 ]; then
      cleanup_and_exit 1 "Failed to update HTTPS rule"
  fi

  wg_result=$(az network nsg rule update --name WireGuard --source-address-prefixes $homeip $stdArgs 2>/dev/null | jq -r "(.name)+\": \"+(.sourceAddressPrefix)+\", \"+(.provisioningState)" 2>/dev/null)
  if [ $? -ne 0 ]; then
      cleanup_and_exit 1 "Failed to update WireGuard rule"
  fi

  ssh_result=$(az network nsg rule update --name SSH --source-address-prefixes $homeip $stdArgs 2>/dev/null | jq -r "(.name)+\": \"+(.sourceAddressPrefix)+\", \"+(.provisioningState)" 2>/dev/null)
  if [ $? -ne 0 ]; then
      cleanup_and_exit 1 "Failed to update SSH rule"
  fi

  echo $https_result
  echo $wg_result
  echo $ssh_result

  echo "[$TIMESTAMP] Update Results - HTTPS: $https_result" >> $LOGFILE
  echo "[$TIMESTAMP] Update Results - WireGuard: $wg_result" >> $LOGFILE
  echo "[$TIMESTAMP] Update Results - SSH: $ssh_result" >> $LOGFILE
  echo "[$TIMESTAMP] NSG Rules Updated Successfully" >> $LOGFILE

  cleanup_and_exit 0 "Successfully updated NSG rules to $homeip"
else
  echo "[$TIMESTAMP] No IP change detected - NSG rules current" >> $LOGFILE
  cleanup_and_exit 0 "No NSG update needed - all rules already match home IP"
fi
