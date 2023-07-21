#!/usr/bin/bash
#
# Update Azure network security group with home WAN IP (dynamic)
#

homeip=$(dig +short home.yourdomain.com)'/32'

stdArgs='--nsg-name azmon-nsg --resource-group 0000id0000 -o json'
webip=$(az network nsg rule show --name AllowCidrBlockCustom443Inbound $stdArgs | jq -r '"\(.sourceAddressPrefix)"')
wgip=$(az network nsg rule show --name AllowCidrBlockCustom51820Inbound $stdArgs | jq -r '"\(.sourceAddressPrefix)"')
sship=$(az network nsg rule show --name default-allow-ssh $stdArgs | jq -r '"\(.sourceAddressPrefix)"')

if [ "$webip" != "$homeip" ] || [ "$sship" != "$homeip" ] || [ "$wgip" != "$homeip" ]; then
  echo "Detected home IP of $homeip"
  echo "Azure Security Rules are using:"
  echo "$webip (Web)"
  echo "$sship (SSH)"
  echo "$wgip (Wireguard)"
  echo 
  echo ""
  echo "Updating Network Security Group rules with new home IP."
  echo ""
  az network nsg rule update --name AllowCidrBlockCustom443Inbound --source-address-prefixes $homeip $stdArgs | jq -r '(.name)+": "+(.sourceAddressPrefix)+", "+(.provisioningState)'
  az network nsg rule update --name AllowCidrBlockCustom51820Inbound --source-address-prefixes $homeip $stdArgs | jq -r '(.name)+": "+(.sourceAddressPrefix)+", "+(.provisioningState)'
  az network nsg rule update --name default-allow-ssh --source-address-prefixes $homeip $stdArgs | jq -r '(.name)+": "+(.sourceAddressPrefix)+", "+(.provisioningState)'
fi
