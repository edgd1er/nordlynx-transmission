#!/usr/bin/env bash

set -e -o pipefail
#vars
GITHUB_TOKEN=
LIBEVENT_VERSION=$(grep -oP "(?<=LIBEVENT_VERSION: )[^$]+" .github/workflows/check_version.yml)
TRANSMISSION_VERSION=$(grep -oP "(?<=TRANSMISSION_VERSION: )[^$]+" .github/workflows/check_version.yml)
TRANSMISSION_DEV_VERSION=$(grep -oP "(?<=TRANSMISSION_DEV_VERSION: )[^$]+" .github/workflows/check_version.yml)
NORDVPN_VERSION=$(grep -oP "(?<=NORDVPN_VERSION: )[^$]+" .github/workflows/check_version.yml)
TWCV=$(grep -oP "(?<=TWCV: )v[^$]+" .github/workflows/check_version.yml)
TICV=$(grep -oP "(?<=TICV: )v[^$]+" .github/workflows/check_version.yml)

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

[[ -v GITHUB_TOKEN ]] && HEADERTOKEN="-H \"Authorization: Bearer \${GITHUB_TOKEN}\"" && HEADERTOKEN=""

#Functions
checkNordvpn() {
  ver=$(curl -s "https://repo.nordvpn.com/deb/nordvpn/debian/dists/stable/main/binary-amd64/Packages" | grep -oP "(?<=Version: )(.*)" | sort -t. -n -k1,1 -k2,2 -k3,3 | tail -1)
  [[ ${NORDVPN_VERSION} == ${ver} ]] && coul=${GREEN} || coul=${RED}
  echo -e ${coul} "Nordvpn current: ${NORDVPN_VERSION}, latest: ${ver}"
}

checkLibEvent() {
  ver=$(curl -s ${HEADERTOKEN} "https://api.github.com/repos/libevent/libevent/releases/latest" | jq -r .tag_name )
  [[ release-${LIBEVENT_VERSION} == ${ver} ]] && coul=${GREEN} || coul=${RED}
  echo -e ${coul} "libevent build version: ${LIBEVENT_VERSION}, latest github libevent version: ${ver}"
}

checkTbt(){
  ver=$(curl -s ${HEADERTOKEN} "https://api.github.com/repos/transmission/transmission/releases/latest" | jq -r .tag_name )
  [[ ${TRANSMISSION_VERSION} == ${ver} ]] && coul=${GREEN} || coul=${RED}
  echo -e ${coul} "transmission build version: ${TRANSMISSION_VERSION}, latest github transmission version: ${ver}"
  devver=$(curl -s "https://raw.githubusercontent.com/transmission/transmission/main/CMakeLists.txt" | grep -oP "(?<=TR_VERSION_(MAJOR|MINOR|PATCH) \")[^\"]+" | tr '\n' '.' | grep -oP "[0-9]+\.[0-9]+\.[0-9]+")
  [[ ${TRANSMISSION_DEV_VERSION} == ${devver} ]] && coul=${GREEN} || coul=${RED}
  echo -e ${coul} "transmission dev build version: ${TRANSMISSION_DEV_VERSION}, latest github transmission dev version: ${devver}"
}

checkUIs(){
  ver=$(curl -s ${HEADERTOKEN} "https://api.github.com/repos/transmission-web-control/transmission-web-control/releases/latest" | jq -r .tag_name)
  [[ ${TWCV} == ${ver} ]] && coul=${GREEN} || coul=${RED}
  echo -e ${coul} "transmission-web-control version: ${TWCV}, latest github transmission version: ${ver}"
  ver=$(curl -s ${HEADERTOKEN} "https://api.github.com/repos/6c65726f79/Transmissionic/releases/latest" | jq -r .tag_name)
  [[ ${TICV} == ${ver} ]] && coul=${GREEN} || coul=${RED}
  echo -e ${coul} "Transmissionic version: ${TICV}, latest github transmission version: ${ver}"
}

#Main
checkNordvpn
checkLibEvent
checkTbt
checkUIs
