#!/usr/bin/env bash
main() {
    local script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    local test_file="$1"

    cd "${script_dir}/../../"
    #docker run --rm --name bats --hostname bats --volume "${PWD}:/a:ro" bats/bats:latest /a/test/${test_file}
    docker run --rm --volume "${PWD}:/a:ro" bats/bats:latest /a/test
}

main "$@"

