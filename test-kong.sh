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

    mv /kong/.ci/run_tests.sh.bak /kong/.ci/run_tests.sh || true
    cp /kong/.ci/run_tests.sh /kong/.ci/run_tests.sh.bak
    sed -i "s/export BUSTED_ARGS.*/DEFAULT_BUSTED_ARGS=\"--no-k -o htest -v --exclude-tags=flaky,ipv6\"\nexport BUSTED_ARGS=\${BUSTED_ARGS:-\$DEFAULT_BUSTED_ARGS}/g" /kong/.ci/run_tests.sh
    sed -i "s/ON_ERROR_STOP=1/ON_ERROR_STOP=0/g" /kong/.ci/run_tests.sh
    BUSTED_ARGS='--no-k -o htest -v --filter-out="dangling socket cleanup" --exclude-tags=flaky,ipv6' /kong/.ci/run_tests.sh
    mv /kong/.ci/run_tests.sh.bak /kong/.ci/run_tests.sh
}

test
