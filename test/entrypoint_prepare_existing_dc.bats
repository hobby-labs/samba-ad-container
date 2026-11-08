#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    mkdir -p /etc/samba/
    touch /etc/samba/smb.conf

    stub prepare_hosts
    stub set_winbind_to_nsswitch
    stub install_krb5_conf
    stub echo
}

function teardown() {
    rm -f /etc/samba/smb.conf
}

@test '#prepare_existing_dc should return 0 if all instructions were succeeded' {
    run prepare_existing_dc; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times prepare_hosts)"             -eq 1 ]]
    [[ "$(stub_called_times set_winbind_to_nsswitch)"   -eq 1 ]]
    [[ "$(stub_called_times install_krb5_conf)"         -eq 1 ]]
    [[ "$(stub_called_times echo)"                      -eq 0 ]]
}

@test '#prepare_existing_dc should return 1 if /etc/samba/smb.conf does not exist' {
    rm -f /etc/samba/smb.conf
    run prepare_existing_dc; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times prepare_hosts)"             -eq 0 ]]
    [[ "$(stub_called_times set_winbind_to_nsswitch)"   -eq 0 ]]
    [[ "$(stub_called_times echo)"                      -eq 1 ]]
    stub_called_with_exactly_times echo 1 "ERROR: /var/lib/samba/private/sam.ldb exists but /etc/samba/smb.conf does not." \
        "Mount /etc/samba that contains smb.conf of the existing DC as well as /var/lib/samba." \
        "This program does not provision to prevent destroying existing DC data."
}

@test '#prepare_existing_dc should return 1 if prepare_hosts has failed' {
    stub_and_eval prepare_hosts '{ return 1; }'
    run prepare_existing_dc; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times prepare_hosts)"             -eq 1 ]]
    [[ "$(stub_called_times set_winbind_to_nsswitch)"   -eq 0 ]]
}

@test '#prepare_existing_dc should return 1 if set_winbind_to_nsswitch has failed' {
    stub_and_eval set_winbind_to_nsswitch '{ return 1; }'
    run prepare_existing_dc; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times prepare_hosts)"             -eq 1 ]]
    [[ "$(stub_called_times set_winbind_to_nsswitch)"   -eq 1 ]]
    [[ "$(stub_called_times install_krb5_conf)"         -eq 0 ]]
}
