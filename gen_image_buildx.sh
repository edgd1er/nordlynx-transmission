#!/usr/bin/env bash

#testml multi arch build using buildx

#Variables
localDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
DKRFILE=${localDir}/Dockerfile
ARCHI=$(dpkg --print-architecture)
IMAGE=nordvpn-proxy
DUSER=edgd1er
[[ "${ARCHI}" != "armhf" ]] && isMultiArch=$(docker buildx ls | grep -c arm)
aptCacher=$(ip route get 1 | awk '{print $7}')
PROGRESS=plain #text auto plain
PROGRESS=auto  #text auto plain
CACHE=""
WHERE="--load"
#TBT_VERSION=4.0.3
TBT_VERSION=dev

#exit on error
set -e -u -o pipefail

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

WHERE="--push"
#CACHE="--no-cache"

NAME=${DUSER}/${IMAGE}
TAG="${DUSER}/${IMAGE}:latest"

PTF=linux/arm/v7
#build multi arch images
if [ "${ARCHI}" == "amd64" ]; then
  PTF=linux/amd64
  # load is not compatible with multi arch build
  if [[ $WHERE == "--push" ]]; then
    PTF+=,linux/amd64,linux/arm64/v8,linux/arm/v7,linux/arm/v6
    #enable multi arch build framework
    if [ $isMultiArch -eq 0 ]; then
      enableMultiArch
    fi
  fi
fi

# c= container, p=package
todo=${1:-c}
todo=${todo#-}
case ${todo} in
  a)
    #no nodejs for v6
    if [[ ${TBT_VERSION} == "dev" ]]; then
      PTFARG=linux/amd64,linux/arm64/v8,linux/arm/v7
    else
      PTFARG=linux/amd64,linux/arm64/v8,linux/arm/v7,linux/arm/v6
    fi
    ;;
  p)
    if [[ ${TBT_VERSION} == "dev" ]]; then
          PTF=${PTFARG:-'linux/amd64'}
    fi
    echo "generating debian package for ${PTF} in ${TBT_VERSION} version"
    docker buildx build --platform ${PTF} -f ${DKRFILE}.deb --build-arg TBT_VERSION=$TBT_VERSION \
  $CACHE --progress $PROGRESS --build-arg aptCacher=$aptCacher -o out .
  find out/ -mindepth 2 -type f -print -exec mv {} out/ \;
  ;;
  c)
    #enable multi arch build framework
    echo -e "building $TAG, name $NAME using cache $CACHE and apt cache $aptCacher for ${PTF} in ${TBT_VERSION}"
    docker buildx build ${WHERE} --platform ${PTF} -f ${DKRFILE} --build-arg TBT_VERSION=$TBT_VERSION \
  $CACHE --progress $PROGRESS --build-arg aptCacher=$aptCacher -t $TAG .
  #done
    docker manifest inspect $TAG | grep -E "architecture|variant"
  ;;
  h)
    echo -e "script:\t${0}\n-a\tbuild for all plateforms\n-c\tBuild image\n-p\tBuild packages"
    ;;
  *)
    ;;
esac