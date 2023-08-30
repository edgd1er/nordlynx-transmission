.PHONY: help lint build

# Use bash for inline if-statements in arch_patch target
SHELL:=bash
NEWVERSION := $(shell grep -oE 'changelog.: .+' README.md | cut -f2 -d' ')

# Enable BuildKit for Docker build
export DOCKER_BUILDKIT:=1
NVPNVER:="3.16.5"
APTCACHER:="192.168.53.208"
#APTCACHER:="192.168.43.61"

# https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
help: ## generate help list
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

lint: ## lint both dockerfile
	@echo "lint dockerfile ..."
	docker run -i --rm hadolint/hadolint < Dockerfile

build: ## build image
	@echo "build image with nordvpn client..."
	#docker-compose build
	docker buildx build --build-arg aptcacher=${APTCACHER} --build-arg NORDVPN_INSTALL=1 --build-arg VERSION=${NVPNVER} --build-arg NORDVPNCLIENT_INSTALLED=1 --build-arg TBT_VERSION="4.0.4" -f ./Dockerfile -t edgd1er/nordlynx-transmission:latest .

builddev: ##build dev image
	@echo "Build dev image"
	docker buildx build --build-arg aptcacher=${APTCACHER} --build-arg NORDVPN_INSTALL=1 --build-arg VERSION=${NVPNVER} --build-arg NORDVPNCLIENT_INSTALLED=1 --build-arg TBT_VERSION="dev" -f ./Dockerfile -t edgd1er/nordlynx-transmission:dev .

build3: ##build dev image
	@echo "Build transmission v3"
	docker buildx build --build-arg aptcacher=${APTCACHER} --build-arg NORDVPN_INSTALL=1 --build-arg VERSION=${NVPNVER} --build-arg NORDVPNCLIENT_INSTALLED=1 --build-arg TBT_VERSION="3.00" -f ./Dockerfile -t edgd1er/nordlynx-transmission:v3 .

build4: ##build dev image
	@echo "Build transmission v4 beta image"
	docker buildx build --build-arg aptcacher=${APTCACHER} --build-arg NORDVPN_INSTALL=1 --build-arg VERSION=${NVPNVER} --build-arg NORDVPNCLIENT_INSTALLED=1 --build-arg TBT_VERSION="4.0.4" -f ./Dockerfile -t edgd1er/nordlynx-transmission:v4 .

buildnoclient: ## build image without nordvpn client
	@echo "build image without nordvpn client"
	docker buildx build --build-arg aptcacher=${APTCACHER} --build-arg NORDVPN_INSTALL=0 -f ./Dockerfile -t edgd1er/nordguard-transmission  .

ver:	## check versions
	#    && wget --no-cache -qO- "$(wget --no-cache -qO- https://api.github.com/repos/ronggang/transmission-web-control/releases/latest | jq --raw-output '.tarball_url')" | tar -C /opt/transmission-ui/transmission-web-control/ --strip-components=2 -xz \
	./versions.sh
	@echo "local  version: "$$(grep -oP "(?<=changelog\): )[^ ]+" README.md)
	@echo "remote version: "$$(curl -Ls "${NORDVPN_PACKAGE}" | grep -oP "(?<=Version: )(.*)" | sort -t. -n -k1,1 -k2,2 -k3,3 | tail -1)
	@echo "NEWVERSION: $(NEWVERSION)"
	@sed -i -E "s/ VERSION:.+/ VERSION: ${NEWVERSION}/" docker-compose.yml
	@sed -i -E "s/ VERSION=.+/ VERSION=${NEWVERSION}/" Dockerfile
	@grep -E ' VERSION[:=].+' Dockerfile docker-compose.yml

run:
	@echo "run container"
	docker-compose up
