#!/bin/bash

INITIALIZED_FLAG_FILE="/.ad_has_initialized"

main() {
    init_env_variables || {
        echo "ERROR: Failed to initialize environment variables." >&2
        return 1
    }

    case "$DC_TYPE" in
        "PARIMARY_DC")
            run_primary_dc
            ;;
        "SECONDARY_DC")
            run_secondary_dc
            ;;
        "RESTORED_DC")
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
        export CONTAINER_IP=$(get_container_ip)

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

    if [[ -z "$DNS_FORWARDER" ]]; then
        export DNS_FORWARDER="8.8.8.8"
        echo "NOTICE: Environment variable DNS_FORWARDER was empty." \
                 "Set DNS_FORWARDER=\"8.8.8.8\" by default." \
                 "You can change it by editing /etc/samba/smb.conf after provisioned samba"
    fi

    return 0
}

run_primary_dc() {
    if ! is_already_initialized; then
        if ! build_primary_dc; then
            echo "ERROR: Failed to build primary DC due to previous error." >&2
            return 1
        fi

        flag_initialized
    fi

    start_samba
}

run_secondary_dc() {
    true
}

build_primary_dc() {
    mv -f /etc/krb5.conf /etc/krb5.conf.org
    if [[ -f "/etc/krb5.conf" ]]; then
        echo "ERROR: Failed to delete(move) /etc/krb5.conf before running \"samba-tool domain provision\". Processes following it will be quitted." >&2
        return 1
    fi

    mv -f /etc/samba/smb.conf /etc/samba/smb.conf.org    # This will overwrite smb.conf.org if it is already existed
    if [[ -f "/etc/samba/smb.conf" ]]; then
        echo "ERROR: Failed to delete(move) /etc/samba/smb.conf before running \"samba-tool domain provision\". Processes following it will be quitted." >&2
        return 1
    fi

    samba-tool domain provision --use-rfc2307 --domain=${DOMAIN} \
        --realm=${DOMAIN_FQDN^^} --server-role=dc \
        --dns-backend=SAMBA_INTERNAL --adminpass=${ADMIN_PASSWORD} --host-ip=${CONTAINER_IP}

    local ret=$?

    if [[ $ret -ne 0 ]]; then
        echo "ERROR: Failed to \"samba-tool domain provision\"[ret=${ret}]." >&2
        return 1
    fi

    # Change dns forwarder in /etc/samba/smb.conf
    sed -i -e "s/dns forwarder = .*/dns forwarder = ${DNS_FORWARDER}/g" /etc/samba/smb.conf || {
        echo "ERROR: Failed to modify /etc/samba/smb.conf to change \"dns forwarder = ${DNS_FORWARDER}\" after DC has profisioned" >&2
        return 1
    }

    return 0
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

get_container_ip() {
    ip add show | grep -E '^\s+inet .* scope global .*' | awk '{print $2}' | cut -d '/' -f 1 | tail -1
}

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    main "$@"
    exit $?
fi

