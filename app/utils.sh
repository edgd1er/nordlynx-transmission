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

eval $(/sbin/ip route list match 0.0.0.0 | awk '{if($5!="tun0"){print "GW="$3"\nINT="$5; exit}}')
export GW
export INT
export nordvpn_api="https://api.nordvpn.com"

getTransCreds() {
  CREDS=""
  #use secrets
  if [[ -f /run/secrets/RPC_CREDS ]]; then
    r=($(</run/secrets/RPC_CREDS))
    CREDS="-n ${r[0]}:${r[1]}"
    export TRANSMISSION_RPC_USERNAME=${r[0]}
    export TRANSMISSION_RPC_PASSWORD=${r[1]}
  #if env set
  elif [[ -n ${TRANSMISSION_RPC_USERNAME:-''} ]]; then
    CREDS="-n ${TRANSMISSION_RPC_USERNAME}:${TRANSMISSION_RPC_PASSWORD}"
  fi
  echo "${CREDS}"
}

checkDns() {
  # Test DNS resolution
  if ! dig +short ${HEALTH_CHECK_HOST:-"google.com"} 1>/dev/null 2>&1; then
    echo "WARNING: DNS resolution test failed"
  else
    echo "INFO: DNS resolution test ok"
  fi
}

getCurrentWanIp() {
  myIp=$(curl -s -m 5 'ifconfig.me/ip')
  if [[ -n ${myIp} ]]; then
    echo $myIp
  else
    i=$(curl -m 5 'https://api.ipify.org?format=json' 2>&1)
    if [[ $? ]]; then
      echo ${i} | jq -r .ip
    else
      checkDNS
      echo "ERROR: getCurrentWanIp: cannot get my ip"
    fi
  fi
}

getVpnProtectionStatus() {
  nordvpn status | tr '[:upper:]' '[:lower:]'
}

getVpnItf() {
  ip -j a | jq -r '.[].ifname | match("wg0|nordlynx|nordtun")| .string'
}

getEthIp() {
  ip -j a | jq -r '.[] |select(.ifname=="eth0")| .addr_info[].local'
}

getEthCidr() {
  ip -j a show eth0 | jq -r '.[].addr_info[0]|"\( .broadcast)/\(.prefixlen)"' | sed 's/255/0/g'
}

generateDantedConf() {
  log "INFO: DANTE: set configuration socks proxy"
  SOURCE_DANTE_CONF=/etc/danted.conf.tmpl
  DANTE_CONF=/etc/dante.conf
  INTERFACE=$(getVpnItf)
  sed "s/INTERFACE/${INTERFACE}/" ${SOURCE_DANTE_CONF} >${DANTE_CONF}
  sed -i "s/DANTE_DEBUG/${DANTE_DEBUG}/" ${DANTE_CONF}

  #basic Auth
  TINYCRED=$(getTinyCred)
  if [[ -n ${TINYCRED:-''} ]]; then
    createUserForAuthifNeeded ${TINYCRED}
    sed -i -r "s/#?socksmethod: .*/socksmethod: username/" ${DANTE_CONF}
  else
    sed -i -r "s/#?socksmethod: .*/socksmethod: none/" ${DANTE_CONF}
  fi

  #Allow from private addresses from clients
  if [[ -n ${LOCAL_NETWORK:-''} ]]; then
    aln=(${LOCAL_NETWORK//,/ })
    msg=""
    for l in ${aln[*]}; do
      echo "client pass {
        from: ${l} to: 0.0.0.0/0
	log: error
}" >>${DANTE_CONF}
    done
  else
    #no local network defined, allowing known private addresses.
    echo "#Allow private addresses from clients
client pass {
        from: 10.0.0.0/8 to: 0.0.0.0/0
  log: error
}

client pass {
        from: 172.16.0.0/12 to: 0.0.0.0/0
	log: error
}

client pass {
        from: 192.168.0.0/16 to: 0.0.0.0/0
	log: error
}" >>${DANTE_CONF}
  fi

  #Allow local access + eth0 network
  echo "client pass {
        from: 127.0.0.0/8 to: 0.0.0.0/0
	log: error
}

client pass {
        from: $(getEthCidr) to: 0.0.0.0/0
	log: error
}

#Allow all sockets connections
socks pass {
        from: 0.0.0.0/0 to: 0.0.0.0/0
        protocol: tcp udp
        log: error
}
" >>${DANTE_CONF}
  [[ -n ${DANTE_LOGLEVEL} ]] && sed -i "s/log: DANTE_LOGLEVEL/log: ${DANTE_LOGLEVEL}/" ${DANTE_CONF}
  [[ 0 -ne ${DANTE_DEBUG} ]] && cat ${DANTE_CONF}
  sed -i "s/log: error/log: ${DANTE_LOGLEVEL}/g" ${DANTE_CONF}

  #define logoutput
  if [[ "file" == ${DANTE_LOGOUTPUT} ]]; then
    LOGDIR=/config/log
    mkdir -p ${LOGDIR}
    echo "Setting dante log to ${LOGDIR}/dante.log"
    sed -i -r "s%^#?logoutput: DANTE_LOGOUTPUT%logoutput: ${LOGDIR}/dante.log%" ${DANTE_CONF}
  else
    echo "Settting dante log to stdout"
    sed -i -r "s%^#?logoutput: DANTE_LOGOUTPUT%logoutput: stdout%" ${DANTE_CONF}
  fi

  log "INFO: DANTE: check configuration socks proxy"
  danted -Vf ${DANTE_CONF}
}

generateTinyproxyConf() {
  SOURCE_CONF=/etc/tinyproxy.conf.tmpl
  CONF=/etc/tinyproxy/tinyproxy.conf
  LOGDIR=/config/log
  mkdir -p $(dirname ${CONF}) -p ${LOGDIR}
  TINYPORT=${WEBPROXY_PORT:-8888}
  #Critical (least verbose), Error, Warning, Notice, Connect (to log connections without Info's noise), Info
  TINY_LOGLEVEL=${TINY_LOGLEVEL:-Error}

  EXT_IP=$(getNordlynxIp)
  INT_IP=$(getEthIp)
  INT_CIDR=$(getEthCidr)

  #Main
  log "INFO: TINYPROXY: set configuration INT_IP: ${INT_IP}/ EXT_IP: ${EXT_IP} / log level: ${TINY_LOGLEVEL} / local network: ${LOCAL_NETWORK}"
  sed "s/TINYPORT/${TINYPORT}/" ${SOURCE_CONF} >${CONF}
  sed -i "s/TINY_LOGLEVEL/${TINY_LOGLEVEL}/" ${CONF}
  sed -i "s/#Listen .*/Listen ${INT_IP}/" ${CONF}
  sed -i "s!#Allow INT_CIDR!Allow ${INT_CIDR}!" ${CONF}

  if [[ "file" == "${TINYLOGOUTPUT}" ]]; then
    [[ ! -d ${LOGDIR} ]] &&mkdir -p ${LOGDIR} || true
    touch ${LOGDIR}/tinyproxy.log
    chown tinyproxy:tinyproxy ${LOGDIR}/tinyproxy.log
    sed -i -r "s%^#?LogFile.*%LogFile \"${LOGDIR}/tinyproxy.log\"%" ${CONF}
  fi

  #basic Auth
  TCREDS_SECRET_FILE=/run/secrets/TINY_CREDS
  if [[ -f ${TCREDS_SECRET_FILE} ]]; then
    TINYUSER=$(head -1 ${TCREDS_SECRET_FILE})
    TINYPASS=$(tail -1 ${TCREDS_SECRET_FILE})
  fi
  if [[ -n ${TINYUSER:-''} ]] && [[ -n ${TINYPASS:-''} ]]; then
    sed -i -r "s/#?BasicAuth user password/BasicAuth ${TINYUSER} ${TINYPASS}/" ${CONF}
    sed -i -r "s/^#?upstream socks5.*/upstream socks5 ${TINYUSER}:${TINYPASS}@localhost:1080/" ${CONF}
  else
    sed -i -r "s/^#?BasicAuth .*/#BasicAuthuser password/" ${CONF}
    sed -i -r "s/^#?upstream socks5.*/upstream socks5 localhost:1080/" ${CONF}
  fi

  #Allow only local network or all private address ranges
  if [[ -n ${LOCAL_NETWORK:-''} ]]; then
    aln=(${LOCAL_NETWORK//,/ })
    msg="s%#Allow LOCAL_NETWORK%Allow "
    for l in ${aln[*]}; do
      msg+="${l}\nAllow "
    done
    sed -i "${msg:0:-6}%" ${CONF}
  else
    #or all private address ranges, may 10.x.x.x/8 is not a good idea as it is also the vpn range.
    sed -i "s!#Allow 10!Allow 10!" ${CONF}
    sed -i "s!#Allow 172!Allow 172!" ${CONF}
    sed -i "s!#Allow 192!Allow 192!" ${CONF}
  fi

  [[ ${DEBUG:-false} ]] && grep -vE "(^#|^$)" ${CONF} || true
}
####################
# NORDVPN specific #
####################

getJsonFromNordApi() {
  set +x
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
  export possible_technologies=$(echo ${json_technologies} | jq -r '[.[].name] | @csv' | tr -d '\"')
  export possible_technologies_id=$(echo ${json_technologies} | jq -r '[.[].identifier] |@csv' | tr -d '\"')
  log "Checking NORDPVN API responses"
  for po in json_countries json_groups json_technologies; do
    if [[ $(echo ${!po} | grep -c "<html>") -gt 0 ]]; then
      msg=$(echo ${!po} | grep -oP "(?<=title>)[^<]+")
      log "ERROR, unexpected html content from NORDVPN servers: ${msg}"
      sleep 30
      exit
    fi
  done
  log "End checking NORDPVN API responses"
  [[ ${NORDVPN_DEBUG:-false} == "true" ]] && set -x || true
}

getNordlynxIp() {
  ip -j a | jq -r '.[] |select((.ifname|test("wg0";"i")) or (.ifname|test("nordlynx";"i")) or (.ifname|test("tun";"i")) ) | .addr_info[].local'
}

extractLynxConf() {
  [[ ${GENERATE_WIREGUARD_CONF} != true ]] && return || true
  if [[ ${TECHNOLOGY,,} != nordlynx ]]; then
    log "Info: NORDPVN: Connection is not a Nordlynx (wireguard) type. Cannot extract wireguard information"
    return
  fi
  if [[ -z $(command -v wg) ]]; then
    log "Error: NORDPVN: wireguard kernel and tools not installed. installing required packages, using additionnal 317 MB of disk space."
    apt-get update && apt-get install -y --no-install-recommends wireguard wireguard-tools
  fi
  wg showconf nordlynx >/etc/wireguard/wg0.conf
  chmod 600 /etc/wireguard/wg0.conf
  log "Wireguard configuration written to /etc/wireguard/wg0.conf"
  cat /etc/wireguard/wg0.conf
}

startNordVpn() {
  #Use secrets if present
  #hide credentials even in debug
  set +x
  #Use secrets if present
  if [ -e /run/secrets/NORDVPN_CREDS ]; then
    mapfile -t -n 2 vars </run/secrets/NORDVPN_CREDS
    if [[ ${#vars[*]} -eq 2 ]]; then
      NORDVPN_LOGIN=${vars[0]}
      NORDVPN_PASS=${vars[1]}
    elif [[ ${#vars[*]} -eq 1 ]]; then
      log "WARNING: Only one line found, assuming token."
      NORDVPN_LOGIN=${vars[0]}
      NORDVPN_PASS=''
    fi
  fi

  if [[ -z ${NORDVPN_LOGIN:-''} ]]; then
    log "ERROR: NORDVPN: **********************"
    log "ERROR: NORDVPN: empty user or token   "
    log "ERROR: NORDVPN: **********************"
    exit 1
  fi

  if [[ -z ${NORDVPN_PASS:-''} ]]; then
    logincmd="login --token ${NORDVPN_LOGIN}"
  else
    logincmd="login --username ${NORDVPN_LOGIN} --password ${NORDVPN_PASS}"
  fi

  log "INFO: NORDVPN: starting nordvpn daemon"
  action=start
  isRunning=$(supervisorctl status nordvpnd | grep -c RUNNING) || true
  [[ 0 -le ${isRunning} ]] && action=restart
  [[ -e ${RDIR}/nordvpnd.sock ]] && rm -f ${RDIR}/nordvpnd.sock
  #start nordvpn daemon
  while [ ! -S ${RDIR}/nordvpnd.sock ]; do
    log "WARNING: NORDVPN: restart nordvpn daemon as no socket was found"
    supervisorctl ${action} nordvpnd
    sleep 10
  done

  # login: already logged in return 1
  res="$(nordvpn ${logincmd})" || true
  # restore debug if required.
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
    sleep 5
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

getWireguardServerFromJsonAll() {
  if [[ -z ${jsonAll} ]]; then
    jsonAll=$(curl -LSs "${nordvpn_api}/v1/servers?limit=9999999")
  fi

  #jsonAll=$(curl -LSs "${nordvpn_api}/v1/servers?limit=1000")
  #jsonOne=$(echo $jsonAll | jq '[.[1]]')
  local country=${1,,}
  local city=${2,,}
  if [[ -z ${country} ]] || [[ -z ${city} ]]; then
    log "Error, empty county and/or city"
    return
  fi
  echo $jsonAll | jq "map(select(.technologies[].name|test(\"wireguard\";\"i\")))|map(select(.locations[].country.name|test(\"${country}\";\"i\")))|map(select(.locations[].country.city.name|test(\"${city}\";\"i\")))|."
}

country_filter() {
  local country=(${*//[;,]/ })
  if [[ ${#country[@]} -ge 1 ]]; then
    country=${country[@]//_/ }
    local country_id=$(echo ${json_countries} | jq --raw-output ".[] | select( (.name|test(\"^${country}$\";\"i\")) or (.code|test(\"^${country}$\";\"i\")) ) | .id" | head -n 1)
  fi
  if [[ -n ${country_id} ]]; then
    #log "Searching for country : ${country} (${country_id})"
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
    local city_id=$(echo ${json_countries} | jq --raw-output ".[].cities[]| select(.name|test(\"${city}\";\"i\")) |.id")
    if [[ -n ${city_id} ]]; then
      #log "found city : ${city} (${city_id})"
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
    #log "found group: ${category} (${identifier})"
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
    #log "found technology: ${technology} (${identifier})"
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
    filters+="$(technologies_filter wireguard_udp)"
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
  set +x
  PRIVATE_KEY=$(cat /run/secrets/NORDVPN_PRIVKEY)
  [[ -z ${PRIVATE_KEY} ]] && fatal_error "Error, cannot get wireguard private key"
  [[ ${NORDVPN_DEBUG,,} == true ]] && set -x || true
  #Need LISTEN_PORT, PRIVATEKEY, PUBLICKEY, EP_IP, EP_PORT, Address
  eval "echo \"$(cat /etc/wireguard/wg.conf.tmpl)\"" >/etc/wireguard/wg0.conf
  # cannot install resolconfctl in docker, workaround
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
  wg show wg0
}

enforce_proxies_nordvpn() {
  T_PORT=$(grep -oP "(?<=rpc-port\": )[^,]+" /config/transmission-home/settings.json)
  T_PORT=${T_PORT:-9091}
  log "proxies: allow ports 1080, ${WEBPROXY_PORT}"
  nordvpn whitelist add port 1080 protocol TCP || true
  nordvpn whitelist add port 1080 protocol UDP || true
  nordvpn whitelist add port ${WEBPROXY_PORT} protocol TCP || true
  nordvpn whitelist add port ${T_PORT} protocol TCP || true
  iptables -L
}

enforce_iptables() {
  log "WARNING: enforce_iptables: Nothing done."

}
iptableProtection() {
  log "INFO: iptables: setting iptables."
  #iptables -P INPUT ACCEPT
  #iptables -P FORWARD ACCEPT
  #iptables -L -P OUTPUT ACCEPT
  #iptables -L -A INPUT -s 185.240.244.11/32 -i eth0 -j ACCEPT
  #iptables -L -A INPUT -s 172.16.0.0/12 -i eth0 -j ACCEPT
  #iptables -L -A INPUT -s 172.23.0.0/16 -i eth0 -j ACCEPT
  #iptables -L -A INPUT -i eth0 -j DROP
  #iptables -L -A OUTPUT -d 185.240.244.11/32 -o eth0 -j ACCEPT
  #iptables -L -A OUTPUT -d 172.16.0.0/12 -o eth0 -j ACCEPT
  #iptables -L -A OUTPUT -d 172.23.0.0/16 -o eth0 -j ACCEPT
  #iptables -L -A OUTPUT -o eth0 -j DROP
}

########################
# Normal run functions #
########################
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

log() {
  echo "$(date +"%Y-%m-%d %T"): $*"
}

setTimeZone() {
  [[ ${TZ} == $(cat /etc/timezone) ]] && return
  log "INFO: Setting timezone to ${TZ}"
  ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime
  dpkg-reconfigure -fnoninteractive tzdata
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
    log "**********************************************************************"
  else
    log "INFO: No update needed for nordvpn (${VERSION})"
  fi
}

installedRequiredNordVpnClient() {
  MAXVER=$(apt-cache policy nordvpn | grep -oP "Candidat.*: \K.+")
  installed=$(apt-cache policy nordvpn | grep -oP "Install.*: \K.+")
  NEW=${1:-${NORDVPN_VERSION}}
  if [[ ${installed} != "${NEW}" ]]; then
    log "*************************************************************************************"
    log "INFO: current is ${installed}, installing nordvpn ${NEW}, latest version is ${MAXVER}"
    log "*************************************************************************************"
    log "INFO: stopping nordvpn's killswitch as 3.17.x have a bug preventing accessing to internet"
    [[ -n $(pgrep nordvpnd 2>&1) ]] && nordvpn s killswitch false || true
    apt-get update && apt-get install -y --allow-downgrades nordvpn=${NEW}
    installed=${NEW}
  fi
  if [[ ${installed} =~ 3.17.[0-9] ]]; then
    log "*************************************************************************************"
    log "WARNING: 3.17.x versions are failing tests. (unable to connect). set NORDVPN_VERSION "
    log "WARNING: to downgrade"
    log "*************************************************************************************"
  fi
}

createUserForAuthifNeeded() {
  ARG1=${1:-':'}
  IFS=':' read -r -a arr <<<"${ARG1}"
  TINYUSER=${arr[0]}
  #expected error when user does not exist
  if [[ -n ${TINYUSER} ]]; then
    TINYPASS=${arr[1]::-1}
    tinyid=$(id -u ${TINYUSER}) || true
    if [[ -z ${tinyid} ]]; then
      adduser --gecos "" --no-create-home --disabled-password  --shell /usr/sbin/nologin --ingroup tinyproxy ${TINYUSER}
    fi
    echo "${TINYUSER}:${TINYPASS}" |chpasswd
  fi

}

getTinyCred() {
  TCREDS_SECRET_FILE=/run/secrets/TINY_CREDS
  if [[ -f ${TCREDS_SECRET_FILE} ]]; then
    TINYUSER=$(head -1 ${TCREDS_SECRET_FILE})
    TINYPASS=$(tail -1 ${TCREDS_SECRET_FILE})
  fi
  if [[ -n ${TINYUSER:-''} ]] && [[ -n ${TINYPASS:-''} ]]; then
    TINYCRED="${TINYUSER}:${TINYPASS}@"
  else
    TINYCRED=""
  fi
  echo "${TINYCRED}"
}

getTinyConf() {
  grep -v ^# /etc/tinyproxy/tinyproxy.conf | sed "/^$/d"
}

getDanteConf() {
  grep -v ^# /etc/dante.conf | sed "/^$/d"
}

getTinyListen() {
  grep -oP "(?<=^Listen )[0-9\.]+" /etc/tinyproxy/tinyproxy.conf
}

changeTinyListenAddress() {
  listen_ip4=$(getTinyListen)
  current_ip4=$(getEthIp)
  if [[ ! -z ${listen_ip4} ]] && [[ ! -z ${current_ip4} ]] && [[ ${listen_ip4} != ${current_ip4} ]]; then
    #dante ecoute sur le nom de l'interface eth0
    echo "Tinyproxy: changing listening address from ${listen_ip4} to ${current_ip4}"
    sed -i "s/${listen_ip4}/${current_ip4}/" /etc/tinyproxy/tinyproxy.conf
    supervisorctl restart tinyproxy
  fi
}

getLatestTransmissionWebUI() {
  newVer=$(curl -s "https://api.github.com/repos/transmission-web-control/transmission-web-control/releases/latest" | jq -r .tag_name)
  wget --no-cache -qO- "https://github.com/transmission-web-control/transmission-web-control/releases/download/${newVer}/dist.tar.gz" | tar -C /opt/transmission-ui/transmission-web-control/ --strip-components=2 -xz
}

stop_transmission() {
  #cannot use https://github.com/transmission/transmission/blob/main/docs/rpc-spec.md#233-authentication
  #as rpc-password is required to set daemon's password.
  #username and #password are set
  if [[ -n ${TRANSMISSION_RPC_USERNAME} ]] && [[ -n ${TRANSMISSION_RPC_PASSWORD} ]]; then
    CREDS="-n \"${TRANSMISSION_RPC_USERNAME}:${TRANSMISSION_RPC_PASSWORD}\""
  else
    #No creds set
    CREDS=""
  fi

  container_ip=$(getEthIp)
  while [ 1 -le $(pgrep -c "transmission-daemon") ]; do
    transmission-remote http://${container_ip}:${TRANSMISSION_RPC_PORT} ${CREDS} --exit
    sleep 1
  done
  unset CREDS
}

## tests functions
testhproxy() {
  PROXY_HOST=$(getEthIp)
  TINYCRED=$(getTinyCred)
  IP=$(curl -m5 -sqx http://${TINYCRED}${PROXY_HOST}:${WEBPROXY_PORT} "https://ifconfig.me/ip")
  if [[ $? -eq 0 ]]; then
    log "IP through http proxy is ${IP}"
  else
    log "ERROR: testhproxy: curl through http proxy to https://ifconfig.me/ip failed"
  fi
}

testsproxy() {
  PROXY_HOST=$(getEthIp)
  TINYCRED=$(getTinyCred)
  IP=$(curl -m5 -sqx socks5://${TINYCRED}${PROXY_HOST}:1080 "https://ifconfig.me/ip")
  if [[ $? -eq 0 ]]; then
    log "IP through socks proxy is ${IP}"
  else
    log "ERROR: testsproxy: curl through socks proxy to https://ifconfig.me/ip failed"
  fi
}

checkRights() {
  touch /data/watch/tt
  if [[ ! $? ]]; then
    log "Error, cannot write to /data/watch"
    return 1
  else
    rm /data/watch/tt
  fi
  return 0
}

checkServices() {
  for s in nordvpnd dante tinyproxy transmission; do
    sta=$(supervisorctl status $s | grep -ic running)
    if [[ 0 -eq ${sta} ]]; then
      log "$s is stopped."
      return 1
    fi
  done
  return 0
}

#export creds if set as secrets
if [[ -z ${TRANSMISSION_RPC_USERNAME:-''} ]]; then
  getTransCreds 2>&1 >/dev/null
fi
