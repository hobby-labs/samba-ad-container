#!/usr/bin/env bash
main() {
    local script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    local test_file="$1"

    cd "${script_dir}/../../"
    git submodule update --init --recursive

    if [[ -f .dockerenv ]]; then
        bats ./test
    else
        docker run --rm --volume "${PWD}:/a:ro" bats/bats:latest "$@"
    fi
}

main "$@"

