#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

function test() {
    echo '--- testing kong ---'
    cp -R /tmp/build/* /
    mv /tmp/build /tmp/buffer # Check we didn't link dependencies to `/tmp/build/...`

    kong version
    kong roar
    KONG_DATABASE=off kong start
    curl localhost:8001
    KONG_DATABASE=off kong restart
    curl localhost:8001
    kong stop

    # Sleep long enough that Kong isn't running
    sleep 10

    mv /tmp/buffer /tmp/build
    echo '--- tested kong ---'
}

test
