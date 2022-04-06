#!/usr/bin/env bash
#
# add INPUT/FORWARD/NAT iptables rules
# to forward packets between eth0 and wg0

set -e -u -o pipefail

[[ ${NORDVPN_DEBUG:-false} == "true" ]] && set -x || true

IPT="/usr/sbin/iptables"
IPT6="/usr/sbin/ip6tables"

IN_FACE="eth0"                   # NIC connected to the internet
WG_FACE="wg0"                    # WG NIC
# WG IPv4 sub/net aka CIDR
SUB_NET="$(ip -j -4 a | jq -r '.[] |select((.ifname|test("wg0";"i")) or (.ifname|test("nordlynx";"i")) or (.ifname|test("tun";"i")) ) | .addr_info[].local,"/",.addr_info[].prefixlen'| tr -d '\n')"
WG_PORT="${LISTEN_PORT:-51820}"  # WG udp port
SUB_NET_6="$(ip -j -6 a | jq -r '.[] |select((.ifname|test("wg0";"i")) or (.ifname|test("nordlynx";"i")) or (.ifname|test("tun";"i")) ) | .addr_info[].local,"/",.addr_info[].prefixlen'| tr -d '\n')"  # WG IPv6 sub/net

## IPv4 ##
# add rule: forward from wg0 (sub_net) to lan (eth0) with masquerade
$IPT -t nat -I POSTROUTING 1 -s $SUB_NET -o $IN_FACE -j MASQUERADE
# add rule: allow inpout from wg0
$IPT -I INPUT 1 -i $WG_FACE -j ACCEPT
# add rule: allow switching from/to wg0/lan
$IPT -I FORWARD 1 -i $IN_FACE -o $WG_FACE -j ACCEPT
$IPT -I FORWARD 1 -i $WG_FACE -o $IN_FACE -j ACCEPT
$IPT -I INPUT 1 -i $IN_FACE -p udp --dport $WG_PORT -j ACCEPT

## IPv6 (Uncomment) ##
## $IPT6 -t nat -I POSTROUTING 1 -s $SUB_NET_6 -o $IN_FACE -j MASQUERADE
## $IPT6 -I INPUT 1 -i $WG_FACE -j ACCEPT
## $IPT6 -I FORWARD 1 -i $IN_FACE -o $WG_FACE -j ACCEPT
## $IPT6 -I FORWARD 1 -i $WG_FACE -o $IN_FACE -j ACCEPT
