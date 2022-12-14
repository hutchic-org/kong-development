ARG OSTYPE=linux-gnu
ARG ARCHITECTURE=x86_64
ARG DOCKER_REGISTRY=ghcr.io
ARG DOCKER_IMAGE_NAME

ARG OPERATING_SYSTEM=ubuntu
ARG OPERATING_SYSTEM_VERSION="22.04"

# List out all image permutations to trick dependabot
FROM --platform=linux/amd64 ghcr.io/hutchic-org/kong-runtime:1.0.8-x86_64-linux-musl as x86_64-linux-musl
FROM --platform=linux/amd64 ghcr.io/hutchic-org/kong-runtime:1.0.8-x86_64-linux-gnu as x86_64-linux-gnu
FROM --platform=linux/arm64 ghcr.io/hutchic-org/kong-runtime:1.0.8-aarch64-linux-musl as aarch64-linux-musl
FROM --platform=linux/arm64 ghcr.io/hutchic-org/kong-runtime:1.0.8-aarch64-linux-gnu as aarch64-linux-gnu


# Run the build script
FROM $ARCHITECTURE-$OSTYPE as build

COPY . /tmp
WORKDIR /tmp

COPY kong /kong

# Run our predecessor tests
# Configure, build, and install
# Run our own tests
# Re-run our predecessor tests
ENV DEBUG=0
RUN /test/*/test.sh && \
    /tmp/build.sh && \
    /tmp/test.sh && \
    /test/*/test.sh

# Test scripts left where downstream images can run them
COPY test.sh /test/kong-development/test.sh


# Copy the build result to scratch so we can export the result
FROM scratch as build-result
COPY --from=build /tmp/build /


# Use FPM to change the contents of /tmp/build into a deb / rpm / apk.tar.gz
FROM kong/fpm:0.5.1 as fpm

COPY /build-result /tmp/build
COPY /fpm /fpm

# Keep sync'd with the fpm/package.sh variables
ARG PACKAGE_TYPE=deb
ENV PACKAGE_TYPE=${PACKAGE_TYPE}

ARG KONG_VERSION=3.0.1
ENV KONG_VERSION=${KONG_VERSION}

ARG OPERATING_SYSTEM=ubuntu
ENV OPERATING_SYSTEM=${OPERATING_SYSTEM}

ARG OPERATING_SYSTEM_VERSION="22.04"
ENV OPERATING_SYSTEM_VERSION=${OPERATING_SYSTEM_VERSION}

WORKDIR /fpm
RUN ./package.sh


# Copy the build result to scratch so we can export the result
FROM scratch as package

COPY --from=fpm /output/* /
