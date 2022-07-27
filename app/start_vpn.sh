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

[[ -f /app/utils.sh ]] && source /app/utils.sh || true

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
  if [[ -z ${DOCKER_NET:-''} ]]; then
    DOCKER_NET="$(getEthCidr)"
  fi
  log "INFO: NORDVPN: whitelisting docker's net: ${DOCKER_NET}"
  nordvpn whitelist add subnet ${DOCKER_NET}
  if [[ -n ${LOCAL_NETWORK:-''} ]]; then
    for net in ${LOCAL_NETWORK//[;,]/ }; do
      nordvpn whitelist add subnet ${net}
      #do not readd route if already present
      if [[ -z $(ip route show match ${net} | grep ${net}) ]]; then
        log "INFO: NORDVPN: adding route to local network ${net} via ${GW} dev ${INT}"
        /sbin/ip route add "${net}" via "${GW}" dev "${INT}"
      fi
    done
  else
    log "INFO: NORDVPN: no route to host's local network"
  fi
  [[ -n ${PORTS:-''} ]] && for port in ${PORTS//[;,]/ }; do nordvpn whitelist add port ${port}; done
  [[ ${DEBUG} ]] && nordvpn -version && nordvpn settings
}

#Main
#Overwrite docker dns as it may fail with specific configuration (dns on server)
echo "nameserver 1.1.1.1" >/etc/resolv.conf
# No more updated
# checkLatest
# [[ 0 -ne $? ]] && checkLatestApt
checkLatestApt
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
