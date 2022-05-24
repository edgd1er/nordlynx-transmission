#!/usr/bin/env bash
#
# Remove INPUT/FORWARD/NAT iptables rules
#

set -e -u -o pipefail

[[ ${NORDVPN_DEBUG:-false} == "true" ]] && set -x || true

IPT="/usr/sbin/iptables"
IPT6="/usr/sbin/ip6tables"

IN_FACE=$(ip route get 1 | grep -oP '(?<=dev )\S+')                   # NIC connected to the internet eth0
WG_FACE=$(ip route show table $TABLE | grep -oP '(?<=dev )\S+')       # WG NIC wg0
# WG IPv4 sub/net aka CIDR
SUB_NET="$(ip -j -4 a | jq -r '.[] |select((.ifname|test("wg0";"i")) or (.ifname|test("nordlynx";"i")) or (.ifname|test("tun";"i")) ) | .addr_info[].local,"/",.addr_info[].prefixlen'| tr -d '\n')"
WG_PORT="${LISTEN_PORT:-51820}"  # WG udp port
SUB_NET_6="$(ip -j -6 a | jq -r '.[] |select((.ifname|test("wg0";"i")) or (.ifname|test("nordlynx";"i")) or (.ifname|test("tun";"i")) ) | .addr_info[].local,"/",.addr_info[].prefixlen'| tr -d '\n')"  # WG IPv6 sub/net

# IPv4 rules #
# forward from wg0 (sub_net) to lan (eth0) with masquerade
$IPT -t nat -D POSTROUTING -s $SUB_NET -o $IN_FACE -j MASQUERADE

iptables -D FORWARD -i wg0 -j LOG --log-prefix 'tunnel wireguard iptables: ' --log-level 7
iptables -D FORWARD -o wg0 -j LOG --log-prefix 'tunnel wireguard iptables: ' --log-level 7

#$IPT -D INPUT -i $WG_FACE -j ACCEPT
# allow switching from/to wg0/lan
#$IPT -D FORWARD -i $IN_FACE -o $WG_FACE -j ACCEPT
#$IPT -D FORWARD -i $WG_FACE -o $IN_FACE -j ACCEPT
#$IPT -D INPUT -i $IN_FACE -p udp --dport $WG_PORT -j ACCEPT

# IPv6 rules (uncomment) #
## $IPT6 -t nat -D POSTROUTING -s  -o $IN_FACE -j MASQUERADE
## $IPT6 -D INPUT -i $WG_FACE -j ACCEPT
## $IPT6 -D FORWARD -i $IN_FACE -o $WG_FACE -j ACCEPT
## $IPT6 -D FORWARD -i $WG_FACE -o $IN_FACE -j ACCEPT