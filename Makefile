.PHONY: help lint build

# Use bash for inline if-statements in arch_patch target
SHELL:=bash

# Enable BuildKit for Docker build
export DOCKER_BUILDKIT:=1
NVPNVER:="3.15.2"
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
	docker buildx build --build-arg aptcacher=${APTCACHER} --build-arg NORDVPN_INSTALL=1 --build-arg VERSION=${NVPNVER} --build-arg NORDVPNCLIENT_INSTALLED=1 --build-arg TBT_VERSION="main" -f ./Dockerfile -t edgd1er/nordlynx-transmission:latest  .

builddev: ##build dev image
	@echo "Build dev image"
	docker buildx build --build-arg aptcacher=${APTCACHER} --build-arg NORDVPN_INSTALL=1 --build-arg VERSION=${NVPNVER} --build-arg NORDVPNCLIENT_INSTALLED=1 --build-arg TBT_VERSION="dev" -f ./Dockerfile -t edgd1er/nordlynx-transmission:dev  .

build4: ##build dev image
	@echo "Build transmission v4 beta image"
	docker buildx build --build-arg aptcacher=${APTCACHER} --build-arg NORDVPN_INSTALL=1 --build-arg VERSION=${NVPNVER} --build-arg NORDVPNCLIENT_INSTALLED=1 --build-arg TBT_VERSION="tbt_v4" -f ./Dockerfile -t edgd1er/nordlynx-transmission:v4  .

buildnoclient: ## build image without nordvpn client
	@echo "build image without nordvpn client"
	docker buildx build --build-arg aptcacher=${APTCACHER} --build-arg NORDVPN_INSTALL=0 -f ./Dockerfile -t edgd1er/nordguard-transmission  .

run:
	@echo "run container"
	docker-compose up