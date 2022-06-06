#!/bin/bash

set -euo pipefail

#Vars
[[ -f /app/utils.sh ]] && source /app/utils.sh || true
[[ ${NORDVPN_DEBUG:-false} == "true" ]] && set -x || true
TSEC=5
RDIR=/run/nordvpn/
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


container_ip=$(getEthIp)

#Functions
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

#Main
#Overwrite docker dns as it may fail with specific configuration (dns on server)
echo "nameserver 1.1.1.1" >/etc/resolv.conf

[[ -z ${CONNECT} ]] && exit 1

UNP_IP=$(getCurrentWanIp)
set_iptables DROP
setTimeZone
set_iptables ACCEPT

if [ -f /run/secrets/NORDVPN_PRIVKEY ]; then
  log "INFO: NORDLYNX: private key found, going for wireguard."
  getJsonFromNordApi
  if [[ ! -s /etc/resolv.conf ]]; then
    rm -f /etc/resolv.conf
    ln -s /run/resolvconf/resolv.conf /etc/resolv.conf
  fi
  generateWireguardConf
  connectWireguardVpn
  enforce_iptables
elif [[ ${NORDVPNCLIENT_INSTALLED} -eq 1 ]]; then
  log "Info: NORDLYNX: no wireguard private key found, connecting with nordvpn client."
  startNordlynxVpn
  enforce_proxies_nordvpn
  extractLynxConf
else
  log "Error: NORDLYNX: no nordvpn client, no wireguard private key, exiting."
  exit
fi

#
echo "waiting ${TSEC} for routing to be up"
sleep ${TSEC}

#connected
status=$(getVpnProtectionStatus)
currentIp=$(getCurrentWanIp)
log "INFO: current WAN IP: $(getCurrentWanIp) / unprotected ip: ${UNP_IP}, status: ${status}"
if [[ ${UNP_IP} == ${currentIp} ]]; then
  echo "Error, ${currentIp} is the same as host external ip (${UNP_IP}), exiting."
  exit 1
fi

if [[ ${status,,} == "unprotected" ]]; then
  echo "Warning, status is ${status} according to nordvpn."
  curl -sm 10 "https://api.nordvpn.com/vpn/check/full" | jq .
fi

generateDantedConf
generateTinyproxyConf

log "INFO: DANTE: start proxy"
supervisorctl start dante

log "INFO: TINYPROXY: starting"
supervisorctl start tinyproxy

supervisorctl start transmission
