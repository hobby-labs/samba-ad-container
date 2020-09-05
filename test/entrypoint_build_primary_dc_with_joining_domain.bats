#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    stub change_ip_of_dns
    stub join_domain
    stub transfer_fsmo
    stub restore_dns

    export DOMAIN_FQDN="corp.mysite.example.com"
    export ADMIN_PASSWORD="p@ssword0"
}

function teardown() {
    unset DOMAIN_FQDN
    unset ADMIN_PASSWORD
}

@test '#build_primary_dc_with_joining_domain should return 0 if all instructions were succeeded' {
    run build_primary_dc_with_joining_domain "192.168.1.73"; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times change_ip_of_dns)"  -eq 1 ]]
    [[ "$(stub_called_times join_domain)"       -eq 1 ]]
    [[ "$(stub_called_times restore_dns)"       -eq 1 ]]
    [[ "$(stub_called_times transfer_fsmo)"     -eq 1 ]]
}

@test '#build_primary_dc_with_joining_domain should return 1 if change_ip_of_dns has failed' {
    stub_and_eval change_ip_of_dns '{ return 1; }'
    run build_primary_dc_with_joining_domain "192.168.1.73"; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times change_ip_of_dns)"  -eq 1 ]]
    [[ "$(stub_called_times join_domain)"       -eq 0 ]]
    [[ "$(stub_called_times restore_dns)"       -eq 0 ]]
    [[ "$(stub_called_times transfer_fsmo)"     -eq 0 ]]
}

@test '#build_primary_dc_with_joining_domain should return 1 if join_domain has failed' {
    stub_and_eval join_domain '{ return 1; }'
    run build_primary_dc_with_joining_domain "192.168.1.73"; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times change_ip_of_dns)"  -eq 1 ]]
    [[ "$(stub_called_times join_domain)"       -eq 1 ]]
    [[ "$(stub_called_times restore_dns)"       -eq 0 ]]
    [[ "$(stub_called_times transfer_fsmo)"     -eq 0 ]]
}

@test '#build_primary_dc_with_joining_domain should return 1 if transfer_fsmo transfer has failed' {
    stub_and_eval transfer_fsmo '{ return 1; }'
    run build_primary_dc_with_joining_domain; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times change_ip_of_dns)"  -eq 1 ]]
    [[ "$(stub_called_times join_domain)"       -eq 1 ]]
    [[ "$(stub_called_times restore_dns)"       -eq 0 ]]
    [[ "$(stub_called_times transfer_fsmo)"     -eq 1 ]]
}

