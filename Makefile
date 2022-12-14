ARCHITECTURE ?= x86_64
OSTYPE ?= linux-gnu
DOCKER_TARGET ?= build
DOCKER_REGISTRY ?= ghcr.io
DOCKER_IMAGE_NAME ?= kong-development
DOCKER_IMAGE_TAG ?= $(DOCKER_TARGET)-$(ARCHITECTURE)-$(OSTYPE)
DOCKER_NAME ?= $(DOCKER_REGISTRY)/$(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG)
DOCKERFILE_NAME ?= Dockerfile.$(DOCKER_TARGET)
DOCKER_RESULT ?= --load
OPERATING_SYSTEM ?= ubuntu
OPERATING_SYSTEM_VERSION ?= 22.04

clean:
	-rm -rf build
	-rm -rf package

clean/submodules:
	-git reset --hard
	-git submodule foreach --recursive git reset --hard
	-git submodule update --init --recursive

docker:
	-git submodule update --init --recursive
	-git submodule status
	docker inspect --format='{{.Config.Image}}' $(DOCKER_NAME) || \
	docker buildx build \
		--build-arg DOCKER_REGISTRY=$(DOCKER_REGISTRY) \
		--build-arg DOCKER_IMAGE_NAME=$(DOCKER_IMAGE_NAME) \
		--build-arg DOCKER_IMAGE_TAG=$(DOCKER_IMAGE_TAG) \
		--build-arg OPERATING_SYSTEM=$(OPERATING_SYSTEM) \
		--build-arg OPERATING_SYSTEM_VERSION=$(OPERATING_SYSTEM_VERSION) \
		--build-arg ARCHITECTURE=$(ARCHITECTURE) \
		--build-arg OSTYPE=$(OSTYPE) \
		--target=$(DOCKER_TARGET) \
		-f $(DOCKERFILE_NAME) \
		-t $(DOCKER_NAME) \
		$(DOCKER_RESULT) .

build:
	$(MAKE) DOCKER_TARGET=build DOCKER_RESULT="-o build" docker

package: build
	$(MAKE) DOCKER_TARGET=package DOCKER_RESULT="-o package" docker
	ls package/*
