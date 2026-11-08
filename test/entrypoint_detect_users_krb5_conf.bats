#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    KRB5_CONF_FILE="$(mktemp -u)"
}

function teardown() {
    rm -f "$KRB5_CONF_FILE"
}

@test '#detect_users_krb5_conf should set FLAG_USERS_KRB5_CONF=1 if krb5.conf exists' {
    touch "$KRB5_CONF_FILE"
    detect_users_krb5_conf > /dev/null

    [[ "$FLAG_USERS_KRB5_CONF" -eq 1 ]]
}

@test '#detect_users_krb5_conf should keep FLAG_USERS_KRB5_CONF=0 if krb5.conf does not exist' {
    detect_users_krb5_conf > /dev/null

    [[ "$FLAG_USERS_KRB5_CONF" -eq 0 ]]
}

@test '#detect_users_krb5_conf should print a message if krb5.conf exists' {
    touch "$KRB5_CONF_FILE"
    run detect_users_krb5_conf

    [[ "$status" -eq 0 ]]
    [[ "$output" == "INFO: ${KRB5_CONF_FILE} exists. It is assumed to be mounted by a user and will not be modified." ]]
}
