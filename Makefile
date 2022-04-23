.PHONY: help lint build

# Use bash for inline if-statements in arch_patch target
SHELL:=bash

# Enable BuildKit for Docker build
export DOCKER_BUILDKIT:=1


# https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
help:

lint: ## stop all containers
	@echo "lint dockerfile ..."
	docker run -i --rm hadolint/hadolint < Dockerfile

build: ## build image
	@echo "build image with nordvpn client..."
	docker-compose build

buildnoclient: ## build image without nordvpn client
	@echo "build image without nordvpn client"
	docker buildx build --build-arg aptcacher=192.168.53.208 --build-arg NORDVPN_INSTALL=0 -f ./Dockerfile -t edgd1er/nordguard-transmission  .

run:
	@echo "run container"
	docker-compose up