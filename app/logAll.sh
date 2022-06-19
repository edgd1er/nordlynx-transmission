#!/usr/bin/env bash
set -e -u -o pipefail

# enable packet logging

#functions
installConfigure(){
  if [[ "" == $(which ulogd) ]]; then
    apt-get update && apt-get install -y ulogd2
  fi

  if [[ ! -f /etc/ulogd.conf ]]; then
  echo "[global]
        logfile=\"/var/log/ulogd.log\"
        stack=log1:NFLOG,base1:BASE,ifi1:IFINDEX,ip2str1:IP2STR,print1:PRINTPKT,emu1:LOGEMU

        [log1]
        group=1

        [emu1]
        file=\"/var/log/ulogd_syslogemu.log\"
        sync=1

" > /etc/ulogd.conf
  fi
}

#Main
[[ 0 -eq ${IPTABLES_LOG:-0} ]] && exit
installConfigure
#INPUT chain
#FORWARD chain
#OUTPUT chain
for c in INPUT FORWARD OUTPUT
do
  isPresent=$(iptables -L ${c} | grep -c nflog-prefix)
  if [[ 0 -eq ${isPresent} ]]; then
    iptables -I $c 1 -j NFLOG --nflog-prefix "[default-drop]:" --nflog-group 1
  fi
done

#To log network activity in the NAT table execute the following commands for tracking activity in their respective chains
for c in PREROUTING POSTROUTING OUTPUT
do
  isPresent=$(iptables -t nat -L ${c} | grep -c nflog-prefix)
  if [[ 0 -eq ${isPresent} ]]; then
    iptables -t nat -I $c 1 -j NFLOG --nflog-prefix "[default-drop]:" --nflog-group 1
  fi
done

echo <EOF >/etc/supervisor/conf.d/ulogd.conf
[program:ulogd]
command = /usr/sbin/ulogd -c /etc/danted.conf -v
user = root
autostart = false
autorestart = false
startsecs = 0
stdout_logfile = /dev/stdout
redirect_stderr = true
stdout_logfile_maxbytes = 0

stderr_logfile_maxbytes = 0
stdout_logfile_backups = 0
stderr_logfile_backups = 0"
EOF

supervist