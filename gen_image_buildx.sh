#!/usr/bin/env bash

#testml multi arch build using buildx

#Variables
localDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
DKRFILE=${localDir}/Dockerfile
ARCHI=$(dpkg --print-architecture)
IMAGE=nordlynx-transmission
DUSER=edgd1er
[[ "${ARCHI}" != "armhf" ]] && isMultiArch=$(docker buildx ls | grep -c amd-arm)
aptCacher=$(ip route get 1 | awk '{print $7}')
PROGRESS=plain #text auto plain
PROGRESS=auto  #text auto plain
CACHE=""
WHERE="--load"
#TBT_VERSION=3.00
TBT_VERSION=4.0.5
#TBT_VERSION=dev # 4.1.x

#exit on error
set -e -u -o pipefail

#fonctions
enableMultiArch() {
  docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
  [[ 0 -ne $(docker buildx ls | grep -c amd-arm) ]] && docker buildx rm amd-arm || true
  docker buildx create --use --name amd-arm --driver=docker-container --driver-opt image=moby/buildkit:master --platform=linux/amd64,linux/arm64,linux/386,linux/arm/v7,linux/arm/v6 #--attest type=provenance,mode=min
  docker buildx inspect --bootstrap amd-arm
}

#Main
[[ "$HOSTNAME" != phoebe ]] && aptCacher=""
[[ ! -f ${DKRFILE} ]] && echo -e "\nError, Dockerfile is not found\n" && exit 1

WHERE="--push"
#CACHE="--no-cache"

NAME=${DUSER}/${IMAGE}
case "${TBT_VERSION}" in
  3.00)
    TAG="${DUSER}/${IMAGE}:v3"
    ;;
  dev)
    TAG="${DUSER}/${IMAGE}:dev"
    ;;
  4.0.5)
    TAG="${DUSER}/${IMAGE}:v4"
    ;;
  4.1.0)
    TAG="${DUSER}/${IMAGE}:dev"
    ;;
esac

#default build for rpi4
PTF=linux/arm64
#build amd64 if
if [ "${ARCHI}" == "amd64" ]; then
  PTF=linux/amd64
fi
# c= container, p=package
while getopts "ah?vpc" opt; do
  case "$opt" in
  v)
    echo verbose mode
    set -x
    ;;
  a)
    PTF=linux/arm/v7
    #build multi arch images
    if [ "${ARCHI}" == "amd64" ]; then
      PTF=linux/amd64
      # load is not compatible with multi arch build
      if [[ $WHERE == "--push" ]]; then
        PTF+=,linux/arm64/v8,linux/arm/v7,linux/arm/v6
        #enable multi arch build framework
        if [ $isMultiArch -eq 0 ]; then
          enableMultiArch
        fi
      fi
    fi
    #no nodejs for v6
    if [[ ${TBT_VERSION} == "dev" ]]; then
      PTFARG=linux/amd64,linux/arm64/v8,linux/arm/v7
    else
      #PTFARG=linux/amd64,linux/arm64/v8,linux/arm/v7,linux/arm/v6
      PTFARG=linux/amd64,linux/arm64/v8,linux/arm/v7
    fi
    ;;
  p)
    echo "generating debian package for ${PTF} in ${TBT_VERSION} version"
    #get transmission source if not present
    if [[ ! -f transmission-${TBT_VERSION}.tar.xz ]] && [[ "dev" != ${TBT_VERSION} ]]; then
      wget -O transmission-${TBT_VERSION}.tar.xz https://github.com/transmission/transmission/releases/download/${TBT_VERSION}/transmission-${TBT_VERSION}.tar.xz
    fi
    date
    docker buildx build --builder=amd-arm --platform ${PTF} -f ${DKRFILE}.deb --build-arg TBT_VERSION=$TBT_VERSION \
      $CACHE --progress $PROGRESS --build-arg aptCacher=$aptCacher --provenance false -o out .
    find out/ -mindepth 2 -type f -print -exec mv {} out/ \;
    date
    ;;
  c)
    #enable multi arch build framework
    echo -e "building $TAG, name $NAME using cache $CACHE and apt cache $aptCacher for ${PTF} in ${TBT_VERSION}"
    #docker buildx use amd-arm
    docker buildx build --builder=amd-arm ${WHERE} --platform ${PTF} -f ${DKRFILE} --build-arg TBT_VERSION=$TBT_VERSION \
      $CACHE --progress $PROGRESS --build-arg aptCacher=$aptCacher --provenance false -t $TAG .
    #done
    #docker manifest inspect $TAG | grep -E "architecture|variant"
    docker manifest inspect $TAG | jq -r '.manifests[].platform|[.architecture,.os,.variant]| @tsv'
    ;;
  h | \?)
    echo -e "script:\t${0}\n-a\tbuild for all plateforms\n-c\tBuild image\n-p\tBuild packages"
    ;;
  *) ;;
  esac
done
