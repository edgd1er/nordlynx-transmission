#!/usr/bin/env bash

#testml multi arch build using buildx

#Variables
localDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
DKRFILE=${localDir}/Dockerfile
ARCHI=$(dpkg --print-architecture)
IMAGE=nordvpn-proxy
DUSER=edgd1er
[[ $("${ARCHI}" != "armhf") ]] && isMultiArch=$(docker buildx ls | grep -c arm)
aptCacher=$(ip route get 1 | awk '{print $7}')
PROGRESS=plain #text auto plain
PROGRESS=auto  #text auto plain
CACHE=""
WHERE="--load"

#exit on error
set -xe

#fonctions
enableMultiArch() {
  docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
  docker buildx rm amd-arm
  docker buildx create --use --name amd-arm --driver-opt image=moby/buildkit:master --platform=linux/amd64,linux/arm64,linux/386,linux/arm/v7,linux/arm/v6
  docker buildx inspect --bootstrap amd-arm
}

#Main
[[ "$HOSTNAME" != phoebe ]] && aptCacher=""
[[ ! -f ${DKRFILE} ]] && echo -e "\nError, Dockerfile is not found\n" && exit 1

#WHERE="--push"
#CACHE="--no-cache"

NAME=${DUSER}/${IMAGE}
TAG="${DUSER}/${IMAGE}:latest"

PTF=linux/arm/v7
#build multi arch images
if [ "${ARCHI}" == "amd64" ]; then
  #PTF=linux/arm/v7,linux/arm/v6
  # load is not compatible with multi arch build
  if [[ $WHERE == "--push" ]]; then
    PTF+=,linux/amd64,linux/arm64/v8,linux/arm/v7,linux/arm/v6
    #enable multi arch build framework
    if [ $isMultiArch -eq 0 ]; then
      enableMultiArch
    fi
  fi
fi

#PTF=linux/amd64
#PTF=linux/arm/v7
PTF=linux/amd64
#enable multi arch build framework
echo -e "\nbuilding $TAG, name $NAME using cache $CACHE and apt cache $aptCacher \n\n"

#Fix push errors
#docker buildx create --driver-opt image=moby/buildkit:master

docker buildx build ${WHERE} --platform ${PTF} -f ${DKRFILE}  $CACHE --progress $PROGRESS \
  --build-arg aptCacher=$aptCacher -t $TAG .

#docker manifest inspect $TAG | grep -E "architecture|variant"
