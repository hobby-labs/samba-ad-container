#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    mkdir -p /etc/samba/
    touch /etc/krb5.conf /etc/samba/smb.conf

    export DC_TYPE="PRIMARY_DC"
    export DOMAIN="CORP"
    export DOMAIN_FQDN="corp.mysite.example.com"
    export ADMIN_PASSWORD="p@ssword0"
    export CONTAINER_IP="172.16.0.2"
    export DNS_FORWARDER="192.168.1.1"

    stub samba-tool
    stub echo
    stub pre_provisioning
    stub post_provisioning

    stub build_primary_dc_with_backup_file
    stub build_primary_dc_with_joining_domain
}

function teardown() {
    unset DC_TYPE
    unset DOMAIN
    unset DOMAIN_FQDN
    unset ADMIN_PASSWORD
    unset CONTAINER_IP
    unset DNS_FORWARDER
    unset RESTORE_FROM
}

@test '#build_dc should return 0 if all processes are succeeded with DC_TYPE=PRIMARY_DC' {
    run build_dc; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times samba-tool)"                                -eq 1 ]]
    [[ "$(stub_called_times echo)"                                      -eq 0 ]]
    [[ "$(stub_called_times pre_provisioning)"                          -eq 1 ]]
    [[ "$(stub_called_times post_provisioning)"                         -eq 1 ]]
    [[ "$(stub_called_times build_primary_dc_with_backup_file)"         -eq 0 ]]
    [[ "$(stub_called_times build_primary_dc_with_joining_domain)"      -eq 0 ]]

    stub_called_with_exactly_times samba-tool 1 "domain" "provision" "--use-rfc2307" "--domain=CORP" \
                                                "--realm=CORP.MYSITE.EXAMPLE.COM" "--server-role=dc" \
                                                "--dns-backend=SAMBA_INTERNAL" "--adminpass=p@ssword0" "--host-ip=172.16.0.2"
}

@test '#build_dc should return 0 if all processes are succeeded with DC_TYPE=PRIMARY_DC and RESTORE_FROM=BACKUP_FILE' {
    export RESTORE_FROM="BACKUP_FILE"
    run build_dc; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times samba-tool)"                                -eq 0 ]]
    [[ "$(stub_called_times echo)"                                      -eq 0 ]]
    [[ "$(stub_called_times pre_provisioning)"                          -eq 1 ]]
    [[ "$(stub_called_times post_provisioning)"                         -eq 1 ]]
    [[ "$(stub_called_times build_primary_dc_with_backup_file)"         -eq 1 ]]
    [[ "$(stub_called_times build_primary_dc_with_joining_domain)"      -eq 0 ]]
}

@test '#build_dc should return 0 if all processes are succeeded with DC_TYPE=PRIMARY_DC and RESTORE_FROM=JOINING_DOMAIN' {
    export RESTORE_FROM="JOINING_DOMAIN"
    stub_and_eval host '{ command echo "rpdc has address 192.168.1.73"; }'
    run build_dc; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times samba-tool)"                                -eq 0 ]]
    [[ "$(stub_called_times echo)"                                      -eq 0 ]]
    [[ "$(stub_called_times pre_provisioning)"                          -eq 1 ]]
    [[ "$(stub_called_times post_provisioning)"                         -eq 1 ]]
    [[ "$(stub_called_times build_primary_dc_with_backup_file)"         -eq 0 ]]
    [[ "$(stub_called_times build_primary_dc_with_joining_domain)"      -eq 1 ]]
    [[ "$(stub_called_times host)"                                      -eq 1 ]]
    stub_called_with_exactly_times build_primary_dc_with_joining_domain 1 "192.168.1.73"
}

@test '#build_dc should return 1 if all processes are succeeded with DC_TYPE=PRIMARY_DC and RESTORE_FROM=JOINING_DOMAIN but failed to get IP of rpdc' {
    export RESTORE_FROM="JOINING_DOMAIN"
    stub_and_eval host '{ command echo "rpdc has address 256.256.256.256"; }'
    run build_dc; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times samba-tool)"                                -eq 0 ]]
    [[ "$(stub_called_times echo)"                                      -eq 1 ]]
    [[ "$(stub_called_times pre_provisioning)"                          -eq 1 ]]
    [[ "$(stub_called_times post_provisioning)"                         -eq 0 ]]
    [[ "$(stub_called_times build_primary_dc_with_backup_file)"         -eq 0 ]]
    [[ "$(stub_called_times build_primary_dc_with_joining_domain)"      -eq 0 ]]
    [[ "$(stub_called_times host)"                                      -eq 1 ]]

    stub_called_with_exactly_times echo 1 "ERROR: Could not get IP from the host name \"rpdc\". [result=256.256.256.256]"
}

@test '#build_dc should return 0 if all processes are succeeded with DC_TYPE=PRIMARY_DC and RESTORE_FROM=192.168.1.73' {
    export RESTORE_FROM="JOINING_DOMAIN"

    stub_and_eval host '{ command echo "rpdc has address 256.256.256.256"; }'
    run build_dc; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times samba-tool)"                                -eq 0 ]]
    [[ "$(stub_called_times echo)"                                      -eq 1 ]]
    [[ "$(stub_called_times pre_provisioning)"                          -eq 1 ]]
    [[ "$(stub_called_times post_provisioning)"                         -eq 0 ]]
    [[ "$(stub_called_times build_primary_dc_with_backup_file)"         -eq 0 ]]
    [[ "$(stub_called_times build_primary_dc_with_joining_domain)"      -eq 0 ]]
    [[ "$(stub_called_times host)"                                      -eq 1 ]]

    stub_called_with_exactly_times echo 1 "ERROR: Could not get IP from the host name \"rpdc\". [result=256.256.256.256]"
}

@test '#build_dc should return 0 if all processes are succeeded with DC_TYPE=SECONDARY_DC' {
    export DC_TYPE="SECONDARY_DC"
    run build_dc; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times samba-tool)"                                -eq 1 ]]
    [[ "$(stub_called_times echo)"                                      -eq 0 ]]
    [[ "$(stub_called_times pre_provisioning)"                          -eq 1 ]]
    [[ "$(stub_called_times post_provisioning)"                         -eq 1 ]]
    [[ "$(stub_called_times build_primary_dc_with_backup_file)"         -eq 0 ]]
    [[ "$(stub_called_times build_primary_dc_with_joining_domain)"      -eq 0 ]]

    stub_called_with_exactly_times samba-tool 1 "domain" "join" "corp.mysite.example.com" "DC" "-UAdministrator%p@ssword0"
}

@test '#build_dc should return 1 if pre_provisioning was failed' {
    stub_and_eval pre_provisioning '{ return 1; }'
    run build_dc; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times samba-tool)"                                -eq 0 ]]
    [[ "$(stub_called_times echo)"                                      -eq 1 ]]
    [[ "$(stub_called_times pre_provisioning)"                          -eq 1 ]]
    [[ "$(stub_called_times post_provisioning)"                         -eq 0 ]]
    [[ "$(stub_called_times build_primary_dc_with_backup_file)"         -eq 0 ]]
    [[ "$(stub_called_times build_primary_dc_with_joining_domain)"      -eq 0 ]]

    stub_called_with_exactly_times echo 1 "ERROR: Failed to pre_provisioning tasks"
}


@test '#build_dc should return 1 if samba-tool was failed' {
    stub_and_eval samba-tool '{ return 1; }'
    run build_dc; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times samba-tool)"                                -eq 1 ]]
    [[ "$(stub_called_times echo)"                                      -eq 1 ]]
    [[ "$(stub_called_times pre_provisioning)"                          -eq 1 ]]
    [[ "$(stub_called_times post_provisioning)"                         -eq 1 ]]
    [[ "$(stub_called_times build_primary_dc_with_backup_file)"         -eq 0 ]]
    [[ "$(stub_called_times build_primary_dc_with_joining_domain)"      -eq 0 ]]

    stub_called_with_exactly_times echo 1 "ERROR: Failed to \"samba-tool domain provision\"[ret=1]"
}

@test '#build_dc should return 1 if post_provisioning was failed' {
    stub_and_eval post_provisioning '{ return 1; }'
    run build_dc; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times samba-tool)"                                -eq 1 ]]
    [[ "$(stub_called_times echo)"                                      -eq 1 ]]
    [[ "$(stub_called_times pre_provisioning)"                          -eq 1 ]]
    [[ "$(stub_called_times post_provisioning)"                         -eq 1 ]]
    [[ "$(stub_called_times build_primary_dc_with_backup_file)"         -eq 0 ]]
    [[ "$(stub_called_times build_primary_dc_with_joining_domain)"      -eq 0 ]]

    stub_called_with_exactly_times echo 1 "ERROR: Failed to post_provisioning tasks"
}

