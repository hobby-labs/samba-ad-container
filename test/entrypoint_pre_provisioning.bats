#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    mkdir -p /etc/samba/
    touch /etc/krb5.conf /etc/samba/smb.conf
    stub mv
}

function teardown() {
    rm -f /etc/krb5.conf /etc/samba/smb.conf
    unset RESTORE_WITH
}

@test '#pre_provisioning should return 0 if all instructions has succeeded and users smb.conf was NOT existed' {
    rm -f /etc/samba/smb.conf
    run pre_provisioning; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times mv)"                    -eq 0 ]]
}

@test '#pre_provisioning should return 0 if RESTORE_WITH=JOINING_A_DOMAIN' {
    RESTORE_WITH="JOINING_A_DOMAIN"
    run pre_provisioning; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times mv)"                    -eq 0 ]]
}

@test '#pre_provisioning should return 0 if all instructions has succeeded and users smb.conf was existed' {
    run pre_provisioning; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times mv)"                    -eq 1 ]]
    stub_called_with_exactly_times mv 1 "-f" "/etc/samba/smb.conf" "/etc/samba/smb.conf.bak"
}




@test '#pre_provisioning should return 1 if mv was failed and smb.conf of user was existed' {
    run pre_provisioning; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times mv)"                    -eq 1 ]]

}

