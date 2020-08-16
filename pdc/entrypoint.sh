#!/bin/bash

INITIALIZED_FLAG_FILE="/.dc_has_initialized"

# Flag whether need to restore smb.conf after provisioning
FLAG_RESTORE_USERS_SMB_CONF_AFTER_PROV=0


main() {
    init_env_variables || {
        echo "ERROR: Failed to initialize environment variables." >&2
        return 1
    }

    case "$DC_TYPE" in
        "PRIMARY_DC" | "SECONDARY_DC")
            run_dc
            ;;
        "RESTORED_DC")
            # TODO:
            ;;
        *)
            echo "ERROR: Unsupported DC_TYPE environment variable (DC_TYPE=${DC_TYPE}). This program only support \"PRIMARY_DC\", \"SECONDARY_DC\", \"TEMPORARY_DC\" or \"RESTORED_PRIMARY_DC\"" >&2
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

    if [[ ! -z "$RESTORE_WITH" ]]; then
        if [[ "$RESTORE_WITH" == "JOINING_A_DOMAIN" ]] || [[ "$RESTORE_WITH" == "BACKUP_FILE" ]]; then
            if [[ "$DC_TYPE" != "PRIMARY_DC" ]]; then
                echo "ERROR: You can not specify RESTORE_WITH=${RESTORE_WITH} with DC_TYPE=${DC_TYPE}. RESTORE_WITH only support with DC_TYPE=PRIMARY_DC" >&2
                return 1
            fi
        else
            echo "ERROR: Variable RESTORE_WITH=${RESTORE_WITH} does not support. RESTORE_WITH only supports \"JOIN_DOMAIN\" or \"BACKUP_FILE\"." >&2
            return 1
        fi
    fi

    return 0
}

run_dc() {

    if ! is_already_initialized; then
        build_dc

        local ret=$?
        if [[ "$ret" -ne 0 ]]; then
            echo "ERROR: Failed to build dc"
            return 1
        fi

        flag_initialized
    fi

    start_samba
}

build_dc() {
    local ret=0
    local flag_resotre_smb_conf=0

    pre_provisioning || {
        echo "ERROR: Failed to pre_provisioning tasks" >&2
        return 1
    }

    case "$DC_TYPE" in
        "PRIMARY_DC")

            case "$RESTORE_WITH" in
                "BACKUP_FILE" )
                    run_primary_dc_with_backup_file
                    ;;
                "JOIN_DOMAIN" )
                    run_primary_dc_with_joining_a_domain
                    ;;
                * )
                samba-tool domain provision --use-rfc2307 --domain=${DOMAIN} \
                    --realm=${DOMAIN_FQDN^^} --server-role=dc \
                    --dns-backend=SAMBA_INTERNAL --adminpass=${ADMIN_PASSWORD} --host-ip=${CONTAINER_IP}
                ;;
            esac

            ;;
        "SECONDARY_DC")
            samba-tool domain join ${DOMAIN_FQDN,,} DC -U"Administrator"%"${ADMIN_PASSWORD}"
            ;;
        "RESTORED_DC")
            # TODO:
            ;;
        *)
            echo "ERROR: Unsupported DC_TYPE environment variable (DC_TYPE=${DC_TYPE}). This program only support \"PRIMARY_DC\", \"SECONDARY_DC\", \"TEMPORARY_DC\" or \"RESTORED_PRIMARY_DC\"" >&2
            return 1
            ;;
    esac
    local ret_samba_tool=$?

    post_provisioning || {
        echo "ERROR: Failed to post_provisioning tasks" >&2
        return 1
    }

    if [[ $ret_samba_tool -ne 0 ]]; then
        echo "ERROR: Failed to \"samba-tool domain provision\"[ret=${ret_samba_tool}]" >&2
        return 1
    fi

    return 0
}

pre_provisioning() {
    # /etc/krb5.conf and /etc/samba/smb.conf has already removed at creating docker images.
    # If /etc/samba/smb.conf is existed, it is a file mounted by a user.
    if [[ -f "/etc/samba/smb.conf" ]]; then
        mv -f /etc/samba/smb.conf /etc/samba/smb.conf.bak
        local ret=$?

        if [[ $ret -ne 0 ]]; then
            echo "ERROR: Failed to move /etc/samba/smb.conf before running \"samba-tool domain provision\". Provisioning process will be quitted." >&2
            return 1
        fi

        # Set the flag to restore smb.conf after provisioning
        FLAG_RESTORE_USERS_SMB_CONF_AFTER_PROV=1
    fi

    return 0
}

post_provisioning() {
    local ret=0

    if [[ $FLAG_RESTORE_USERS_SMB_CONF_AFTER_PROV -eq 1 ]]; then
        mv -f /etc/samba/smb.conf.bak /etc/samba/smb.conf
        ret=$?

        if [[ $ret -ne 0 ]]; then
            echo "ERROR: Failed to restore smb.conf after running \"samba-tool domain provision\"." >&2
            return 1
        fi
        FLAG_RESTORE_USERS_SMB_CONF_AFTER_PROV=0
    else
        # Change dns forwarder in /etc/samba/smb.conf
        sed -i -e "s/dns forwarder = .*/dns forwarder = ${DNS_FORWARDER}/g" /etc/samba/smb.conf || {
            echo "ERROR: Failed to modify /etc/samba/smb.conf to change \"dns forwarder = ${DNS_FORWARDER}\" after DC has provisioned" >&2
            return 1
        }
    fi

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

