#!/bin/bash

set -euo pipefail

DEBUG=${DEBUG:-"false"}
DANTE_LOGLEVEL=${DANTE_LOGLEVEL:-"error"}
DANTE_ERRORLOG=${DANTE_ERRORLOG:-"/dev/null"}
DANTE_DEBUG=${DANTE_DEBUG:-0}
export TRANSMISSION_DEBUG=${TRANSMISSION_DEBUG:-"false"}
export NORDVPN_DEBUG=${NORDVPN_DEBUG:-"false"}
if [[ ${DEBUG} != "false" ]]; then
  set -x
  export DANTE_DEBUG=1
  export TRANSMISSION_DEBUG=true
  export NORDVPN_DEBUG=true
  DANTE_DEBUG=9
  DANTE_LOGLEVEL=${DANTE_LOGLEVEL-"connect disconnect error data"}
fi
DANTE_LOGLEVEL=${DANTE_LOGLEVEL//\"/}
DANTE_ERRORLOG=${DANTE_ERRORLOG//\"/}

export nordvpn_api="https://api.nordvpn.com"

fatal_error() {
  #printf "${TIME_FORMAT} \e[41mERROR:\033[0m %b\n" "$*" >&2
  printf "\e[41mERROR:\033[0m %b\n" "$*" >&2
  exit 1
}

log() {
  echo "$(date +"%Y-%m-%d %T"): $*"
}

getCurrentWanIp() {
  curl -s 'https://api.ipify.org?format=json' | jq .ip
}

getVpnEth() {
  ip -j a | jq -r '.[].ifname | match("wg0|nordlynx|tun")| .string'
}

getEthIp() {
  ip -j a | jq -r '.[] |select(.ifname=="eth0")| .addr_info[].local'
}

generateDantedConf() {
  log "INFO: DANTE: set configuration socks proxy"
  SOURCE_DANTE_CONF=/etc/danted.conf.tmpl
  DANTE_CONF=/etc/dante.conf
  INTERFACE=$(getVpnEth)
  sed "s/INTERFACE/${INTERFACE}/" ${SOURCE_DANTE_CONF} >${DANTE_CONF}
  sed -i "s/DANTE_DEBUG/${DANTE_DEBUG}/" ${DANTE_CONF}
  [[ -n ${DANTE_LOGLEVEL} ]] && sed -i "s/log: DANTE_LOGLEVEL/log: ${DANTE_LOGLEVEL}/" ${DANTE_CONF}
  [[ -n ${DANTE_ERRORLOG} ]] && sed -i "s#errorlog: /dev/null#errorlog: ${DANTE_ERRORLOG}#" ${DANTE_CONF}

  log "INFO: DANTE: check configuration socks proxy"
  danted -Vf ${DANTE_CONF}
}

generateTinyproxyConf() {
  SOURCE_CONF=/etc/tinyproxy.conf.tmpl
  CONF=/etc/tinyproxy/tinyproxy.conf
  mkdir -p $(dirname ${CONF})
  TINYPORT=${TINYPORT:-8888}
  #Critical (least verbose), Error, Warning, Notice, Connect (to log connections without Info's noise), Info
  TINY_LOGLEVEL=${TINY_LOGLEVEL:-Error}

  EXT_IP=$(getNordlynxIp)
  INT_IP=$(getEthIp)

  #Main
  log "INFO: TINYPROXY: set configuration INT_IP: ${INT_IP}/ EXT_IP: ${EXT_IP} / log level: ${TINY_LOGLEVEL} / local network: ${LOCAL_NETWORK}"
  sed "s/TINYPORT/${TINYPORT}/" ${SOURCE_CONF} >${CONF}
  sed -i "s/TINY_LOGLEVEL/${TINY_LOGLEVEL}/" ${CONF}
  sed -i "s/#Listen .*/Listen ${INT_IP}/" ${CONF}

  #Allow only local network or all private address ranges
  if [[ -n ${LOCAL_NETWORK} ]]; then
    sed -i "s!#Allow LOCAL_NETWORK!Allow ${LOCAL_NETWORK}!" ${CONF}
  else
    sed -i 's!#Allow 10!Allow 10!' ${CONF}
    sed -i 's!#Allow 172!Allow 172!' ${CONF}
    sed -i 's!#Allow 192!Allow 192!' ${CONF}
  fi

  [[ ${DEBUG:-false} ]] && grep -vE "(^#|^$)" ${CONF} || true
}
####################
# NORDVPN specific #
####################

getNordlynxIp() {
  ip -j a | jq -r '.[] |select((.ifname|test("wg0";"i")) or (.ifname|test("nordlynx";"i")) or (.ifname|test("tun";"i")) ) | .addr_info[].local'
}

extractLynxConf() {
  wg showconf nordlynx >/etc/wireguard/wg0.conf
  chmod 600 /etc/wireguard/wg0.conf
  log "Wireguard configuration written to /etc/wireguard/wg0.conf"
}

nordlynxVpn() {

  #Use secrets if present
  #hide credentials even in debug
  set +x
  if [ -e /run/secrets/NORDVPN_CREDS ]; then
    mapfile -t -n 2 vars </run/secrets/NORDVPN_CREDS
    if [[ ${#vars[*]} -ne 2 ]] || [[ ${vars[0]} == ${vars[1]} ]]; then
      fatal_error "OVPN: openVPN login and password are identical. Exiting"
    fi
    NORDVPN_LOGIN=${vars[0]}
    NORDVPN_PASS=${vars[1]}
    [[ "${NORDVPN_LOGIN}" == "${NORDVPN_PASS}" ]] && fatal_error "ERROR, credentials shoud have two lines (login/password), one found."
  fi

  if [ -z ${NORDVPN_LOGIN} ] || [ -z ${NORDVPN_PASS} ]; then
    log "ERROR: NORDVPN: **********************"
    log "ERROR: NORDVPN: empty user or password"
    log "ERROR: NORDVPN: **********************"
    exit 1
  fi

  #start nordvpn daemon
  while [ ! -S ${RDIR}/nordvpnd.sock ]; do
    log "WARNING: NORDVPN: restart nordvpn daemon as no socket was found"
    supervisorctl restart nordvpnd
    sleep 10
  done

  # login: already logged in return 1
  res=$(nordvpn login --username ${NORDVPN_LOGIN} --password "${NORDVPN_PASS}" || true)
  [[ ${DEBUG} != "false" ]] && set -x || true
  if [[ "${res}" != *"Welcome to NordVPN"* ]] && [[ "${res}" != *"You are already logged in."* ]]; then
    log "ERROR: NORDVPN: cannot login: ${res}"
    exit 1
  fi
  log "INFO: NORDVPN: logged in: ${res}"

  #define connection parameters
  setup_nordvpn
  log "INFO: NORDVPN: connecting to ${GROUP} ${CONNECT} "

  #connect to vpn
  res=$(nordvpn connect ${GROUP} ${CONNECT}) || true
  log "INFO: NORDVPN: connect: ${res}"
  if [[ "${res}" != *"You are connected to"* ]]; then
    log "ERROR: NORDVPN: cannot connect to ${GROUP} ${CONNECT}"
    res=$(nordvpn connect ${CONNECT}) || true
    log "INFO: NORDVPN: connecting to ${CONNECT}"
    [[ "${res}" != *"You are connected to"* ]] && log "ERROR: NORDVPN: cannot connect to ${CONNECT}" && exit 1
  fi
  nordvpn status

  #check connected status
  N=10
  while [[ $(nordvpn status | grep -ic "connected") -eq 0 ]]; do
    sleep 10
    N--
    [[ ${N} -eq 0 ]] && log "ERROR: NORDVPN: cannot connect" && exit 1
  done
}

country_filter() {
  local country=(${*//[;,]/ })
  if [[ ${#country[@]} -ge 1 ]]; then
    country=${country[@]//_/ }
    local country_id=$(echo ${json_countries} | jq --raw-output ".[] | select( (.name|test(\"^${country}$\";\"i\")) or (.code|test(\"^${country}$\";\"i\")) ) | .id" | head -n 1)
  fi
  if [[ -n ${country_id} ]]; then
    log "Searching for country : ${country} (${country_id})"
    echo "filters\[country_id\]=${country_id}&"
  else
    log "Warning, empty or invalid NORDVPN_COUNTRY (value=${1}). Ignoring this parameter. Possible values are:${possible_country_codes[*]} or ${possible_country_names[*]}."
  fi
}

# curl -LsS 'https://api.nordvpn.com/v1/servers/countries' | jq ' [.[]| {"country": .name , "city": .cities[].name}]'
# curl -LsS 'https://api.nordvpn.com/v1/servers/countries' | jq ' .[]| select (.name|test("United states";"i")) | .cities[].name'
# curl -LSs 'https://api.nordvpn.com/v1/servers/recommendations?filters\[city_dns_name\]=new-york&filters\[country_id\]=228&filters\[servers_technologies\]\[identifier\]=wireguard_udp&limit=1' | jq

city_filter() {
  local city=${*:-''}
  city=${city,,}
  if [ -n "${city}" ]; then
    city=${city// /-}
    local city_id=$(echo ${json_countries} | jq --raw-output ".[].cities[]| select(.name|test(\"seattle\";\"i\")) |.id")
    if [[ -n ${city_id} ]]; then
      log "Searching for city : ${city} (${city_id})"
      echo "filters\[city_id\]=${city_id}&"
    else
      log "Warning, empty or invalid NORDVPN_CITY (value=${city}). Ignoring this parameter. Possible values are:${possible_city_names[*]}"
    fi
  fi
}

group_filter() {
  local identifier=''
  local category=${*}
  category=${category//[;,]/ }
  category=${category//--group /}
  if [[ -n ${category} ]]; then
    identifier=$(echo $json_groups | jq --raw-output ".[] |
                          select( ( .identifier|test(\"${category}\";\"i\")) or
                                  ( .title| test(\"${category}\";\"i\")) ) |
                          .identifier" | head -n 1)
  fi
  if [[ -n ${identifier} ]]; then
    log "Searching for group: ${identifier}"
    echo "filters\[servers_groups\]\[identifier\]=${identifier}&"
  else
    log "Warning, empty or invalid GROUP (value=${1//--group /}). ignoring this parameter. Possible values are: ${possible_categories[*]}."
  fi
}

technologies_filter() {
  local technology=${*}
  technology=${technology//[;,]/ }
  if [[ -n ${technology} ]]; then
    identifier=$(echo ${json_technologies} | jq --raw-output ".[] |
                          select( ( .name|test(\"${technology}\";\"i\")) or
                                  ( .identifier| test(\"${technology}\";\"i\")) ) |
                          .id" | head -n 1)
  fi
  if [[ -n ${identifier} ]]; then
    log "Searching for group: ${identifier}"
    echo "filters\[servers_technologies\]\[id\]=${identifier}&"
  else
    log "Warning, empty or invalid GROUP (value=${*}). ignoring this parameter. Possible values are: ${possible_technologies[*]}."
  fi
}

######################
# Wireguard specific #
######################

installWireguardPackage() {
  apt-get update && apt-get install -y --no-install-recommended wireguard wireguard-tools
}

generateWireguardConf() {
  local filters
  if [ -z ${EP_IP} ]; then
    log "Selecting the best server..."
    filters+="$(country_filter ${COUNTRY})"
    filters+="$(city_filter ${CITY})"
    filters+="$(group_filter ${GROUP})"
    filters+="$(technologies_filter  wireguard_udp)"
    # curl 'https://nordvpn.com/wp-admin/admin-ajax.php?action=servers_recommendations&filters={%22country_id%22:228,%22servers_groups%22:[15],%22servers_technologies%22:[35]}' --globoff -H 'User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:98.0) Gecko/20100101 Firefox/98.0' -H 'Accept: */*' -H 'Accept-Language: fr,fr-FR;q=0.8,en-US;q=0.5,en;q=0.3' -H 'Accept-Encoding: gzip, deflate, br' -H 'X-Requested-With: XMLHttpRequest' -H 'DNT: 1' -H 'Connection: keep-alive' -H 'Referer: https://nordvpn.com/fr/servers/tools/' -H 'Cookie: locale=fr; nord_countdown=1649107344587; nord_countdown_iteration=6; nextbid=ce48121b-b30f-47da-861b-448312cbbc41; FirstSession=source%3Dduckduckgo.com%26campaign%3D%26medium%3Dreferral%26term%3D%26content%3D%26hostname%3Dnordvpn.com%26date%3D20220404%26query%3Dnull; CurrentSession=source%3Dduckduckgo.com%26campaign%3D%26medium%3Dreferral%26term%3D%26content%3D%26hostname%3Dnordvpn.com%26date%3D20220404%26query%3Dnull; fontsCssCache=true' -H 'Sec-Fetch-Dest: empty' -H 'Sec-Fetch-Mode: cors' -H 'Sec-Fetch-Site: same-origin' -H 'Sec-GPC: 1' -H 'Pragma: no-cache' -H 'Cache-Control: no-cache' -H 'TE: trailers'
    recommendations=$(curl --retry 3 -LsS "https://api.nordvpn.com/v1/servers/recommendations?${filters}limit=1")
    server=$(jq -r '.[0] | del(.services, .specifications)' <<<"${recommendations}")
    host=$(jq -r '.hostname' <<<"${server}")
    load=$(jq -r '.load' <<<"${server}")
    city=$(jq -r '.locations[0].country.city.name' <<<"${server}")
    if [[ -z ${server} ]]; then
      echo "[$(date -Iseconds)] Unable to select a server"
      sleep infinity
    fi
    echo "[$(date -Iseconds)] Using server: ${host}, load ${load}, city: ${city}"
    EP_IP=$(jq -r '.station' <<<"${server}"):51820
  fi
  if [[ -z ${PUBLIC_KEY} ]]; then
    PUBLIC_KEY=$(jq -r '.technologies[] | select( .identifier == "wireguard_udp" ) | .metadata[] | select( .name == "public_key" ) | .value' <<<"${server}")
  fi
  PRIVATE_KEY=$(cat /run/secrets/NORDLYNX_PRIVKEY)
  [[ -z ${PRIVATE_KEY} ]] && fatal_error "Error, cannot get wireguard private key"
  #Need LISTEN_PORT, PRIVATEKEY, PUBLICKEY, EP_IP, EP_PORT
  eval "echo \"$(cat /etc/wireguard/wg.conf.tmpl)\"" >/etc/wireguard/wg0.conf
  cat /etc/wireguard/wg0.conf
  if [[ -n ${DNS} ]]; then
    echo >/etc/resolv.conf
    for d in ${DNS}; do
      echo "nameserver ${d/,/}" >>/etc/resolv.conf
    done
  fi
}

connectWireguardVpn() {
  chmod 600 /etc/wireguard/wg0.conf
  wg-quick up /etc/wireguard/wg0.conf
}

# Normal run functions
log() {
  printf "%b\n" "$*" >/dev/stderr
}

fatal_error() {
  printf "\e[41mERROR:\033[0m %b\n" "$*" >&2
  exit 1
}

# check for utils
script_needs() {
  command -v $1 >/dev/null 2>&1 || fatal_error "This script requires $1 but it's not installed. Please install it and run again."
}

script_init() {
  log "Checking curl installation"
  script_needs curl
}
