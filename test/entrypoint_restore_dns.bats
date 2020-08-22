#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    stub samba-tool
    stub echo
    export DOMAIN_FQDN="mysite.example.com"
    export ADMIN_PASSWORD="p@ssword0"
}

function teardown() {
    true
    unset DOMAIN_FQDN
}

@test '#join_domain should return 0 if all instructions have succeeded' {
    run join_domain; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times samba-tool)"    -eq 1 ]]
    [[ "$(stub_called_times echo)"          -eq 0 ]]

    stub_called_with_exactly_times samba-tool 1 domain join mysite.example.com DC "-UAdministrator%p@ssword0"
}

@test '#join_domain should return 1 if samba-tool has failed' {
    stub_and_eval samba-tool '{ return 1; }'
    run join_domain; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times samba-tool)"    -eq 1 ]]
    [[ "$(stub_called_times echo)"          -eq 1 ]]

    stub_called_with_exactly_times samba-tool 1 domain join mysite.example.com DC "-UAdministrator%p@ssword0"
    stub_called_with_exactly_times echo 1 "ERROR: Failed to join the domain \"mysite.example.com\" with samba-tool"
}

