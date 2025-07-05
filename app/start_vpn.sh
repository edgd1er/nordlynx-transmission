#!/bin/bash

set -euo pipefail

#Vars
[[ -f /app/utils.sh ]] && source /app/utils.sh || true
[[ ${NORDVPN_DEBUG:-false} == "true" ]] && set -x || true
TSEC=5
RDIR=/run/nordvpn/
ANALYTICS=${ANALYTICS:-off}
COUNTRY=${COUNTRY:-''}
CONNECT=${CONNECT:-''}
GROUP=${GROUP:-''}
NOIPV6=${NOIPV6:-'off'}
[[ -n ${COUNTRY} && -z ${CONNECT} ]] && CONNECT=${COUNTRY} && export CONNECT
CONNECT=${CONNECT// /_}
[[ "${GROUPID:-''}" =~ ^[0-9]+$ ]] && groupmod -g $GROUPID -o vpn
[[ -n ${GROUP} ]] && GROUP="--group ${GROUP}"


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

mkTun() {
  # Create a tun device see: https://www.kernel.org/doc/Documentation/networking/tuntap.txt
  if [ ! -c /dev/net/tun ]; then
    log "INFO: OVPN: Creating tun interface /dev/net/tun"
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200
    chmod 600 /dev/net/tun
  fi
}

#Main
#Overwrite docker dns as it may fail with specific configuration (dns on server)
chattr -i /etc/resolv.conf
echo "nameserver 1.1.1.1" >/etc/resolv.conf

setTimeZone

# checkLatest commented as no more updated
checkLatestApt
installedRequiredNordVpnClient

#Define if not defined
TECHNOLOGY=${TECHNOLOGY:-'nordlynx'}
OBFUSCATE=${OBFUSCATE:-'off'}

#if running stop it.
stop_transmission

#stop killswitch that disable communication when no vpn is up
if [ 1 -le $(pgrep -c nordvpnd) ]; then
  nordvpn s killswitch off
fi

[[ -z ${CONNECT} ]] && exit 1
[[ ! -d ${RDIR} ]] && mkdir -p ${RDIR}

mkTun
UNP_IP=$(getCurrentWanIp)
# May be useful for Synology when iptables-nft has problems.
if [[ ${IPTABLES_LEGACY^^} != "N" ]]; then
   log "INFO: use iptable-legacy: https://developers.redhat.com/blog/2020/08/18/iptables-the-two-variants-and-their-relationship-with-nftables#"
   update-alternatives --set iptables /usr/sbin/iptables-legacy
fi
#Drop existing rules
set_iptables DROP
#Accept all.
set_iptables ACCEPT

if [[ -f /run/secrets/NORDVPN_PRIVKEY ]] && [[ ${TECHNOLOGY,,} == "nordlynx" ]]; then
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
  setup_nordvpn
  startNordVpn
  enforce_proxies_nordvpn
  [[ ${TECHNOLOGY,,} == "nordlynx" ]] && extractLynxConf || true
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

if [[ ${status,,} != "connected" ]]; then
  echo "Warning, status is ${status} according to nordvpn."
fi

generateDantedConf
generateTinyproxyConf

log "INFO: DANTE: start proxy"
supervisorctl start dante

log "INFO: TINYPROXY: starting"
supervisorctl start tinyproxy

supervisorctl start transmission
