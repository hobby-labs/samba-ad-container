#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    command rm -f /etc/resolv.conf.org
    command cp -f /etc/resolv.conf /etc/resolv.conf.backup
    stub cp
    stub echo
}

function teardown() {
    command rm -f /etc/resolv.conf.org
    command cp -f /etc/resolv.conf.backup /etc/resolv.conf
}

@test '#restore_dns should return 0 if all instructions has succeeded' {
    touch /etc/resolv.conf.org
    run restore_dns; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times cp)"    -eq 1 ]]
    [[ "$(stub_called_times echo)"  -eq 0 ]]

    stub_called_with_exactly_times cp 1 "-f" "/etc/resolv.conf.org" "/etc/resolv.conf"
}

@test '#restore_dns should return 0 if /etc/resolv.conf.org does not exist' {
    run restore_dns; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times cp)"    -eq 0 ]]
    [[ "$(stub_called_times echo)"  -eq 1 ]]

    stub_called_with_exactly_times echo 1 "INFO: Backup file /etc/resolv.conf.org does not exist. Restoring process will be skipped"
}

@test '#restore_dns should return 1 if cp /etc/resolv.conf.org /etc/resolv.conf has failed' {
    stub_and_eval cp '{ return 1; }'
    touch /etc/resolv.conf.org
    run restore_dns; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times cp)"    -eq 1 ]]
    [[ "$(stub_called_times echo)"  -eq 1 ]]

    stub_called_with_exactly_times cp 1 "-f" "/etc/resolv.conf.org" "/etc/resolv.conf"
    stub_called_with_exactly_times echo 1 "ERROR: Failed to restore resolv.conf. Copying file /etc/resolv.conf.org to /etc/resolv.conf has failed"
}
