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
RPC_CREDS=/run/secrets/RPC_CREDS
#Functions
log() {
  #printf "${TIME_FORMAT} %b\n" "$*" >/dev/stderr
  printf "%b\n" "$*" >/dev/stderr
}

# Source our persisted env variables from container startup
#. env_var_scriptoi
if [[ -f ${RPC_CREDS} ]]; then
  #use secrets
  r=($(<${RPC_CREDS}))
  export TRANSMISSION_RPC_USERNAME=${r[0]}
  export TRANSMISSION_RPC_PASSWORD=${r[1]}
  if [[ "${TRANSMISSION_RPC_USERNAME}" == "${TRANSMISSION_RPC_PASSWORD}" ]]; then
    log "Error, TRANSMISSION_RPC_USERNAME and TRANSMISSION_RPC_PASSWORD have to be defined."
  fi
fi

stop_transmission

# If transmission-pre-start.sh exists, run it
SCRIPT=/etc/scripts/transmission-pre-start.sh
if [[ -x ${SCRIPT} ]]; then
  echo "Executing ${SCRIPT}"
  #${SCRIPT} "$@"
  ${SCRIPT} "${USER_SCRIPT_ARGS[*]}"
  echo "${SCRIPT} returned $?"
fi

# Add containerIp to RPC_WHITELIST if enabled and missing
if [[ "true" == "${TRANSMISSION_RPC_WHITELIST_ENABLED}" ]] && [[ ! ${TRANSMISSION_RPC_WHITELIST} =~ ${container_ip} ]]; then
  dockerNet=$(echo ${container_ip} | grep -oP ".+\.")"*"
  log "Adding ${dockerNet} to TRANSMISSION_RPC_WHITELIST (${TRANSMISSION_RPC_WHITELIST})"
  export TRANSMISSION_RPC_WHITELIST=${TRANSMISSION_RPC_WHITELIST},${dockerNet}
fi

log "Updating TRANSMISSION_BIND_ADDRESS_IPV4 to the ip of ${dev} : ${nordlynx_ip}"
export TRANSMISSION_BIND_ADDRESS_IPV4="${nordlynx_ip}"

log "Updating TRANSMISSION_RPC_BIND_ADDRESS to the ip of ${container_ip},127.0.0.1"
export TRANSMISSION_RPC_BIND_ADDRESS="${container_ip},127.0.0.1"

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

case ${TRANSMISSION_LOG_LEVEL,,} in
"trace" | "debug" | "info" | "warn" | "error" | "critical")
  echo "Will exec Transmission with '--log-level=${TRANSMISSION_LOG_LEVEL,,}' argument"
  export TRANSMISSION_LOGGING_LEVEL="${TRANSMISSION_LOG_LEVEL,,}"
  ;;
*)
  export TRANSMISSION_LOGGING_LEVEL=
  ;;
esac

# Persist transmission settings for use by transmission-daemon
python3 /app/transmission/persistEnvironment.py ${env_var_script}
source /app/transmission/userSetup.sh

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
  LOG="/dev/stdout"
else
  LOG="${TRANSMISSION_HOME}/transmission.log"
fi

if [[ -f /usr/local/bin/transmission-daemon ]]; then
  transbin='/usr/local/bin'
else
  transbin='/usr/bin'
fi

# Raise the open-files limit (RLIMIT_NOFILE) for transmission-daemon.
# transmission keeps one fd per peer (peer-limit-global, default 240) plus data,
# resume and log files; the default 1024 soft limit causes intermittent
# "Unable to save resume file: Too many open files" errors. The `su` below resets
# the soft limit back to 1024 even when the hard limit is large, so the limit MUST
# be raised inside the su shell.
if [[ -z "${OPEN_FILES_LIMIT}" ]]; then
  # Default to the hard limit, which the unprivileged RUN_AS user can reach without
  # extra privileges. It may be reported as "unlimited", but transmission can't use
  # an infinite nofile - the kernel caps it at fs.nr_open - so fall back to that.
  OPEN_FILES_LIMIT="$(ulimit -Hn)"
  if [[ "${OPEN_FILES_LIMIT}" == "unlimited" ]]; then
    OPEN_FILES_LIMIT="$(cat /proc/sys/fs/nr_open 2>/dev/null || echo 1048576)"
  fi
fi
echo "Setting transmission open-files (nofile) soft limit to ${OPEN_FILES_LIMIT}"


# Build the transmission-daemon command as an array. It is run as RUN_AS via su,
# which resets the nofile soft limit, so we raise it again inside the su shell.
# ${transmission_cmd[*]@Q} safely quotes each argument for the `bash -c` string.
transmission_cmd=("${transbin}/transmission-daemon")
[[ 0 -lt ${#TRANSMISSION_LOGGING_LEVEL} ]] && transmission_cmd+=("--log-level=${TRANSMISSION_LOGGING_LEVEL}") || true
transmission_cmd+=("-f" "-g" "${TRANSMISSION_HOME}" "--logfile" "${LOG}")

log "STARTING TRANSMISSION $(${transbin}/transmission-remote -V 2>&1 | grep -oP "(?<=remote )[0-9.]+") with ${nordlynx_ip} mounted on ${vpn_itf}, container ip is ${container_ip}"
echo "STARTING TRANSMISSION" "command line:" "${transmission_cmd[*]@Q}"

#su --preserve-environment ${RUN_AS} -s /bin/bash -c "ulimit -n ${OPEN_FILES_LIMIT};${transbin}/transmission-daemon ${TRANSMISSION_LOG_LEVEL,,} -f -g ${TRANSMISSION_HOME} ${LOG}"
su --preserve-environment ${RUN_AS} -s /bin/bash -c "ulimit -n ${OPEN_FILES_LIMIT}; exec ${transmission_cmd[*]@Q}" &

#TODO execute post start.
# If transmission-post-start.sh exists, run it
SCRIPT=/etc/scripts/transmission-post-start.sh
if [[ -x ${SCRIPT} ]]; then
  echo "Executing ${SCRIPT}"
  ${SCRIPT} "${USER_SCRIPT_ARGS[*]}"
  echo "${SCRIPT} returned $?"
fi

log "Transmission startup script complete."
