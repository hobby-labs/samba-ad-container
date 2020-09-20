#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    stub samba-tool
    stub echo
    export ADMIN_PASSWORD="p@ssword0"
}

function teardown() {
    unset ADMIN_PASSWORD
}

@test '#demote_dc should return 0 if all instructions are succeeded' {
    run demote_dc; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times samba-tool)"    -eq 1 ]]
    [[ "$(stub_called_times echo)"          -eq 0 ]]

    stub_called_with_exactly_times samba-tool 1 'domain' 'demote' '--remove-other-dead-server=rpdc' '-U' 'Administrator%p@ssword0'
}

@test '#demote_dc should return 1 if samba-tool has failed' {
    stub_and_eval samba-tool '{ return 1; }'
    run demote_dc; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times samba-tool)"    -eq 1 ]]
    [[ "$(stub_called_times echo)"          -eq 1 ]]

    stub_called_with_exactly_times samba-tool 1 'domain' 'demote' '--remove-other-dead-server=rpdc' '-U' 'Administrator%p@ssword0'
    stub_called_with_exactly_times echo 1 'ERROR: Failed to demote rpdc with command "samba-tool domain demote --remove-other-dead-server=rpdc"'
}

