#!/bin/bash

INITIALIZED_FLAG_FILE="/.initialized"

main() {
    echo "$FOO" > /var/tmp/result.txt
    tail -f /dev/null

    init_env_variables || {
        echo "ERROR: Failed to initialize environment variables." >&2
        return 1
    }

    case "$DC_TYPE" in
        "PARIMARY_DC")
            run_primary_dc
            ;;
        "SECONDARY_DC")
            # TODO:
            ;;
        "TEMPORARY_DC")
            # TODO:
            ;;
        "RESTORED_PRIMARY_DC")
            # TODO:
            ;;
        *)
            echo "ERROR: Unsupported DC_TYPE environment variable (DC_TYPE=${DC_TYPE}). This program only support \"PARIMARY_DC\", \"SECONDARY_DC\", \"TEMPORARY_DC\" or \"RESTORED_PRIMARY_DC\"" >&2
            return 1
            ;;
    esac
}

init_env_variables() {
    if [[ -z "$CONTAINER_IP" ]]; then
        export CONTAINER_IP=$(ip add show | grep -E '^\s+inet .* scope global .*' | awk '{print $2}' | cut -d '/' -f 1)

        if [[ ! "$CONTAINER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "ERROR: Attempting get IP from the container because the environment variable CONTAINER_IP was empty but failed." >&2
            return 1
        fi
    fi

    if [[ -z "$DOMAIN_FQDN" ]]; then
        export DOMAIN_FQDN=${DOMAIN_FQDN:-corp.mysite.example.com}
        echo "NOTICE: Environment variable DOMAIN_FQDN was empty." \
                 "Set DOMAIN_FQDN=\"corp.mysite.example.com\" by default."
    fi

    if [[ -z "$DOMAIN" ]]; then
        export DOMAIN="$(cut -d '.' -f1 <<< "${DOMAIN_FQDN^^}")"
        echo "NOTICE: Environment variable DOMAIN was empty." \
                 "Set DOMAIN=\"${DOMAIN}\" by default."
    fi

    if [[ -z "$ADMIN_PASSWORD" ]]; then
        export ADMIN_PASSWORD="p@ssword0"
        echo "NOTICE: Environment variable ADMIN_PASSWORD was empty." \
                 "Set ADMIN_PASSWORD=\"p@ssword0\" by default." \
                 "You can change it after running samba with" \
                 "\"samba-tool user setpassword Administrator --newpassword=new_password -U Administrator\""
    fi
}

run_primary_dc() {
    if is_already_initialized; then
        if ! build_primary_dc; then
            echo "ERROR: Failed to build primary DC due to previous error." >&2
            return 1
        fi

        do_initialized
    fi

    start_samba
}

build_primary_dc() {
    mv /etc/krb5.conf /etc/krb5.conf.org
    mv /etc/samba/smb.conf /etc/samba/smb.conf.org

    samba-tool domain provision --use-rfc2307 --domain=${DOMAIN} \
        --realm=${DOMAIN_FQDN^^} --server-role=dc \
        --dns-backend=SAMBA_INTERNAL --adminpass=${ADMIN_PASSWORD} --host-ip=${CONTAINER_IP}

}

start_samba() {
    exec /usr/sbin/samba -i
}

is_already_initialized() {
    [[ -f "$INITIALIZED_FLAG_FILE" ]]
}

flag_initialized() {
    touch "$INITIALIZED_FLAG_FILE"
}

main "$@" || exit $?

