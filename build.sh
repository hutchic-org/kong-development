#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

# Retries a command a configurable number of times with backoff.
#
# The retry count is given by ATTEMPTS (default 5), the initial backoff
# timeout is given by TIMEOUT in seconds (default 1.)
#
# Successive backoffs double the timeout.
function with_backoff {
  local max_attempts=${ATTEMPTS-5}
  local timeout=${TIMEOUT-5}
  local attempt=1
  local exitCode=0

  while (( $attempt < $max_attempts ))
  do
    if "$@"
    then
      return 0
    else
      exitCode=$?
    fi

    echo "Failure! Retrying in $timeout.." 1>&2
    sleep $timeout
    attempt=$(( attempt + 1 ))
    timeout=$(( timeout * 2 ))
  done

  if [[ $exitCode != 0 ]]
  then
    echo "You've failed me for the last time! ($@)" 1>&2
  fi

  return $exitCode
}

function main() {
  echo '--- installing kong ---'
  ROCKS_CONFIG=$(mktemp)
  echo "
  rocks_trees = {
    { name = [[system]], root = [[/tmp/build/usr/local]] }
  }
  " > $ROCKS_CONFIG

  if [[ -d /usr/local/share/lua ]]; then
    cp -R /usr/local/share/lua/ /tmp/build/usr/local/share/
  fi
  cp -R /tmp/build/* /

  export LUAROCKS_CONFIG=$ROCKS_CONFIG
  export LUA_PATH="/usr/local/share/lua/5.1/?.lua;/usr/local/openresty/luajit/share/luajit-2.1.0-beta3/?.lua;;"
  export PATH=$PATH:/usr/local/openresty/luajit/bin

  pushd /kong
    ROCKSPEC_VERSION=`basename /kong/kong-*.rockspec` \
      && ROCKSPEC_VERSION=${ROCKSPEC_VERSION%.*} \
      && ROCKSPEC_VERSION=${ROCKSPEC_VERSION#"kong-"}

    mkdir -p /tmp/plugin

    if [ "${SSL_PROVIDER-openssl}" = "boringssl" ]; then
      sed -i 's/fips = off/fips = on/g' kong/templates/kong_defaults.lua
    fi

    with_backoff /usr/local/bin/luarocks make kong-${ROCKSPEC_VERSION}.rockspec \
      CRYPTO_DIR=/usr/local/kong \
      OPENSSL_DIR=/usr/local/kong \
      YAML_LIBDIR=/tmp/build/usr/local/kong/lib \
      YAML_INCDIR=/tmp/yaml \
      EXPAT_DIR=/usr/local/kong \
      LIBXML2_DIR=/usr/local/kong \
      CFLAGS="-L/tmp/build/usr/local/kong/lib -Wl,-rpath,/usr/local/kong/lib -O2 -std=gnu99 -fPIC"

    mkdir -p /tmp/build/etc/kong
    cp kong.conf.default /tmp/build/usr/local/lib/luarocks/rock*/kong/$ROCKSPEC_VERSION/
    cp kong.conf.default /tmp/build/etc/kong/kong.conf.default

    # /usr/local/kong/include is usually created by other C libraries, like openssl
    # call mkdir here to make sure it's created
    if [ -e "kong/include" ]; then
      mkdir -p /tmp/build/usr/local/kong/include
      cp -r kong/include/* /tmp/build/usr/local/kong/include/
    fi

    # circular dependency of CI: remove after https://github.com/Kong/kong-distributions/pull/791 is merged
    if [ -e "kong/pluginsocket.proto" ]; then
      cp kong/pluginsocket.proto /tmp/build/usr/local/kong/include/kong
    fi

    with_backoff curl -fsSLo /tmp/protoc.zip https://github.com/protocolbuffers/protobuf/releases/download/v3.19.0/protoc-3.19.0-linux-x86_64.zip
    unzip -o /tmp/protoc.zip -d /tmp/protoc 'include/*'
    cp -r /tmp/protoc/include/google /tmp/build/usr/local/kong/include/
  popd

  cp /kong/COPYRIGHT /tmp/build/usr/local/kong/
  cp /kong/bin/kong /tmp/build/usr/local/bin/kong
  sed -i 's/resty/\/usr\/local\/openresty\/bin\/resty/' /tmp/build/usr/local/bin/kong
  sed -i 's/\/tmp\/build//' `grep -l -I -r '\/tmp\/build' /tmp/build/` || true

  chown -R 1000:1000 /tmp/build/*

  echo '--- installed kong ---'
}

main
