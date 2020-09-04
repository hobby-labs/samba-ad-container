#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    mkdir -p /etc/samba/
    touch /etc/krb5.conf /etc/samba/smb.conf
    stub mv
    stub echo
    stub prepare_hosts
    stub prepare_krb5_conf

    export DC_TYPE="PRIMARY_DC"
}

function teardown() {
    rm -f /etc/krb5.conf /etc/samba/smb.conf
    unset RESTORE_FROM
    unset DC_TYPE
    unset RESTORE_FROM
}

@test '#pre_provisioning should return 0 if all instructions has succeeded and users smb.conf was NOT existed' {
    rm -f /etc/samba/smb.conf
    run pre_provisioning; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times mv)"                    -eq 0 ]]
    [[ "$(stub_called_times prepare_hosts)"         -eq 1 ]]
    [[ "$(stub_called_times prepare_krb5_conf)"     -eq 0 ]]
    [[ "$(stub_called_times echo)"                  -eq 0 ]]
}

@test '#pre_provisioning should return 0 if DC_TYPE="SECONDARY_DC"' {
    rm -f /etc/samba/smb.conf
    unset RESTORE_FROM
    run pre_provisioning; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times prepare_krb5_conf)"     -eq 0 ]]
    [[ "$(stub_called_times mv)"                    -eq 0 ]]
    [[ "$(stub_called_times prepare_hosts)"         -eq 1 ]]
    [[ "$(stub_called_times echo)"                  -eq 0 ]]
}

@test '#pre_provisioning should return 0 if DC_TYPE="PRIMARY_DC" && RESTORE_FROM="JOINING_DOMAIN"' {
    rm -f /etc/samba/smb.conf
    export RESTORE_FROM="JOINING_DOMAIN"
    run pre_provisioning; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times prepare_krb5_conf)"     -eq 1 ]]
    [[ "$(stub_called_times mv)"                    -eq 0 ]]
    [[ "$(stub_called_times prepare_hosts)"         -eq 1 ]]
    [[ "$(stub_called_times echo)"                  -eq 0 ]]
}

@test '#pre_provisioning should return 0 if DC_TYPE="PRIMARY_DC" && RESTORE_FROM="IP"' {
    rm -f /etc/samba/smb.conf
    export RESTORE_FROM="192.168.1.73"
    run pre_provisioning; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times prepare_krb5_conf)"     -eq 1 ]]
    [[ "$(stub_called_times mv)"                    -eq 0 ]]
    [[ "$(stub_called_times prepare_hosts)"         -eq 1 ]]
    [[ "$(stub_called_times echo)"                  -eq 0 ]]
}

@test '#pre_provisioning should return 0 if RESTORE_FROM=JOINING_A_DOMAIN' {
    RESTORE_FROM="JOINING_A_DOMAIN"
    run pre_provisioning; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times prepare_krb5_conf)"     -eq 0 ]]
    [[ "$(stub_called_times mv)"                    -eq 0 ]]
    [[ "$(stub_called_times prepare_hosts)"         -eq 1 ]]
    [[ "$(stub_called_times echo)"                  -eq 0 ]]
}

@test '#pre_provisioning should return 0 if all instructions has succeeded and /etc/smb.conf that prepared by user was existed' {
    run pre_provisioning; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times prepare_krb5_conf)"     -eq 0 ]]
    [[ "$(stub_called_times mv)"                    -eq 1 ]]
    [[ "$(stub_called_times prepare_hosts)"         -eq 1 ]]
    [[ "$(stub_called_times echo)"                  -eq 0 ]]
    stub_called_with_exactly_times mv 1 "-f" "/etc/samba/smb.conf" "/etc/samba/smb.conf.bak"
}

@test '#pre_provisioning should return 1 if mv has failed' {
    stub_and_eval mv '{ return 1; }'
    run pre_provisioning; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times mv)"                    -eq 1 ]]
    [[ "$(stub_called_times prepare_hosts)"         -eq 1 ]]
    [[ "$(stub_called_times echo)"                  -eq 1 ]]

    stub_called_with_exactly_times mv 1 "-f" "/etc/samba/smb.conf" "/etc/samba/smb.conf.bak"
    stub_called_with_exactly_times echo 1 "ERROR: Failed to move /etc/samba/smb.conf before running \"samba-tool domain provision\". Provisioning process will be quitted"
}

@test '#pre_provisioning should return 1 if prepare_hosts has failed' {
    stub_and_eval prepare_hosts '{ return 1; }'
    run pre_provisioning; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times mv)"                    -eq 0 ]]
    [[ "$(stub_called_times prepare_hosts)"         -eq 1 ]]
    [[ "$(stub_called_times echo)"                  -eq 0 ]]
}

