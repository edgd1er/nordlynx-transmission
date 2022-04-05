#!/usr/bin/env bash

#vars
PROXY_HOST="localhost"
#PROXY_HOST="holdom3.mission.lan"
HTTP_PORT=2888
SOCK_PORT=2081
TRANS_PORT=9091
FAILED=0
INTERVAL=4
BUILD=1

#Functions
buildAndWait() {
  echo "Stopping and removing running containers"
  docker compose down -v
  echo "Building and starting image"
  docker compose -f docker-compose.yml up -d --build
  echo "Waiting for the container to be up.(every ${INTERVAL} sec)"
  logs=""
  while [ 0 -eq $(echo $logs | grep -c "Initialization Sequence Completed") ]; do
    logs="$(docker compose logs)"
    sleep ${INTERVAL}
    ((n++))
    echo "loop: ${n}"
    [[ ${n} -eq 15 ]] && break || true
  done
  docker compose logs
}

#Main
[[ -e /.dockerenv ]] && PROXY_HOST=

#Check ports
[[ $1 == "-t" ]] && BUILD=0
if [[ "localhost" == ${PROXY_HOST} ]] && [[ 1 -eq ${BUILD} ]]; then
  buildAndWait
fi
for PORT in ${HTTP_PORT} ${SOCK_PORT}; do
  msg="Test connection to port ${PORT}: "
  if [ 0 -eq $(echo "" | nc -v -q 2 ${PROXY_HOST} ${PORT} 2>&1 | grep -c "] succeeded") ]; then
    msg+=" Failed"
    ((FAILED += 1))
  else
    msg+=" OK"
  fi
  echo -e "$msg"
done

# check returned IP through http and socks proxy
myIp=$(curl -m5 -sq https://ifconfig.me/ip)

vpnIP=$(curl -m5 -sx http://${PROXY_HOST}:${HTTP_PORT} "https://ifconfig.me/ip")
if [[ $? -eq 0 ]] && [[ ${myIp} == ${vpnIP} ]]; then
  echo "http proxy: IP is ${IP}, mine is ${myIp}"
else
  echo "Error, curl through http proxy to https://ifconfig.me/ip failed"
  echo "or IP (${myIp}) == vpnIP (${vpnIP})"
  ((FAILED += 1))
fi

#check detected ips
vpnIP=$(curl -m5 -sqx socks5://${PROXY_HOST}:${SOCK_PORT} "https://ifconfig.me/ip")
if [[ $? -eq 0 ]] && [[ ${myIp} == ${vpnIP} ]]; then
  echo "socks proxy: IP is ${vpnIP}, mine is ${myIp}"
else
  echo "Error, curl through socks proxy to https://ifconfig.me/ip failed"
  echo "or IP (${myIp}) == vpnIP (${vpnIP})"
  ((FAILED += 1))
fi

echo "# failed tests: ${FAILED}"
exit ${FAILED}

echo "***************************************************"
echo "Testing container"
echo "***************************************************"
docker compose exec lynx bash -c "ip -j a |jq  '.[]|select(.ifname|test(\"wg0|tun|nordlynx\"))|.ifname'"
docker compose exec lynx wg showconf nordlynx 2>/dev/null
docker compose exec lynx echo -e "eth0: $(ip -j a | jq -r '.[] |select(.ifname=="eth0")| .addr_info[].local')\n wg0: $(ip -j a | jq -r '.[] |select(.ifname=="wg0")| .addr_info[].local')\nnordlynx: $(ip -j a | jq -r '.[] |select(.ifname=="nordlynx")| .addr_info[].local')"

[[ 1 -eq ${BUILD} ]] && docker compose down


