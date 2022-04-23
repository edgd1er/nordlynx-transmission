#!/bin/bash

set -euo pipefail

#Vars
RDIR=/run/nordvpn/
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
else
  log "Info: NORDLYNX: no wireguard private key found, connecting with nordvpn client."
  nordlynxVpn
  extractLynxConf
fi

log "INFO: current WAN IP: $(getCurrentWanIp) / unprotected ip: ${UNP_IP}"

#prevent leak through default route
if [[ "true" = "$DROP_DEFAULT_ROUTE" ]] && [[ -n ${route_net_gateway} ]]; then
  echo "DROPPING DEFAULT ROUTE"
  # Remove the original default route to avoid leaks.
  #/sbin/ip route del default via "${route_net_gateway}" || exit 1
fi

#connected
status=$(getVpnProtectionStatus)
if [[ ${status,,} == "unprotected" ]]; then
  echo "Error, status: ${status}"
  exit 1
fi

generateDantedConf
generateTinyproxyConf

log "INFO: DANTE: start proxy"
supervisorctl start dante

log "INFO: TINYPROXY: starting"
supervisorctl start tinyproxy

supervisorctl start transmission
