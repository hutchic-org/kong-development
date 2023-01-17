ARCHITECTURE ?= x86_64
DOCKER_TARGET ?= build
DOCKER_REGISTRY ?= ghcr.io
DOCKER_IMAGE_NAME ?= hutchic-org/kong-development
DOCKER_IMAGE_TAG ?= $(DOCKER_TARGET)-$(ARCHITECTURE)-$(OSTYPE)
DOCKER_NAME ?= $(DOCKER_REGISTRY)/$(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG)
DOCKERFILE_NAME ?= Dockerfile.$(DOCKER_TARGET)
DOCKER_RESULT ?= --load
OPERATING_SYSTEM ?= ubuntu
OPERATING_SYSTEM_VERSION ?= 22.04
KONG_VERSION ?= `./grep-kong-version.sh`
USE_TTY := $(shell test -t 1 && USE_TTY="-T")

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

DOCKER_OFFICIAL_TAG ?= $(DOCKER_ARCHITECTURE)-$(OPERATING_SYSTEM)-$(OPERATING_SYSTEM_VERSION)
DOCKER_OFFICIAL_IMAGE_NAME ?= $(DOCKER_REGISTRY)/$(DOCKER_IMAGE_NAME):$(DOCKER_OFFICIAL_TAG)

clean: development/clean
	-rm -rf build
	-rm -rf package
	-docker rmi $(DOCKER_OFFICIAL_IMAGE_NAME)
	-docker rmi kong-build
	-docker rmi kong-dev
	-docker kill docker kill package-validation-tests
	-docker kill systemd

clean/submodules:
	-git submodule foreach --recursive git reset --hard
	-git submodule update --init --recursive
	-git submodule status

build/docker:
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
		--build-arg KONG_VERSION=$(KONG_VERSION) \
		--build-arg OSTYPE=$(OSTYPE) \
		--target=$(DOCKER_TARGET) \
		-f $(DOCKERFILE_NAME) \
		-t $(DOCKER_NAME) \
		$(DOCKER_RESULT) .

build:
	$(MAKE) DOCKER_TARGET=build DOCKER_RESULT="-o build" build/docker

package/test: package
	PACKAGE_TYPE=$(PACKAGE_TYPE) \
	DOCKER_ARCHITECTURE=$(DOCKER_ARCHITECTURE) \
	/bin/bash ./test-package.sh

package:
	$(MAKE) build
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
		--load \
		--platform=linux/$(DOCKER_ARCHITECTURE) \
		--build-arg ASSET=local \
		-f Dockerfile.$(PACKAGE_TYPE) \
		-t $(DOCKER_OFFICIAL_IMAGE_NAME) . && \
	git restore .

development/clean:
	-docker-compose kill
	-docker-compose rm -f

development/build:
	$(MAKE) DOCKER_NAME=kong-build DOCKERFILE_NAME=Dockerfile.build DOCKER_TARGET=building build/docker && \
	docker inspect --format='{{.Config.Image}}' kong-dev || \
	docker build -t kong-dev -f Dockerfile.dev .

development/run: development/build
	docker-compose up -d
	bash -c 'healthy=$$(docker-compose ps | grep healthy | wc -l); while [[ "$$(( $$healthy ))" != "3" ]]; do docker-compose ps && sleep 5; done'
	docker-compose logs

development: development/run
	docker-compose exec kong /bin/bash

kong/test/all: kong/test/integration kong/test/dbless kong/test/plugins kong/test/unit

kong/test/run: development/run
	docker exec -i${USE_TTY} kong /root/test-kong.sh

kong/test/integration:
	$(MAKE) TEST_SUITE=integration kong/test/run

kong/test/dbless:
	$(MAKE) TEST_SUITE=dbless TEST_DATABASE=off kong/test/run

kong/test/plugins:
	$(MAKE) TEST_SUITE=plugins kong/test/run

kong/test/pdk:
	$(MAKE) TEST_SUITE=pdk kong/test/run

kong/test/unit:
	$(MAKE) TEST_SUITE=unit kong/test/run
