#!/bin/bash

set -euo pipefail

[[ -f /app/utils.sh ]] && source /app/utils.sh || true
[[ ${TRANSMISSION_DEBUG} != "false" ]] && set -x || true

#Vars
dev=$(getVpnItf)
container_ip=$(getEthIp)
nordlynx_ip=$(getNordlynxIp)
vpn_itf=$(getVpnItf)
env_var_script=/app/transmission/environment-variables.sh

#Functions
log() {
  #printf "${TIME_FORMAT} %b\n" "$*" >/dev/stderr
  printf "%b\n" "$*" >/dev/stderr
}

# Source our persisted env variables from container startup
#. env_var_scriptoi

[[ -n ${TRANSMISSION_RPC_USERNAME} ]] && CREDS="-n \"${TRANSMISSION_RPC_USERNAME}:${TRANSMISSION_RPC_PASSWORD}\"" || CREDS=""
while [ $(ps -ef |grep -c transmission-daemon ) -gt 1 ]
do
  transmission-remote http://${container_ip}:${TRANSMISSION_RPC_PORT} ${CREDS} --exit
  sleep 1
done
unset CREDS

# If transmission-pre-start.sh exists, run it
SCRIPT=/etc/scripts/transmission-pre-start.sh
if [[ -x ${SCRIPT} ]]; then
  echo "Executing ${SCRIPT}"
  #${SCRIPT} "$@"
  ${SCRIPT} "${USER_SCRIPT_ARGS[*]}"
  echo "${SCRIPT} returned $?"
fi


# Add containerIp to RPC_WHITELIST if missing
if [[ ! ${TRANSMISSION_RPC_WHITELIST} =~ ${container_ip} ]]; then
  dockerNet=$(echo ${container_ip} |grep -oP ".+\.")"*"
  log "Adding ${dockerNet} to TRANSMISSION_RPC_WHITELIST (${TRANSMISSION_RPC_WHITELIST})"
 TRANSMISSION_RPC_WHITELIST=${TRANSMISSION_RPC_WHITELIST},${dockerNet}
fi
# Persist transmission settings for use by transmission-daemon
python3 /app/transmission/persistEnvironment.py ${env_var_script}

log "Updating TRANSMISSION_BIND_ADDRESS_IPV4 to the ip of ${dev} : ${container_ip}"
export TRANSMISSION_BIND_ADDRESS_IPV4=${nordlynx_ip}
# Also update the persisted settings in case it is already set. First remove any old value, then add new.
sed -i '/TRANSMISSION_BIND_ADDRESS_IPV4/d' ${env_var_script}

log "Updating TRANSMISSION_RPC_BIND_ADDRESS to the ip of ${container_ip}"
export TRANSMISSION_RPC_BIND_ADDRESS=${container_ip}
sed -i '/TRANSMISSION_BIND_ADDRESS_IPV4/d' ${env_var_script}
log "export TRANSMISSION_BIND_ADDRESS_IPV4=${container_ip}" >> ${env_var_script}

#define UI
if [[ "combustion" = "$TRANSMISSION_WEB_UI" ]]; then
  log "Using Combustion UI, overriding TRANSMISSION_WEB_HOME"
  export TRANSMISSION_WEB_HOME=/opt/transmission-ui/combustion-release
fi

if [[ "kettu" = "$TRANSMISSION_WEB_UI" ]]; then
  log "Using Kettu UI, overriding TRANSMISSION_WEB_HOME"
  export TRANSMISSION_WEB_HOME=/opt/transmission-ui/kettu
fi

if [[ "transmission-web-control" = "$TRANSMISSION_WEB_UI" ]]; then
  log "Using Transmission Web Control UI, overriding TRANSMISSION_WEB_HOME"
  export TRANSMISSION_WEB_HOME=/opt/transmission-ui/transmission-web-control
fi

if [[ "flood-for-transmission" = "$TRANSMISSION_WEB_UI" ]]; then
  log "Using Flood for Transmission UI, overriding TRANSMISSION_WEB_HOME"
  export TRANSMISSION_WEB_HOME=/opt/transmission-ui/flood-for-transmission
fi

if [[ "shift" = "$TRANSMISSION_WEB_UI" ]]; then
  log "Using Shift UI, overriding TRANSMISSION_WEB_HOME"
  export TRANSMISSION_WEB_HOME=/opt/transmission-ui/shift
fi

if [[ -z $TRANSMISSION_WEB_UI ]]; then
  log "Defaulting TRANSMISSION_WEB_HOME to Transmission Web Control UI"
  export TRANSMISSION_WEB_HOME=/opt/transmission-ui/transmission-web-control
fi

echo "Updating Transmission settings.json with values from env variables"
# Ensure TRANSMISSION_HOME is created
mkdir -p ${TRANSMISSION_HOME}

. /app/transmission/userSetup.sh

su --preserve-environment ${RUN_AS} -s /usr/bin/python3 /app/transmission/updateSettings.py /app/transmission/default-settings.json ${TRANSMISSION_HOME}/settings.json || exit 1
log "sed'ing True to true"
su --preserve-environment ${RUN_AS} -c "sed -i 's/True/true/g' ${TRANSMISSION_HOME}/settings.json"
setNewUSer

if [[ ! -e "/dev/random" ]]; then
  # Avoid "Fatal: no entropy gathering module detected" error
  log "INFO: /dev/random not found - symlink to /dev/urandom"
  ln -s /dev/urandom /dev/random
fi

if [[ "true" = "${LOG_TO_STDOUT}" ]]; then
  LOG="--logfile /dev/stdout"
  #LOG=
else
  LOG="--logfile ${TRANSMISSION_HOME}/transmission.log"
fi

log "STARTING TRANSMISSION with ${nordlynx_ip} mounted on ${vpn_itf}, container ip is ${container_ip}"
su --preserve-environment ${RUN_AS} -s /bin/bash -c "/usr/bin/transmission-daemon -f -g ${TRANSMISSION_HOME} ${LOG}"

#TODO execute post start.
# If transmission-post-start.sh exists, run it
SCRIPT=/etc/scripts/transmission-post-start.sh
if [[ -x ${SCRIPT}   ]]; then
  echo "Executing ${SCRIPT}"
  ${SCRIPT} "${USER_SCRIPT_ARGS[*]}"
  echo "${SCRIPT} returned $?"
fi

log "Transmission startup script complete."