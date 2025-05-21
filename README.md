[![lint nordlynx transmission dockerfile](https://github.com/edgd1er/nordlynx-transmission/actions/workflows/lint.yml/badge.svg?branch=main)](https://github.com/edgd1er/nordlynx-transmission/actions/workflows/lint.yml)
[![build multi-arch images](https://github.com/edgd1er/nordlynx-transmission/actions/workflows/buildPush.yml/badge.svg?branch=main)](https://github.com/edgd1er/nordlynx-transmission/actions/workflows/buildPush.yml)

![Docker Size](https://badgen.net/docker/size/edgd1er/nordlynx-transmission?icon=docker&label=Size)
![Docker Pulls](https://badgen.net/docker/pulls/edgd1er/nordlynx-transmission?icon=docker&label=Pulls)
![Docker Stars](https://badgen.net/docker/stars/edgd1er/nordlynx-transmission?icon=docker&label=Stars)
![ImageLayers](https://badgen.net/docker/layers/edgd1er/nordlynx-transmission?icon=docker&label=Layers)

# nordlynx-transmission

[Nordvpn client's version](https://nordvpn.com/fr/blog/nordvpn-linux-release-notes/) or [changelog](https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/nordvpn_3.20.2_amd64.changelog): 3.20.2 (30/04/25)

2024/11/18, nordvpn reorganized its repository and removed pre 3.17.0 versions. privileged mode is now required for the container.
30/03/2024: --privileged required for client >= 3.17.0. problem stopping container with client 3.17.x. 
26/06/2023: moving to debian bookworm.

/!\ please consider this project as a work in progress especially concerning iptables/leak management when not using nordvpn client (ie: NORDVPN_PRIVKEY found). 

/!\ since v4 for transmission, building package takes too long for github, `gen_image_buildx.sh -ap` generates debian packages for different architecture arm64, amd64, arm v7, then deb files are uploaded to not rebuild transmission at each image build.

purpose: compare wireguard and nordlynx speed transmisssion.

This is a docker container that connects to the recommended NordVPN servers through nordvpn client or wireguard,  and starts a SOCKS5 proxy (dante),  an http proxy (tinyproxy) and torrent client (transmission).
plain wireguard and nordlynx's wireguard technology are available.

this container is build for amd64, arm64, arm/v7, arm/v6, two tags are available.
As of 08/04/22, V3/v4 will be built regularly, as v4 is the version I use. I stopped the automatic launch for latest's workflow building.
v3: transmission v3 + latest nordvpn client.
v4: transmission v4 + latest nordvpn client.
latest: transmission v3 + latest nordvpn client.

Whenever the connection is lost,  nordvpn client has a killswitch to obliterate the connection.
    
check [IP](https://bash.ws/my-ip),  [DNS](https://bash.ws/dnsleak),  [Torrent](https://bash.ws/torrent-leak-test) or [another torrent](https://bash.ws/torrent-leak-test) leaks or [torrent check guard](https://torguard.net/checkmytorrentipaddress.php?hash=505207fe00ad035bd7e3602baa0e70d53e89e701)

## What is this?

This image is a variation of nordlynx-proxy and has two ways to run.
* the first one through nordvpn tooling using nordlynx. Nordvpn version of [wireguard](https://nordvpn.com/blog/wireguard-simplicity-efficiency/) is [nordlynx](https://nordvpn.com/blog/nordlynx-protocol-wireguard/). Login and password are required.
* The second one through plain wireguard. Wireguard's private key will be needed. That key is exported when running in Nordlynx mode in /etc/wireguard/wg0.conf. No fancy feature like killswitch,  cybersec ... 

you can then expose ports 
* `1080` from the container to access the VPN connection via the SOCKS5 proxy.
* `8888` from the container to access the VPN connection via http proxy.
* `9091` from the container to access transmission web UI.

To sum up,  this container:
* Opens the best connection to NordVPN using NordVpn API results according to your criteria.
* Starts a SOCKS5 proxy that routes `eth0` to `nordlynx.wg0` with [dante-server](https://www.inet.no/dante/).
* nordvpn dns servers perform resolution, by default.
* uses supervisor to handle easily services.

The main advantages are:
- you get the best recommendation for each selection.
- can select openvpn or nordlynx protocol
- use of nordVpn app features (Killswitch,  cybersec,  ....)


please note,  that to avoid dns problem when the dns service is on the same server,  /etc/resolv.conf is set to google DNS (1.1.1.1).
That DNS is used only during startup (check latest nordvpn version)

## Limitations

AS of 22/03/29,  not all nordvpn client's features are implemented in plain wireguard:
* killerswitch
* clever usage of iptables
* cybersec

## Usage

The container may use environment variable to select a server,  otherwise the best recommended server is selected:
see environment variables to get all available options or [nordVpn support](https://support.nordvpn.com/Connectivity/Linux/1325531132/Installing-and-using-NordVPN-on-Debian-Ubuntu-Raspberry-Pi-Elementary-OS-and-Linux-Mint.htm#Settings).

adding 
``` docker
sysclts:
 - net.ipv6.conf.all.disable_ipv6=1 # disable ipv6
 ```
  might be needed,  if nordvpn cannot change the settings itself.

* ANALYTICS: [off,0,false/on,1,true], default on, send anonymous aggregate data: crash reports, OS version, marketing performance, and feature usage data
* TECHNOLOGY: [NordLynx](https://support.nordvpn.com/hc/en-us/articles/19564565879441-What-is-NordLynx)/[OpenVPN](https://support.nordvpn.com/hc/en-us/articles/19683394518161-OpenVPN-connection-on-NordVPN)/[nordwhisper](https://nordvpn.com/blog/nordwhisper-protocol/), default: NordLynx (wireguard like)
* PROTOCOL=tcp # or udp (default), useful only when using openvpn. wireguard is udp only.
* [OBFUSCATE](https://nordvpn.com/features/obfuscated-servers/): [off/on], default off, on hide vpn's use.
* CONNECT = [country]/[server]/[country_code]/[city] or [country] [city],  if none provide you will connect to the recommended server.
* [COUNTRY](https://api.nordvpn.com/v1/servers/countries) define the exit country. Albania, Argentina, Australia, Austria, Belgium, Bosnia_And_Herzegovina, Brazil, Bulgaria, Canada, Chile, Costa_Rica, Croatia, Cyprus, Czech_Republic, Denmark, Estonia, Finland, France, Georgia, Germany, Greece, Hong_Kong, Hungary, Iceland, India, Indonesia, Ireland, Israel, Italy, Japan, Latvia, Lithuania, Luxembourg, Malaysia, Mexico, Moldova, Netherlands, New_Zealand, North_Macedonia, Norway, Poland, Portugal, Romania, Serbia, Singapore, Slovakia, Slovenia, South_Africa, South_Korea, Spain, Sweden, Switzerland, Taiwan, Thailand, Turkey, Ukraine, United_Kingdom, United_States, Vietnam `curl -LSs https://api.nordvpn.com/v1/servers/countries | jq '[.[].name ] | @csv' | tr -d '\\"' | tr ' ' '_'`
* [GROUP](https://api.nordvpn.com/v1/servers/groups): Double VPN, Onion Over VPN, Ultra fast TV, Anti DDoS, Dedicated IP, Standard VPN servers, Netflix USA, P2P, Obfuscated Servers, Europe, The Americas, Asia Pacific, Africa,  the Middle East and India, Anycast DNS, Geo DNS, Grafana, Kapacitor, Socks5 Proxy, FastNetMon,  although many categories are possible,  p2p seems more adapted.
* TECHNOLOGY: ikev2, openvpn_udp, openvpn_tcp, socks, proxy, pptp, l2tp, openvpn_xor_udp, openvpn_xor_tcp, proxy_cybersec, proxy_ssl, proxy_ssl_cybersec, ikev2_v6, openvpn_udp_v6, openvpn_tcp_v6, wireguard_udp, openvpn_udp_tls_crypt, openvpn_tcp_tls_crypt, openvpn_dedicated_udp, openvpn_dedicated_tcp, skylark, mesh_relay. `curl -LSs https://api.nordvpn.com/v1/technologies | jq '[.[].identifier] | @csv' | tr -d '\\"'`
* CITY:  Tirana, Buenos Aires, Adelaide, Brisbane, Melbourne, Perth, Sydney, Vienna, Brussels, Sarajevo, Sao Paulo, Sofia, Montreal, Toronto, Vancouver, Santiago, San Jose, Zagreb, Nicosia, Prague, Copenhagen, Tallinn, Helsinki, Marseille, Paris, Tbilisi, Berlin, Frankfurt, Athens, Hong Kong, Budapest, Reykjavik, Mumbai, Jakarta, Dublin, Tel Aviv, Milan, Tokyo, Riga, Vilnius, Steinsel, Kuala Lumpur, Mexico, Chisinau, Amsterdam, Auckland, Skopje, Oslo, Warsaw, Lisbon, Bucharest, Belgrade, Singapore, Bratislava, Ljubljana, Johannesburg, Seoul, Madrid, Stockholm, Zurich, Taipei, Bangkok, Istanbul, Kyiv, Dubai, Edinburgh, Glasgow, London, Manchester, Atlanta, Buffalo, Charlotte, Chicago, Dallas, Denver, Kansas City, Los Angeles, Manassas, Miami, New York, Phoenix, Saint Louis, Salt Lake City, San Francisco, Seattle, Hanoi. `curl -LSs https://api.nordvpn.com/v1/servers/countries | jq '[.[].cities[].name ] | @csv' | tr -d '\\"'`
* NORDVPN_LOGIN=email (As of 22/12/23, login with token should be preferred.)
* NORDVPN_PASS=pass
* CYBER_SEC,  default off
* KILLERSWITCH,  default on
* DNS: change dns
* PORTS: add ports to allow
* NETWORK: add subnet to allow
* DOCKER_NET: optional,  docker CIDR extracted from container ip if not set.
* IPTABLES_LEGACY: optional, default N for iptables-nft, set to Y to use iptables-legacy.

### Container variables
* DEBUG: (true/false) verbose mode for initial script launch and dante server.
* GENERATE_WIREGUARD_CONF=false #write /etc/wireguard/wg0.conf if true. Will download 56 MB, docker 317 MB of additional disk space will be used. 
* TINYUSER= #optional, enforces authentication over tinyproxy when set with TINYPASS, add authorization with danteuser:${TINYPASS} to socks proxy
* TINYPASS= #optional, enforces authentication over tinyproxy when set with TINYUSER.
* DANTE_LOGOUTPUT=file # stdout or file (>/config/log/dante.log)
* TINYLOGOUTPUT=file # stdout or file (>/config/log/tinyproxy.log)
* LOG_TO_STDOUT= (true/false) # write transmission logs to stdout or transmission.log 


see [haugene's poject](https://github.com/haugene/docker-transmission-openvpn) for transsmission's variables.

### Secrets

Nordvpn, wireguard private key, transmission rpc and tinyproxy credentials may be available throught secrets (/run/secrets/nordvpn_creds, /run/secrets/tiny_creds)
In the setup scripts, secrets values override any env values. Secrets names are fixed values: NORDVPN_CREDS, NORDVPN_PRIVKEY, RPC_CREDS, TINY_CREDS.

file: ./nordvpn_creds #file with username/token in 1st line, passwd in 2nd line.
file: ./tiny_creds #file with username/password in 1st line, passwd in 2nd line.
these credentials can also be set with secrets.
- NORDVPN_CREDS # nordvpn token
- NORDVPN_PRIVKEY # wireguard private key extracted
- RPC_CREDS # login/password for transmission
- TINY_CREDS # username / password for http/socks proxy

```bash
docker run -it --rm --cap-add NET_ADMIN -p 1081:1080 -p 8888:8888 -p 9091:9091
 --device /dev/net/tun -e NORDVPN_LOGIN=<email> -e NORDVPN_PASS='<pass>' -e COUNTRY=Poland
 -e edgd1er/nordlynx-transmission
```

```yaml
version: '3.8'
services:
  transmission:
    image: edgd1er/nordlynx-transmission:latest
    restart: unless-stopped
    ports:
      - "1080:1080"
      - "8888:8888"
      - "9091:9091"
    devices:
      - /dev/net/tun
    sysctls:
        - net.ipv4.conf.all.src_valid_mark=1 # remove need to have privilegied
        - net.ipv4.ip_forward=1
        - net.ipv4.conf.all.rp_filter=2 # Loose Reverse Path: https://access.redhat.com/solutions/53031
        - net.ipv6.conf.all.disable_ipv6=1 # disable ipv6
        - net.ipv6.conf.all.forwarding=1
      #      - net.ipv4.conf.all.rp_filter=2 # Loose Reverse Path: https://access.redhat.com/solutions/53031
    cap_add:
      - NET_ADMIN               # Required
#      - SYS_MODULE              # Required for TECHNOLOGY=NordLynx
    environment:
      - TZ=America/Chicago
      - CONNECT=uk
      - TECHNOLOGY=NordLynx
      - DEBUG=
      - NORDVPN_LOGIN=<email> #Not required if using secrets
      - NORDVPN_PASS=<pass> #Not required if using secrets
      - TRANSMISSION_RPC_USERNAME=<username> # not required if using secrets
      - TRANSMISSION_RPC_PASSWORD=<password> # not required if using secrets
      #- TRANSMISSION_RPC_WHITELIST_ENABLED=true # optional, enables IP whitelist for RPC access
      #- TRANSMISSION_RPC_WHITELIST=172.16.0.* # required if whitelist enabled: specify allowed IP ranges for RPC access
      #- TRANSMISSION_UMASK=0000 # optional, set file permissions mask
      #- TINYUSER: optional, enforces authentication over tinyproxy when set with TINYPASS. set dante username also.
      #- TINYPASS: optional, enforces authentication over tinyproxy when set with TINYUSER. set dante password also.
    secrets:
      - NORDVPN_CREDS
      - NORDVPN_PRIVKEY
      - RPC_CREDS
      - TINY_CREDS

secrets:
    NORDVPN_CREDS:
        file: ./nordvpn_creds # login and password on two separate lines, or token in oneline.
    NORDVPN_PRIVKEY:
        file: ./nordvpn_privkey # wireguard extracted private key
    RPC_CREDS:
        file: ./rpc_creds # login and password on two separate lines for transmission auth.
    TINY_CREDS:
        file: ./tiny_creds # login and password on two separate lines for tinyproxy and dante auth.

```

### Troubleshooting

Enter the container: `docker compose exec transmission bash`

Several aliases are available:
* checkhttp: get external ip through http proxy and vpn. should be the same as `checkip`
* checksocks: get external ip through socks proxy and vpn. should be the same as `checkip`
* checkip: get external ip. should be the same as `getcheck`
* checkvpn: print protection status as seen by nordvpn's client.
* getcheck: get information as ip from nordvpn client.
* getdante: print socks proxy configuration
* gettiny: print http proxy configuration
* getversion: install nordvpn specific version, allow downgrades eg 3.17.0, 3.17.1, ...

From times to times, nordvpn app is bugged, installing another version (downgrade) may be a workaround.


Sometimes docker won't start the container as the file resolv.conf is locked cannot be modified anymore.
This problem occurs since nordvpn'client 3.19.

to restart the container, remove i attribute on host container's resolv.conf
```chattr -i /var/lib/docker/containers/<container-hash>/resolv.conf```
