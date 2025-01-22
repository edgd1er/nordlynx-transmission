#!/usr/bin/env bash

set -e -o pipefail
#vars
GITHUB_TOKEN=
LIBEVENT_VERSION=$(grep -oP "(?<=LIBEVENT_VERSION: )[^$]+" .github/workflows/check_version.yml)
TRANSMISSION_VERSION=$(grep -oP "(?<=TBT_VERSION: )[^$]+" .github/workflows/check_version.yml)
TRANSMISSION_DEV_VERSION=$(grep -oP "(?<=TBT_DEV_VERSION: )[^$]+" .github/workflows/check_version.yml)
NORDVPN_VERSION=$(grep -oP "(?<=changelog\): )[^ ]+" README.md | tr -d ' ')
TWCV=$(grep -oP "(?<=TWCV: )[^$]+" .github/workflows/check_version.yml)
TICV=$(grep -oP "(?<=TICV: )[^$]+" .github/workflows/check_version.yml)

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

[[ -n ${GITHUB_TOKEN} ]] && HEADERTOKEN=-H\ \'Authorization:\ Bearer\ ${GITHUB_TOKEN}\' || HEADERTOKEN=""

#Functions
checkNordvpn() {
  ver=$(curl -s "https://repo.nordvpn.com/deb/nordvpn/debian/dists/stable/main/binary-amd64/Packages" | grep -oP "(?<=Version: )(.*)" | sort -t. -n -k1,1 -k2,2 -k3,3 | tail -1)
  [[ ${NORDVPN_VERSION} == ${ver} ]] && coul=${GREEN} || coul=${RED}
  echo -e "Nordvpn current: ${coul}${NORDVPN_VERSION}${NC}, latest: ${coul}${ver}${NC}"
}

checkLibEvent() {
  ver=$(curl -s ${HEADERTOKEN} "https://api.github.com/repos/libevent/libevent/releases/latest" | jq -r .tag_name)
  [[ release-${LIBEVENT_VERSION} == ${ver} ]] && coul=${GREEN} || coul=${RED}
  echo -e "libevent build version: ${coul}${LIBEVENT_VERSION}${NC}, latest github libevent version: ${coul}${ver}${NC}"
}

checkTbt() {
  ver=$(curl -s ${HEADERTOKEN} "https://api.github.com/repos/transmission/transmission/releases/latest" | jq -r .tag_name)
  [[ ${TRANSMISSION_VERSION} == ${ver} ]] && coul=${GREEN} || coul=${RED}
  [[ ! -f ./transmission-${ver}.tar.xz ]] && curl -o transmission-${ver}.tar.xz -L https://github.com/transmission/transmission/releases/download/${ver}/transmission-${ver}.tar.xz
  echo -e "transmission build version: ${coul}${TRANSMISSION_VERSION}${NC}, latest github transmission version: ${coul}${ver}${NC}"
  devver=$(curl -s "https://raw.githubusercontent.com/transmission/transmission/main/CMakeLists.txt" | grep -oP "(?<=TR_VERSION_(MAJOR|MINOR|PATCH) \")[^\"]+" | tr '\n' '.' | grep -oP "[0-9]+\.[0-9]+\.[0-9]+")
  [[ ${TRANSMISSION_DEV_VERSION} == ${devver} ]] && coul=${GREEN} || coul=${RED}
  echo -e "transmission dev build version: ${coul}${TRANSMISSION_DEV_VERSION}${NC}, latest github transmission dev version: ${coul}${devver}${NC}"
}

checkUIs() {
  #ver=$(curl -s ${HEADERTOKEN} "https://api.github.com/repos/transmission-web-control/transmission-web-control/releases/latest" | jq -r .tag_name)
  ver=$(curl -s ${HEADERTOKEN} "https://api.github.com/repos/ronggang/transmission-web-control/releases/latest" | jq -r .tag_name)
  [[ v${TWCV} == ${ver} ]] && coul=${GREEN} || coul=${RED}
  echo -e "transmission-web-control version: ${coul}v${TWCV}${coul}${NC}, latest github transmission version: ${coul}${ver}${NC}"
  ver=$(curl -s ${HEADERTOKEN} "https://api.github.com/repos/6c65726f79/Transmissionic/releases/latest" | jq -r .tag_name)
  [[ v${TICV} == ${ver} ]] && coul=${GREEN} || coul=${RED}
  echo -e  "Transmissionic version: ${coul}v${TICV}${NC}, latest github transmission version: ${coul}${ver}${NC}"
}

#Main
checkNordvpn
checkLibEvent
checkTbt
checkUIs
