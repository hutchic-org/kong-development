#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

# Ideally this file doesn't exist and we can just run the tests. There's no canon
# way to run kong tests so we do this to abstract force a common way to test
function test() {
    if [ "$TEST_SUITE" == "unit" ]; then
        unset KONG_DATABASE KONG_TEST_DATABASE
    fi

    /kong/.ci/run_tests.sh
}

test
