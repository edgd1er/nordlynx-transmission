.PHONY: help lint build

# Use bash for inline if-statements in arch_patch target
SHELL:=bash
NVPNVER:= $(shell grep -oE 'changelog.: .+' README.md | cut -f2 -d' ')

# Enable BuildKit for Docker build
export DOCKER_BUILDKIT:=1
export NORDVPN_PACKAGE:=https://repo.nordvpn.com/deb/nordvpn/debian/dists/stable/main/binary-amd64/Packages
APTCACHER:="192.168.53.208"
#APTCACHER:="192.168.43.61"
LIBEVENT_VERSION:= $(shell grep -oP '(?<= LIBEVENT_VERSION: ).+' .github/workflows/check_version.yml | tr -d '"')
TBT_V4:=$(shell grep -oP '(?<= TBT_VERSION: ).+' .github/workflows/check_version.yml | tr -d '"' )
TBT_V3:=$(shell grep -oP '(?<=#TBT_VERSION: ).+' .github/workflows/check_version.yml | tr -d '"' )
TWCV:=$(shell grep -oP '(?<=TWCV: ).+' .github/workflows/check_version.yml )
TICV:=$(shell grep -oP '(?<=TICV: ).+' .github/workflows/check_version.yml )

# https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
help: ## generate help list
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

lint: ## lint both dockerfile
	@echo "lint dockerfile ..."
	docker run -i --rm hadolint/hadolint < Dockerfile

build: ## build image
	@echo "build tbt v4 image with nordvpn client..."
	#docker-compose build
	docker buildx build --build-arg aptcacher=${APTCACHER} --build-arg NORDVPN_INSTALL=1 --build-arg VERSION=${NVPNVER} --build-arg NORDVPNCLIENT_INSTALLED=1 --build-arg TBT_VERSION="${TBT_V4}" --build-arg TWCV="${TWCV}" --build-arg TICV="${TICV}" -f ./Dockerfile -t edgd1er/nordlynx-transmission:latest .

builddev: ##build dev image
	@echo "Build dev image"
	docker buildx build --build-arg aptcacher=${APTCACHER} --build-arg NORDVPN_INSTALL=1 --build-arg VERSION=${NVPNVER} --build-arg NORDVPNCLIENT_INSTALLED=1 --build-arg TBT_VERSION="dev" --build-arg TWCV="${TWCV}" --build-arg TICV="${TICV}" -f ./Dockerfile -t edgd1er/nordlynx-transmission:dev .

build3: ##build dev image
	@echo "Build transmission v3"
	docker buildx build --build-arg aptcacher=${APTCACHER} --build-arg NORDVPN_INSTALL=1 --build-arg VERSION=${NVPNVER} --build-arg NORDVPNCLIENT_INSTALLED=1 --build-arg TBT_VERSION="${TBT_V3}" --build-arg TWCV="${TWCV}" --build-arg TICV="${TICV}" -f ./Dockerfile -t edgd1er/nordlynx-transmission:v3 .

build4: ##build dev image
	@echo "Build transmission v4 beta image"
	docker buildx build --build-arg aptcacher=${APTCACHER} --build-arg NORDVPN_INSTALL=1 --build-arg VERSION=${NVPNVER} --build-arg NORDVPNCLIENT_INSTALLED=1 --build-arg TBT_VERSION="${TBT_V4}" --build-arg TWCV="${TWCV}" --build-arg TICV="${TICV}" -f ./Dockerfile -t edgd1er/nordlynx-transmission:v4 .

buildnoclient: ## build image without nordvpn client
	@echo "build image without nordvpn client"
	docker buildx build --build-arg aptcacher=${APTCACHER} --build-arg NORDVPN_INSTALL=0 --build-arg TWCV="${TWCV}" --build-arg TICV="${TICV}" -f ./Dockerfile -t edgd1er/nordguard-transmission  .

ver:	## check versions
	@lversion=$$( grep -oP "(?<=changelog\): )[^ ]+" README.md ) ;\
	rversion=$$(curl -qLs "${NORDVPN_PACKAGE}" | grep -oP "(?<=Version: )(.*)" | sort -t. -n -k1,1 -k2,2 -k3,3 | tail -1); \
	echo "local  version: $${lversion}" ;\
	echo "remote version: $${rversion}" ;\
	if [[ $${lversion} != $${rversion} ]]; then sed -i -E "s/ VERSION:.*/ VERSION: $${rversion}/" docker-compose.yml ; \
	sed -i -E "s/ VERSION=.*/ VERSION=$${rversion}/" Dockerfile ; fi ; \
	grep -E ' VERSION[:=].+' Dockerfile docker-compose.yml ; \
	echo "transmission version: ${TBT_V4}" ; \
	sed -i -E "s/ARG TBT_VERSION=.*/ARG TBT_VERSION=${TBT_V4}/" Dockerfile;\
	echo "transmission web cntrol version: ${TWCV}" ; \
	sed -i -E "s/ verWC=.*/ verWC=${TWCV}/" Dockerfile;\
	echo "transmissionic version: ${TICV}" ; \
	sed -i -E "s/ verTC=.*/ verTC=${TICV}/" Dockerfile; \
	sed -i -E "s/ nversion: \".*/ nversion: \"$${rversion}\"/" .github/workflows/build3_4.yml; \
	sed -i -E "s/$${lversion}/$${rversion}/g" README.md;

run:
	@echo "run container"
	docker-compose up
