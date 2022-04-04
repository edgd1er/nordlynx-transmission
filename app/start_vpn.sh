#!/bin/bash

set -euo pipefail

#Vars
RDIR=/run/nordvpn
DEBUG=${DEBUG:-false}
COUNTRY=${COUNTRY:-''}
CONNECT=${CONNECT:-''}
GROUP=${GROUP:-''}
NOIPV6=${NOIPV6:-'off'}
[[ -n ${COUNTRY} && -z ${CONNECT} ]] && CONNECT=${COUNTRY} && export CONNECT
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

checkLatest() {
  CANDIDATE=$(curl --retry 3 -LSs "https://nordvpn.com/fr/blog/nordvpn-linux-release-notes/" | grep -oP "NordVPN \K[0-9]\.[0-9.-]{1,4}" | head -1)
  VERSION=$(dpkg-query --showformat='${Version}' --show nordvpn) || true
  [[ -z ${VERSION} ]] && VERSION=$(apt-cache show nordvpn | grep -oP "(?<=Version: ).+") || true
  if [[ ${VERSION} =~ ${CANDIDATE} ]]; then
    log "INFO: No update needed for nordvpn (${VERSION})"
  else
    log "**********************************************************************"
    log "WARNING: please update nordvpn from version ${VERSION} to ${CANDIDATE}"
    log "WARNING: please update nordvpn from version ${VERSION} to ${CANDIDATE}"
    log "**********************************************************************"
  fi
}

checkLatestApt() {
  apt-get update
  VERSION=$(apt-cache policy nordvpn | grep -oP "Installed: \K.+")
  CANDIDATE=$(apt-cache policy nordvpn | grep -oP "Candidate: \K.+")
  CANDIDATE=${CANDIDATE:-${VERSION}}
  if [[ ${CANDIDATE} != ${VERSION} ]]; then
    log "**********************************************************************"
    log "WARNING: please update nordvpn from version ${VERSION} to ${CANDIDATE}"
    log "WARNING: please update nordvpn from version ${VERSION} to ${CANDIDATE}"
    log "**********************************************************************"
  else
    log "INFO: No update needed for nordvpn (${VERSION})"
  fi
}

#embedded in nordvpn client but not efficient in container. done in docker-compose
#setIPV6 ${NOIPV6}

setup_nordvpn() {
  nordvpn set technology ${TECHNOLOGY:-'NordLynx'}
  nordvpn set cybersec ${CYBER_SEC:-'off'}
  nordvpn set killswitch ${KILLERSWITCH:-'on'}
  nordvpn set ipv6 ${NOIPV6} 2>/dev/null
  [[ -n ${DNS:-''} ]] && nordvpn set dns ${DNS//[;,]/ }
  [[ -z ${DOCKER_NET:-''} ]] && DOCKER_NET="$(hostname -i | grep -Eom1 "^[0-9]{1,3}\.[0-9]{1,3}").0.0/12"
  nordvpn whitelist add subnet ${DOCKER_NET}
  [[ -n ${NETWORK:-''} ]] && for net in ${NETWORK//[;,]/ }; do nordvpn whitelist add subnet ${net}; done
  [[ -n ${PORTS:-''} ]] && for port in ${PORTS//[;,]/ }; do nordvpn whitelist add port ${port}; done
  [[ ${DEBUG} ]] && nordvpn -version && nordvpn settings
  nordvpn whitelist add subnet ${LOCALNET}.0.0/16
}

#Main
#Overwrite docker dns as it may fail with specific configuration (dns on server)
echo "nameserver 1.1.1.1" >/etc/resolv.conf
checkLatest
[[ 0 -ne $? ]] && checkLatestApt
[[ -z ${CONNECT} ]] && exit 1
[[ ! -d ${RDIR} ]] && mkdir -p ${RDIR}

set_iptables DROP
setTimeZone
set_iptables ACCEPT

if [ -e /run/secrets/NORDLYNX_PRIVKEY ]; then
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
  export possible_technologies=$(echo ${json_technologies} | jq -r '.[].name |@csv'| tr -d '\"')
  export possible_technologies_id=$(echo ${json_technologies} | jq -r '.[].identifier |@csv'| tr -d '\"')
  log "Checking NORDPVN API responses"
  for po in json_countries json_groups json_technologies; do
    if [[ $(echo ${!po} | grep -c "<html>") -gt 0 ]]; then
      msg=$(echo ${!po} | grep -oP "(?<=title>)[^<]+")
      echo "ERROR, unexpected html content from NORDVPN servers: ${msg}"
      sleep 30
      exit
    fi
  done
  generateWireguardConf
  connectWireguardVpn
else
  nordlynxVpn
  extractLynxConf
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
