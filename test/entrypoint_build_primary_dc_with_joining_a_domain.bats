#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    stub samba-tool
    stub echo

    export DOMAIN_FQDN="corp.mysite.example.com"
    export ADMIN_PASSWORD="p@ssword0"
}

function teardown() {
    unset DOMAIN_FQDN
    unset ADMIN_PASSWORD
}

@test '#build_primary_dc_with_joining_domain should return 0 if all instructions were succeeded' {
    run build_primary_dc_with_joining_domain; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times samba-tool)" -eq 2 ]]
    [[ "$(stub_called_times echo)" -eq 0 ]]

    stub_called_with_exactly_times samba-tool 1 "domain" "join" "corp.mysite.example.com" "DC" "-U" "Administrator%p@ssword0"
    stub_called_with_exactly_times samba-tool 1 "fsmo" "transfer" "--role=all" "-U" "Administrator%p@ssword0"
}

@test '#build_primary_dc_with_joining_domain should return 1 if samba-tool domain join has failed' {
    stub_and_eval samba-tool '{
        if [[ "$1" == "domain" ]] && [[ "$2" == "join" ]]; then
            return 1;
        fi
        return 0;
    }'
    run build_primary_dc_with_joining_domain; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times samba-tool)" -eq 1 ]]
    [[ "$(stub_called_times echo)" -eq 1 ]]

    stub_called_with_exactly_times samba-tool 1 "domain" "join" "corp.mysite.example.com" "DC" "-U" "Administrator%p@ssword0"
    stub_called_with_exactly_times echo 1 "ERROR: Failed to join the domain \"corp.mysite.example.com\" with samba-tool."
}

@test '#build_primary_dc_with_joining_domain should return 1 if samba-tool fsmo transfer has failed' {
    stub_and_eval samba-tool '{
        if [[ "$1" == "fsmo" ]] && [[ "$2" == "transfer" ]]; then
            return 1;
        fi
        return 0;
    }'
    run build_primary_dc_with_joining_domain; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times samba-tool)" -eq 2 ]]
    [[ "$(stub_called_times echo)" -eq 1 ]]

    stub_called_with_exactly_times samba-tool 1 "domain" "join" "corp.mysite.example.com" "DC" "-U" "Administrator%p@ssword0"
    stub_called_with_exactly_times samba-tool 1 "fsmo" "transfer" "--role=all" "-U" "Administrator%p@ssword0"
    stub_called_with_exactly_times echo 1 "ERROR: Failed to transfer fsmo"
}

