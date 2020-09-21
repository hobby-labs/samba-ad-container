#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    cp -a /usr/sbin/samba /usr/sbin/samba.bak > /dev/null 2>&1 || true
    ln -f -s $(which true) /usr/sbin/samba

    stub echo
    stub samba-tool
    stub sleep
    stub pkill

    export ADMIN_PASSWORD="p@ssword0"
    CHECK_COUNT_WHETHER_SAMBA_IS_RUNNING=2
}

function teardown() {
    unset ADMIN_PASSWORD
    unlink /usr/sbin/samba
    cp -a /usr/sbin/samba.bak /usr/sbin/samba > /dev/null 2>&1 || true
}

@test '#transfer_fsmo should return 0 if all instructions were succeeded' {
    run transfer_fsmo; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times samba-tool)"    -eq 2 ]]
    [[ "$(stub_called_times echo)"          -eq 1 ]]
    [[ "$(stub_called_times pkill)"         -eq 1 ]]
    [[ "$(stub_called_times sleep)"         -eq 1 ]]

    stub_called_with_exactly_times echo 1 'Waiting for samba is running...'
}

@test '#transfer_fsmo should return 1 if run samba has failed' {
    stub_and_eval samba-tool '{ return 1; }'
    run transfer_fsmo; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times samba-tool)"    -eq 2 ]]
    [[ "$(stub_called_times echo)"          -eq 2 ]]
    [[ "$(stub_called_times pkill)"         -eq 0 ]]
    [[ "$(stub_called_times sleep)"         -eq 2 ]]

    stub_called_with_exactly_times echo 1 'Waiting for samba is running...'
    stub_called_with_exactly_times echo 1 'ERROR: Failed to up samba to transfer fsmo with command "/usr/sbin/samba".'
}

@test '#transfer_fsmo should return 1 if samba-tool fsmo command has failed' {
    stub_and_eval samba-tool '{
        [[ "$1" == "fsmo" ]] && return 1
        return 0
    }'
    run transfer_fsmo; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times samba-tool)"    -eq 2 ]]
    [[ "$(stub_called_times echo)"          -eq 2 ]]
    [[ "$(stub_called_times pkill)"         -eq 0 ]]
    [[ "$(stub_called_times sleep)"         -eq 0 ]]

    stub_called_with_exactly_times echo 1 'Waiting for samba is running...'
    stub_called_with_exactly_times echo 1 'ERROR: Failed to transfer fsmo from current DC'
}
