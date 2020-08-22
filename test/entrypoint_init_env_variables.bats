#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    #stub export
    stub echo
    stub get_container_ip
}

function teardown() {
    rm -f "$INITIALIZED_FLAG_FILE"
}

@test '#init_env_variables return 0 and set default values if all environment variables were not set' {
    stub_and_eval get_container_ip '{ command echo "172.16.0.2"; }'
    run init_env_variables

    command echo "$output"
    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times echo)"             -eq 4 ]]
    [[ "$(stub_called_times get_container_ip)" -eq 1 ]]

    stub_called_with_exactly_times echo 1 "NOTICE: Environment variable DOMAIN_FQDN was empty." "Set DOMAIN_FQDN=\"corp.mysite.example.com\" by default."
    stub_called_with_exactly_times echo 1 "NOTICE: Environment variable DOMAIN was empty." "Set DOMAIN=\"CORP\" by default."
    stub_called_with_exactly_times echo 1 "NOTICE: Environment variable ADMIN_PASSWORD was empty." "Set ADMIN_PASSWORD=\"p@ssword0\" by default." "You can change it after running samba with" "\"samba-tool user setpassword Administrator --newpassword=new_password -U Administrator\""
    stub_called_with_exactly_times echo 1 "NOTICE: Environment variable DNS_FORWARDER was empty." "Set DNS_FORWARDER=\"8.8.8.8\" by default." "You can change it by editing /etc/samba/smb.conf after provisioned samba"
}

@test '#init_env_variables return 1 if get_container_ip failed to get IP' {
    run init_env_variables

    command echo "$output"
    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times echo)"             -eq 1 ]]
    [[ "$(stub_called_times get_container_ip)" -eq 1 ]]

    stub_called_with_exactly_times echo 1 "ERROR: Attempting get IP from the container because the environment variable CONTAINER_IP was empty but failed."
}

@test '#init_env_variables return 0 if DC_TYPE=PRIMARY_DC and RESTORE_FROM=JOINING_DOMAIN' {
    stub_and_eval get_container_ip '{ command echo "172.16.0.2"; }'
    DC_TYPE="PRIMARY_DC"
    RESTORE_FROM="JOINING_DOMAIN"

    run init_env_variables; command echo "$output"
    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times echo)"             -eq 4 ]]
    [[ "$(stub_called_times get_container_ip)" -eq 1 ]]
}

@test '#init_env_variables return 0 if DC_TYPE=PRIMARY_DC and RESTORE_FROM=BACKUP_FILE' {
    stub_and_eval get_container_ip '{ command echo "172.16.0.2"; }'
    DC_TYPE="PRIMARY_DC"
    RESTORE_FROM="BACKUP_FILE"

    run init_env_variables; command echo "$output"
    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times echo)"             -eq 4 ]]
    [[ "$(stub_called_times get_container_ip)" -eq 1 ]]
}

@test '#init_env_variables return 0 if DC_TYPE=PRIMARY_DC and RESTORE_FROM=<IP>' {
    stub_and_eval get_container_ip '{ command echo "172.16.0.2"; }'
    DC_TYPE="PRIMARY_DC"
    RESTORE_FROM="192.168.1.73"

    run init_env_variables; command echo "$output"
    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times echo)"             -eq 4 ]]
    [[ "$(stub_called_times get_container_ip)" -eq 1 ]]
}

@test '#init_env_variables return 0 if DC_TYPE=PRIMARY_DC and RESTORE_FROM=FOO (Unsupported restore method)' {
    stub_and_eval get_container_ip '{ command echo "172.16.0.2"; }'
    DC_TYPE="PRIMARY_DC"
    RESTORE_FROM="FOO"

    run init_env_variables; command echo "$output"
    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times echo)"             -eq 5 ]]
    [[ "$(stub_called_times get_container_ip)" -eq 1 ]]
    stub_called_with_exactly_times echo 1 "ERROR: Variable RESTORE_FROM=FOO does not support. RESTORE_FROM only supports \"JOINING_DOMAIN\" or \"BACKUP_FILE\"."
}

@test '#init_env_variables return 0 if DC_TYPE=SECONDARY_DC and RESTORE_FROM=JOINING_DOMAIN (Unsupported with SECONDARY_DC)' {
    stub_and_eval get_container_ip '{ command echo "172.16.0.2"; }'
    DC_TYPE="SECONDARY_DC"
    RESTORE_FROM="JOINING_DOMAIN"

    run init_env_variables; command echo "$output"
    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times echo)"             -eq 5 ]]
    [[ "$(stub_called_times get_container_ip)" -eq 1 ]]
    stub_called_with_exactly_times echo 1 "ERROR: You can not specify RESTORE_FROM=JOINING_DOMAIN with DC_TYPE=SECONDARY_DC. RESTORE_FROM only support with DC_TYPE=PRIMARY_DC"
}

@test '#init_env_variables return 0 if all environment variables were already set' {
    DC_TYPE="PRIMARY_DC"
    CONTAINER_IP="172.16.0.2"
    DOMAIN_FQDN="corp.mysite.example.com"
    DOMAIN="CORP"
    ADMIN_PASSWORD="p@ssword0"
    DNS_FORWARDER="192.168.1.1"
    RESTORE_FROM="JOINING_DOMAIN"

    run init_env_variables

    command echo "$output"
    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times echo)"             -eq 0 ]]
    [[ "$(stub_called_times get_container_ip)" -eq 0 ]]
}
