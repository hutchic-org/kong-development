ARCHITECTURE ?= x86_64
DOCKER_TARGET ?= build
DOCKER_REGISTRY ?= ghcr.io
DOCKER_IMAGE_NAME ?= kong-development
DOCKER_IMAGE_TAG ?= $(DOCKER_TARGET)-$(ARCHITECTURE)-$(OSTYPE)
DOCKER_NAME ?= $(DOCKER_REGISTRY)/$(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG)
DOCKERFILE_NAME ?= Dockerfile.$(DOCKER_TARGET)
DOCKER_RESULT ?= --load
OPERATING_SYSTEM ?= ubuntu
OPERATING_SYSTEM_VERSION ?= 22.04

ifeq ($(OPERATING_SYSTEM),alpine)
	OSTYPE?=linux-musl
else
	OSTYPE?=linux-gnu
endif

ifeq ($(OPERATING_SYSTEM),rhel)
	PACKAGE_TYPE=rpm
else ifeq ($(OPERATING_SYSTEM),amazonlinux)
	PACKAGE_TYPE=rpm
else ifeq ($(OPERATING_SYSTEM),alpine)
	PACKAGE_TYPE=apk
else
	PACKAGE_TYPE=deb
endif

ifeq ($(ARCHITECTURE),aarch64)
	DOCKER_ARCHITECTURE=arm64
else
	DOCKER_ARCHITECTURE=amd64
endif

clean:
	-rm -rf build
	-rm -rf package
	-docker rmi $(DOCKER_REGISTRY)/$(DOCKER_IMAGE_NAME):$(DOCKER_ARCHITECTURE)-$(OPERATING_SYSTEM)-$(OPERATING_SYSTEM_VERSION)

clean/submodules:
	-git reset --hard
	-git submodule foreach --recursive git reset --hard
	-git submodule update --init --recursive

build/docker:
	-git submodule update --init --recursive
	-git submodule status
	docker inspect --format='{{.Config.Image}}' $(DOCKER_NAME) || \
	docker buildx build \
		--platform=linux/$(DOCKER_ARCHITECTURE) \
		--build-arg DOCKER_REGISTRY=$(DOCKER_REGISTRY) \
		--build-arg DOCKER_IMAGE_NAME=$(DOCKER_IMAGE_NAME) \
		--build-arg DOCKER_IMAGE_TAG=$(DOCKER_IMAGE_TAG) \
		--build-arg OPERATING_SYSTEM=$(OPERATING_SYSTEM) \
		--build-arg OPERATING_SYSTEM_VERSION=$(OPERATING_SYSTEM_VERSION) \
		--build-arg ARCHITECTURE=$(ARCHITECTURE) \
		--build-arg PACKAGE_TYPE=$(PACKAGE_TYPE) \
		--build-arg OSTYPE=$(OSTYPE) \
		--target=$(DOCKER_TARGET) \
		-f $(DOCKERFILE_NAME) \
		-t $(DOCKER_NAME) \
		$(DOCKER_RESULT) .

build:
	$(MAKE) DOCKER_TARGET=build DOCKER_RESULT="-o build" build/docker

package: build
	$(MAKE) DOCKER_TARGET=package DOCKER_RESULT="-o package" build/docker
	ls package/*

docker: package
ifeq ($(OPERATING_SYSTEM),alpine)
	cp package/*.$(PACKAGE_TYPE)* docker-kong/kong.apk.tar.gz
else
	cp package/*.$(PACKAGE_TYPE) docker-kong/kong.$(PACKAGE_TYPE)
endif
ifneq ($(PACKAGE_TYPE),rpm)
	sed -i.bak "s|^FROM .*|FROM --platform=linux/$(ARCHITECTURE) ${OPERATING_SYSTEM}:${OPERATING_SYSTEM_VERSION}|" docker-kong/Dockerfile.$(PACKAGE_TYPE)
endif
	cd docker-kong && \
	docker buildx build \
		--platform=linux/$(DOCKER_ARCHITECTURE) \
		--build-arg ASSET=local \
		-f Dockerfile.$(PACKAGE_TYPE) \
		-t $(DOCKER_REGISTRY)/$(DOCKER_IMAGE_NAME):$(DOCKER_ARCHITECTURE)-$(OPERATING_SYSTEM)-$(OPERATING_SYSTEM_VERSION) .
	$(MAKE) clean/submodule
