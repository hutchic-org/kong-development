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

    mv /tmp/buffer /tmp/build
    echo '--- tested kong ---'
}

test
