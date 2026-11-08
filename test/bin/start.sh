#!/usr/bin/env bash
#
# Run bats unit tests.
#
# Usage: test/bin/start.sh [<test file or directory> ...]
#   Runs all tests under ./test if no argument is given.
#
# Inside a container (e.g. hobbylabs/test-samba-ad-container) bats is executed directly.
# On a host, the test image is built from test/container/Dockerfile and bats runs in it.
#
# Environment variables:
#   TEST_IMAGE  Image used to run tests on a host (default: test-samba-ad-container:local)

TEST_IMAGE="${TEST_IMAGE:-test-samba-ad-container:local}"

main() {
    local script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

    cd "${script_dir}/../../"
    git submodule update --init --recursive || return 1

    if [[ $# -eq 0 ]]; then
        set -- ./test
    fi

    if [[ -f /.dockerenv ]]; then
        bats "$@"
    else
        docker build -q -t "$TEST_IMAGE" ./test/container > /dev/null || {
            echo "ERROR: Failed to build test image ${TEST_IMAGE} from ./test/container" >&2
            return 1
        }
        docker run --rm --volume "${PWD}:/a:ro" --workdir /a "$TEST_IMAGE" bats "$@"
    fi
}

main "$@"
