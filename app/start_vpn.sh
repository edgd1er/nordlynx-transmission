#!/bin/bash

set -euo pipefail

#Vars
[[ ${NORDVPN_DEBUG:-false} == "true" ]] && set -x || true
DEBUG=${DEBUG:-false}
COUNTRY=${COUNTRY:-''}
CONNECT=${CONNECT:-''}
GROUP=${GROUP:-''}
NOIPV6=${NOIPV6:-'off'}
[[ -n ${COUNTRY} && -z ${CONNECT} ]] && CONNECT=${COUNTRY} && export CONNECT
CONNECT=${CONNECT// /_}
[[ "${GROUPID:-''}" =~ ^[0-9]+$ ]] && groupmod -g $GROUPID -o vpn
[[ -n ${GROUP} ]] && GROUP="--group ${GROUP}"
LOCALNET=$(hostname -i | grep -Eom1 "(^[0-9]{1,3}\.[0-9]{1,3})")
route_net_gateway=$(ip r | grep -oP "(?<=default via )([^ ]+)") || true
EP_IP=
EP_PORT=${EP_PORT:-51820}
IP_PORT=${IP_PORT:-54778}

[[ -f /app/utils.sh ]] && source /app/utils.sh || true
container_ip=$(getEthIp)

#Functions
setTimeZone() {
  [[ ${TZ} == $(cat /etc/timezone) ]] && return
  log "INFO: Setting timezone to ${TZ}"
  ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime
  dpkg-reconfigure -fnoninteractive tzdata
}

set_iptables() {
  action=${1:-'DROP'}
  log "INFO: setting iptables policy to ${action}"
  iptables -F
  iptables -X
  iptables -P INPUT ${action}
  iptables -P FORWARD ${action}
  iptables -P OUTPUT ${action}
}

setIPV6() {
  if [[ 0 -eq $(grep -c "net.ipv6.conf.all.disable_ipv6" /etc/sysctl.conf) ]]; then
    echo "net.ipv6.conf.all.disable_ipv6 = ${1}" >/etc/sysctl.conf
  else
    sed -i -E "s/net.ipv6.conf.all.disable_ipv6 = ./net.ipv6.conf.all.disable_ipv6 = ${1}/" /etc/sysctl.conf
  fi
  sysctl -p || true
}

#Main
#Overwrite docker dns as it may fail with specific configuration (dns on server)
echo "nameserver 1.1.1.1" >/etc/resolv.conf

[[ -z ${CONNECT} ]] && exit 1

set_iptables DROP
setTimeZone
set_iptables ACCEPT

if [ -f /run/secrets/NORDVPN_PRIVKEY ]; then
  log "INFO: NORDLYNX: private key found, going for wireguard."
  #Nordvpn has a fetch limit, storing json to prevent hitting the limit.
  export json_countries=$(curl -LSs ${nordvpn_api}/v1/servers/countries)
  export possible_country_codes="$(echo ${json_countries} | jq -r .[].code | tr '\n' ', ')"
  export possible_country_names="$(echo ${json_countries} | jq -r .[].name | tr '\n' ', ')"
  export possible_city_names="$(echo ${json_countries} | jq -r .[].cities[].name | tr '\n' ', ')"
  # groups used for CATEGORY
  export json_groups=$(curl -LSs ${nordvpn_api}/v1/servers/groups)
  export possible_groups="$(echo ${json_groups} | jq -r '[.[].title] | @csv' | tr -d '\"')"
  # technology
  export json_technologies=$(curl -LSs ${nordvpn_api}/v1/technologies)
  export possible_technologies=$(echo ${json_technologies} | jq -r '[.[].name] | @csv'| tr -d '\"')
  export possible_technologies_id=$(echo ${json_technologies} | jq -r '[.[].identifier] |@csv'| tr -d '\"')
  log "Checking NORDPVN API responses"
  for po in json_countries json_groups json_technologies; do
    if [[ $(echo ${!po} | grep -c "<html>") -gt 0 ]]; then
      msg=$(echo ${!po} | grep -oP "(?<=title>)[^<]+")
      echo "ERROR, unexpected html content from NORDVPN servers: ${msg}"
      sleep 30
      exit
    fi
  done
  if [[ ! -s /etc/resolv.conf ]]; then
    rm -f /etc/resolv.conf
    ln -s /run/resolvconf/resolv.conf /etc/resolv.conf
  fi
  generateWireguardConf
  connectWireguardVpn
else
  log "Error: NORDLYNX: no wireguard private key found, exiting."
fi

log "INFO: current WAN IP: $(getCurrentWanIp)"

#prevent leak through default route
if [[ "true" = "$DROP_DEFAULT_ROUTE" ]] && [[ -n ${route_net_gateway} ]]; then
  echo "DROPPING DEFAULT ROUTE"
  # Remove the original default route to avoid leaks.
  #/sbin/ip route del default via "${route_net_gateway}" || exit 1
fi

#connected
generateDantedConf
generateTinyproxyConf

log "INFO: DANTE: start proxy"
supervisorctl start dante

log "INFO: TINYPROXY: starting"
supervisorctl start tinyproxy

supervisorctl start transmission
