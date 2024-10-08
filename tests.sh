#!/usr/bin/env bash

#vars
CPSE=compose.yml
PROXY_HOST="localhost"
SOCK_PORT=2080 # proxy socks
HTTP_PORT=2888 # proxy http
HTTP_PORT=28$(grep -oP '(?<=\- "28)[^:]+' ${CPSE})
SOCK_PORT=20$(grep -oP '(?<=\- "20)[^:]+' ${CPSE})
SERVICE=transmission
TRANS_PORT=9091
#Common
FAILED=0
INTERVAL=4
BUILD=1

#Functions
buildAndWait() {
  echo "Stopping and removing running containers"
  docker compose -f ${CPSE} down -v
  echo "Building and starting image"
  docker compose -f ${CPSE} up -d --build
  echo "Waiting for the container to be up.(every ${INTERVAL} sec)"
  logs=""
  #  while [ 0 -eq $(echo $logs | grep -c "Initialization Sequence Completed") ]; do
  while [ 0 -eq $(echo $logs | grep -c "exited: start_vpn (exit status 0; expected") ]; do
    logs="$(docker compose -f ${CPSE} logs)"
    sleep ${INTERVAL}
    ((n+=1))
    echo "loop: ${n}: $(docker compose -f ${CPSE} logs | tail -1)"
    [[ ${n} -eq 15 ]] && break || true
  done
  docker compose -f ${CPSE} logs
}

areProxiesPortOpened() {
  for PORT in ${HTTP_PORT} ${SOCK_PORT} ${TRANS_PORT}; do
    msg="Test connection to port ${PORT}: "
    if [ 0 -eq $(echo "" | nc -v -w2 ${PROXY_HOST} ${PORT} 2>&1 | grep -c "] succeeded") ]; then
      msg+=" Failed"
      ((FAILED += 1))
    else
      msg+=" OK"
    fi
    echo -e "$msg"
  done
}

testProxies() {
  if [[ -f ./tiny_creds ]]; then
    usertiny=$(head -1 ./tiny_creds)
    passtiny=$(tail -1 ./tiny_creds)
    echo "Getting tinyCreds from file: ${usertiny}:${passtiny}"
    TCREDS="${usertiny}:${passtiny}@"
    DCREDS=${TCREDS}
  else
    usertiny=$(grep -oP "(?<=- TINYUSER=)[^ ]+" ${CPSE})
    passtiny=$(grep -oP "(?<=- TINYPASS=)[^ ]+" ${CPSE})
    echo "Getting tinyCreds from compose: ${usertiny}:${passtiny}"
    TCREDS="${usertiny}:${passtiny}@"
    DCREDS=${TCREDS}

  fi
  if [[ -z ${usertiny:-''} ]]; then
    echo "No tinyCreds"
    TCREDS=""
    DCREDS=""
  fi
  #check http proxy
  vpnIP=$(curl -4m5 -sx http://${TCREDS}${PROXY_HOST}:${HTTP_PORT} "https://ifconfig.me/ip")
  if [[ $? -eq 0 ]] && [[ ${myIp} != "${vpnIP}" ]] && [[ ${#vpnIP} -gt 0 ]]; then
    echo "http proxy: IP is ${vpnIP}, mine is ${myIp}"
  else
    echo "Error, curl through http proxy to https://ifconfig.me/ip failed"
    echo "or IP (${myIp}) == vpnIP (${vpnIP})"
    ((FAILED += 1))
  fi

  #check sock proxy
  vpnIP=$(curl -4m5 -sx socks5h://${DCREDS}${PROXY_HOST}:${SOCK_PORT} "http://ipv4.lafibre.info/ip.php") || true
  if [[ $? -eq 0 ]] && [[ ${myIp} != "${vpnIP}" ]] && [[ ${#vpnIP} -gt 0 ]]; then
    echo "socks proxy: IP is ${vpnIP}, mine is ${myIp}"
  else
    echo "Error, curl through socks proxy to http://ipv4.lafibre.info/ip.php failed"
    echo "or IP (${myIp}) == vpnIP (${vpnIP})"
    ((FAILED += 1))
  fi

  echo "# failed tests: ${FAILED}"
  return ${FAILED}
}

getInterfacesInfo(){
  docker compose exec ${SERVICE} bash -c "ip -j a |jq  '.[]|select(.ifname|test(\"wg0|tun|nordlynx\"))|.ifname'"
  itf=$(docker compose -f ${CPSE} exec ${SERVICE} ip -j a)
  echo eth0:$(echo $itf | jq -r '.[] |select(.ifname=="eth0")| .addr_info[].local')
  echo wg0: $(echo $itf | jq -r '.[] |select(.ifname=="wg0")| .addr_info[].local')
  echo nordlynx: $(echo $itf | jq -r '.[] |select(.ifname=="nordlynx")| .addr_info[].local')
  docker compose -f ${CPSE} exec ${SERVICE} bash -c 'echo "nordlynx conf: $(wg showconf nordlynx 2>/dev/null)"'
  docker compose -f ${CPSE} exec ${SERVICE} bash -c 'echo "wg conf: $(wg showconf wg0 2>/dev/null)"'
}

getAliasesOutput(){
  docker compose -f ${CPSE} exec ${SERVICE} bash -c 'while read -r line; do echo $line;eval $line;done <<<$(grep ^alias ~/.bashrc | cut -f 2 -d"'"'"'")'
}

getTransWebPAge(){
  curl http://localhost:${TRANS_PORT}/transmission/web/
}

#Main
[[ -e /.dockerenv ]] && PROXY_HOST=

#Check ports
#Main
[[ -e /.dockerenv ]] && PROXY_HOST=

#Check ports
[[ ${1:-''} == "-t" ]] && BUILD=0 || BUILD=1
[[ -z $(which nc) ]] && echo "No nc found" && exit || true

myIp=$(curl -4m5 -sq https://ifconfig.me/ip)

if [[ "localhost" == "${PROXY_HOST}" ]] && [[ 1 -eq ${BUILD} ]]; then
  buildAndWait
  echo "***************************************************"
  echo "Testing container"
  echo "***************************************************"
  # check returned IP through http and socks proxy
  testProxies
  getInterfacesInfo
  [[ 1 -eq ${BUILD} ]] && docker compose down
else
  echo "***************************************************"
  echo "Testing container"
  echo "***************************************************"
  # check returned IP through http and socks proxy
  testProxies
  getInterfacesInfo
fi

