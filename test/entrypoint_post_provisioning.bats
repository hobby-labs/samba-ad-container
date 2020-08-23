#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    mkdir -p /etc/samba/
    touch /etc/krb5.conf /etc/samba/smb.conf

    stub mv
    stub sed
    stub echo
    stub set_winbind_to_nsswitch
    export DNS_FORWARDER="8.8.8.8"
}

function teardown() {
    unset DNS_FORWARDER
    unset RESTORE_FROM
    unset FLAG_RESTORE_USERS_SMB_CONF_AFTER_PROV
}

@test '#post_provisioning should return 0 if all instructions has succeeded and FLAG_RESTORE_USERS_SMB_CONF_AFTER_PROV=0' {
    run post_provisioning; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times mv)"                        -eq 0 ]]
    [[ "$(stub_called_times sed)"                       -eq 1 ]]
    [[ "$(stub_called_times echo)"                      -eq 0 ]]
    [[ "$(stub_called_times set_winbind_to_nsswitch)"   -eq 1 ]]

    stub_called_with_exactly_times sed 1 "-i" "-e" "s/dns forwarder = .*/dns forwarder = 8.8.8.8/g" /etc/samba/smb.conf
}

@test '#post_provisioning should return 0 if RESTORE_FROM=JOINING_A_DOMAIN' {
    RESTORE_FROM=JOINING_A_DOMAIN
    run post_provisioning; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times mv)"                        -eq 0 ]]
    [[ "$(stub_called_times sed)"                       -eq 0 ]]
    [[ "$(stub_called_times echo)"                      -eq 0 ]]
    [[ "$(stub_called_times set_winbind_to_nsswitch)"   -eq 1 ]]
}

@test '#post_provisioning should return 0 if all instructions has succeeded and FLAG_RESTORE_USERS_SMB_CONF_AFTER_PROV=1' {
    FLAG_RESTORE_USERS_SMB_CONF_AFTER_PROV=1
    run post_provisioning; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times mv)"                        -eq 1 ]]
    [[ "$(stub_called_times sed)"                       -eq 0 ]]
    [[ "$(stub_called_times echo)"                      -eq 0 ]]
    [[ "$(stub_called_times set_winbind_to_nsswitch)"   -eq 1 ]]

    stub_called_with_exactly_times mv 1 "-f" "/etc/samba/smb.conf.bak" "/etc/samba/smb.conf"
}

@test '#post_provisioning should return 1 if set_winbind_to_nsswitch has failed' {
    stub_and_eval set_winbind_to_nsswitch '{ return 1; }'
    run post_provisioning; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times mv)"                        -eq 0 ]]
    [[ "$(stub_called_times sed)"                       -eq 0 ]]
    [[ "$(stub_called_times echo)"                      -eq 0 ]]
    [[ "$(stub_called_times set_winbind_to_nsswitch)"   -eq 1 ]]
}

@test '#post_provisioning should return 1 if mv returns NOT 0 and FLAG_RESTORE_USERS_SMB_CONF_AFTER_PROV=0' {
    stub_and_eval sed '{ return 1; }'
    run post_provisioning; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times mv)"                        -eq 0 ]]
    [[ "$(stub_called_times sed)"                       -eq 1 ]]
    [[ "$(stub_called_times echo)"                      -eq 1 ]]
    [[ "$(stub_called_times set_winbind_to_nsswitch)"   -eq 1 ]]

    stub_called_with_exactly_times sed 1 "-i" "-e" "s/dns forwarder = .*/dns forwarder = 8.8.8.8/g" "/etc/samba/smb.conf"
    stub_called_with_exactly_times echo 1 "ERROR: Failed to modify /etc/samba/smb.conf to change \"dns forwarder = 8.8.8.8\" after DC has provisioned"
}

@test '#post_provisioning should return 1 if mv returns NOT 0 and FLAG_RESTORE_USERS_SMB_CONF_AFTER_PROV=1' {
    FLAG_RESTORE_USERS_SMB_CONF_AFTER_PROV=1
    stub_and_eval mv '{ return 1; }'
    run post_provisioning; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times mv)"                        -eq 1 ]]
    [[ "$(stub_called_times sed)"                       -eq 0 ]]
    [[ "$(stub_called_times echo)"                      -eq 1 ]]
    [[ "$(stub_called_times set_winbind_to_nsswitch)"   -eq 1 ]]

    stub_called_with_exactly_times mv 1 "-f" "/etc/samba/smb.conf.bak" "/etc/samba/smb.conf"
}
