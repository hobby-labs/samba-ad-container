#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    command cp -f /etc/resolv.conf /etc/resolv.conf.backup
    stub cp
    stub echo
    stub sync
}

function teardown() {
    command cp -f /etc/resolv.conf.backup /etc/resolv.conf
}

@test '#change_ip_of_dns should return 0 if all instructions were succeeded' {
    run change_ip_of_dns "192.168.1.73"; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times cp)"    -eq 1 ]]
    [[ "$(stub_called_times echo)"    -eq 1 ]]
    [[ "$(stub_called_times sync)"    -eq 1 ]]

    stub_called_with_exactly_times echo 1 "nameserver 192.168.1.73"
}

@test '#change_ip_of_dns should return 1 if cp /etc/resolv.conf /etc/resolv.conf.org has failed' {
    stub_and_eval cp '{ return 1; }'
    run change_ip_of_dns "192.168.1.73"; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times cp)"    -eq 1 ]]
    [[ "$(stub_called_times echo)"    -eq 1 ]]
    [[ "$(stub_called_times sync)"    -eq 0 ]]

    stub_called_with_exactly_times echo 1 "ERROR: Failed to backup /etc/resolv.conf to /etc/resolv.conf.org"
}

@test '#change_ip_of_dns should return 1 if echo to resolv.conf has failed' {
    stub_and_eval echo '{
        [[ "$1" == "nameserver 192.168.1.73" ]] && return 1
        return 0
    }'
    run change_ip_of_dns "192.168.1.73"; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times cp)"    -eq 1 ]]
    [[ "$(stub_called_times echo)"    -eq 2 ]]
    [[ "$(stub_called_times sync)"    -eq 0 ]]

    stub_called_with_exactly_times echo 1 "nameserver 192.168.1.73"
    stub_called_with_exactly_times echo 1 "ERROR: Failed to overwrite /etc/resolv.conf by \"nameserver 192.168.1.73\""
}

