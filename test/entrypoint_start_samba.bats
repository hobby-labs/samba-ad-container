#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    stub exec
}

function teardown() {
    unset RESTORE_WITH
}

@test '#start_samba should return 0 if all instructions were succeeded' {
    run start_samba; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times exec)"                      -eq 1 ]]

    stub_called_with_exactly_times exec 1 "/usr/sbin/samba" "-i"
}

@test '#start_samba should return 0 if RESTORE_WITH=BACKUP_FILE' {
    RESTORE_WITH=BACKUP_FILE
    run start_samba; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times exec)"                      -eq 1 ]]

    stub_called_with_exactly_times exec 1 "/usr/sbin/samba" "-i" "-s" "/var/lib/restored_samba/etc/smb.conf"
}

