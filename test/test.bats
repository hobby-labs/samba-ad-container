#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    true
}

function teardown() {
    rm -f "$INITIALIZED_FLAG_FILE"
}

@test '#test 01' {
    run flag_initialized
    [[ -f "$INITIALIZED_FLAG_FILE" ]]
}

@test '#test 02' {
    true
}

