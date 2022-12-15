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
  OPERATING_SYSTEM=${OPERATING_SYSTEM:-ubuntu}
  OPERATING_SYSTEM_VERSION=${OPERATING_SYSTEM_VERSION:-22.04}
  DOCKER_ARCHITECTURE=${DOCKER_ARCHITECTURE:-amd64}
  PACKAGE_TYPE=${PACKAGE_TYPE:-deb}

  if [[ "$OPERATING_SYSTEM" == "rhel" ]]; then
    OPERATING_SYSTEM="redhat/ubi${OPERATING_SYSTEM_VERSION}"
    OPERATING_SYSTEM_VERSION="latest"
  fi

  USE_TTY="-t"
  test -t 1 && USE_TTY="-it"

  docker kill package-validation-tests || true

  sleep 5

  docker run -d --rm \
    --name package-validation-tests \
    --platform="linux/$DOCKER_ARCHITECTURE" \
    -v "${PWD}/package:/src" \
    ${OPERATING_SYSTEM}:${OPERATING_SYSTEM_VERSION} \
    tail -f /dev/null || true

  if [[ "$PACKAGE_TYPE" == "deb" ]]; then
    docker exec ${USE_TTY} package-validation-tests /bin/bash -c "apt-get update"
    docker exec ${USE_TTY} package-validation-tests /bin/bash -c "apt-get install -y perl-base zlib1g-dev procps"
    docker exec ${USE_TTY} package-validation-tests /bin/bash -c "apt install --yes /src/*.deb"
    docker exec ${USE_TTY} package-validation-tests /bin/bash -c "kong version"
  fi

  if [[ "$PACKAGE_TYPE" == "rpm" ]]; then
    docker exec ${USE_TTY} package-validation-tests /bin/bash -c "yum install -y /src/*.rpm procps"
    docker exec ${USE_TTY} package-validation-tests /bin/bash -c "kong version"
  fi

  if [[ "$PACKAGE_TYPE" == "apk" ]]; then
    exit 0
  fi

  # Kong can start, restart, and stop as the Kong user
  docker exec ${USE_TTY} package-validation-tests /bin/bash -c "su - kong -c 'KONG_DATABASE=off kong start'"
  docker exec ${USE_TTY} package-validation-tests /bin/bash -c "su - kong -c 'KONG_DATABASE=off kong health'"
  docker exec ${USE_TTY} package-validation-tests /bin/bash -c "ps aux | grep [m]aster | grep -q [k]ong"
  docker exec ${USE_TTY} package-validation-tests /bin/bash -c "su - kong -c 'KONG_DATABASE=off kong restart'"
  docker exec ${USE_TTY} package-validation-tests /bin/bash -c "su - kong -c 'KONG_DATABASE=off kong health'"
  docker exec ${USE_TTY} package-validation-tests /bin/bash -c "ps aux | grep [m]aster | grep -q [k]ong"
  docker exec ${USE_TTY} package-validation-tests /bin/bash -c "su - kong -c 'KONG_DATABASE=off kong stop'"

  # Kong can start, restart, and stop as the root user
  docker exec ${USE_TTY} package-validation-tests /bin/bash -c "KONG_DATABASE=off kong start"
  docker exec ${USE_TTY} package-validation-tests /bin/bash -c "KONG_DATABASE=off kong health"
  docker exec ${USE_TTY} package-validation-tests /bin/bash -c "ps aux | grep [m]aster | grep -q [r]oot"
  docker exec ${USE_TTY} package-validation-tests /bin/bash -c "KONG_DATABASE=off kong restart"
  docker exec ${USE_TTY} package-validation-tests /bin/bash -c "KONG_DATABASE=off kong health"
  docker exec ${USE_TTY} package-validation-tests /bin/bash -c "ps aux | grep [m]aster | grep -q [r]oot"
  docker exec ${USE_TTY} package-validation-tests /bin/bash -c "KONG_DATABASE=off kong stop"

  docker exec ${USE_TTY} package-validation-tests /bin/sh -c "ls -l /etc/kong/kong.conf.default"
  docker exec ${USE_TTY} package-validation-tests /bin/sh -c "ls -l /etc/kong/kong*.logrotate"
  docker exec ${USE_TTY} package-validation-tests /bin/sh -c "ls -l /usr/local/kong/include/google/protobuf/*.proto"
  docker exec ${USE_TTY} package-validation-tests /bin/sh -c "ls -l /usr/local/kong/include/openssl/*.h"

  docker kill package-validation-tests

  if [[ "$PACKAGE_TYPE" == "rpm" ]]; then
    docker kill systemd || true

    sleep 5

    docker run -d --rm --name=systemd --privileged --tmpfs /tmp --tmpfs /run --tmpfs /run/lock -v ${PWD}/package:/src redhat/ubi8-init
    docker exec ${USE_TTY} systemd /bin/bash -c "yum install -y /src/*.rpm"
    docker exec ${USE_TTY} systemd /bin/bash -c "kong version"

    docker exec ${USE_TTY} systemd /bin/bash -c "test -f /etc/kong/kong*.logrotate"
    docker exec ${USE_TTY} systemd /bin/bash -c "mkdir -p /etc/systemd/system/kong.service.d/"
    docker exec ${USE_TTY} systemd /bin/bash -c "cat <<\EOD > /etc/systemd/system/kong.service.d/override.conf
[Service]
Environment=KONG_DATABASE=off KONG_NGINX_MAIN_WORKER_PROCESSES=2
EOD"
    sleep 5
    docker exec ${USE_TTY} systemd /bin/bash -c "systemctl daemon-reload"
    sleep 5
    docker exec ${USE_TTY} systemd /bin/bash -c "systemctl start kong"

    docker exec ${USE_TTY} systemd /bin/bash -c 'for i in {1..15}; do if test -s /usr/local/kong/pids/nginx.pid; then break; fi; echo waiting for pidfile...; sleep 1; done'

    docker exec ${USE_TTY} systemd /bin/bash -c "systemctl --no-pager status kong"
    docker exec ${USE_TTY} systemd /bin/bash -c "systemctl reload kong"
    sleep 5
    docker exec ${USE_TTY} systemd /bin/bash -c "systemctl --no-pager status kong"
    docker exec ${USE_TTY} systemd /bin/bash -c "systemctl restart kong"
    sleep 5
    docker exec ${USE_TTY} systemd /bin/bash -c "systemctl --no-pager status kong"
    docker exec ${USE_TTY} systemd /bin/bash -c "systemctl stop kong"
    sleep 5
    docker exec ${USE_TTY} systemd /bin/bash -c "systemctl --no-pager status kong || true" # systemctl will exit with 3 if unit is not active
    docker kill systemd
  fi
}

main
