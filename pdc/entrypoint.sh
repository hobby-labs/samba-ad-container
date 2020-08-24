#!/bin/bash

INITIALIZED_FLAG_FILE="/.dc_has_initialized"

# Flag whether need to restore smb.conf after provisioning
FLAG_RESTORE_USERS_SMB_CONF_AFTER_PROV=0

# Regex of the IP from here https://stackoverflow.com/a/13778973/4307818
REG_IP='^(0*(1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))\.){3}0*(1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))$'

main() {
    init_env_variables || {
        echo "ERROR: Failed to initialize environment variables." >&2
        return 1
    }

    case "$DC_TYPE" in
        "PRIMARY_DC" | "SECONDARY_DC")
            run_dc
            ;;
        *)
            echo "ERROR: Unsupported DC_TYPE environment variable (DC_TYPE=${DC_TYPE}). This program only support \"PRIMARY_DC\" or \"SECONDARY_DC\"" >&2
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

    if [[ ! -z "$RESTORE_FROM" ]]; then
        if [[ "$RESTORE_FROM" == "JOINING_DOMAIN" ]] || [[ "$RESTORE_FROM" == "BACKUP_FILE" ]] || [[ "$RESTORE_FROM" =~ $REG_IP ]]; then
            # RESTORE_FROM allows "JOINING_DOMAIN", "BACKUP_FILE" or IP
            if [[ "$DC_TYPE" != "PRIMARY_DC" ]]; then
                echo "ERROR: You can not specify RESTORE_FROM=${RESTORE_FROM} with DC_TYPE=${DC_TYPE}. RESTORE_FROM only support with DC_TYPE=PRIMARY_DC" >&2
                return 1
            fi
        else
            echo "ERROR: Variable RESTORE_FROM=${RESTORE_FROM} does not support. RESTORE_FROM only supports \"JOINING_DOMAIN\" or \"BACKUP_FILE\"." >&2
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

            case "$RESTORE_FROM" in
                "BACKUP_FILE" )
                    build_primary_dc_with_backup_file
                    ;;
                "JOINING_DOMAIN" )
                    local dns_ip=$(host rpdc | rev | cut -d' ' -f1 | rev)
                    if [[ ! "$dns_ip" =~ $REG_IP ]]; then
                        echo "ERROR: Could not get IP from the host name \"rpdc\". [result=${dns_ip}]" >&2
                        return 1
                    fi

                    build_primary_dc_with_joining_domain $dns_ip
                    ;;
                "" )
                    # Run a primary DC from scratch. 
                    samba-tool domain provision --use-rfc2307 --domain=${DOMAIN} \
                        --realm=${DOMAIN_FQDN^^} --server-role=dc \
                        --dns-backend=SAMBA_INTERNAL --adminpass=${ADMIN_PASSWORD} --host-ip=${CONTAINER_IP}

                    ;;
                * )
                    # RESTORE_FROM assumed to be IP. It is promised by init_env_variables()
                    build_primary_dc_with_joining_domain $RESTORE_FROM
                    ;;
            esac

            ;;
        "SECONDARY_DC")
            samba-tool domain join ${DOMAIN_FQDN,,} DC -U"Administrator"%"${ADMIN_PASSWORD}"
            ;;
        *)
            echo "ERROR: Unsupported DC_TYPE environment variable (DC_TYPE=${DC_TYPE}). This program only support \"PRIMARY_DC\" or \"SECONDARY_DC\"" >&2
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

build_primary_dc_with_backup_file() {
   local latest_backup_file="$(find /backup -maxdepth 1 -mindepth 1 -type f -regextype posix-extended -regex '.*/samba\-backup\-.*\.tar\.bz2$' | sort -r | head -1)"
   if [[ -z "$latest_backup_file" ]]; then
       #echo "ERROR: Failed to find backup file in /backup directory." \
       #     "Are you sure to have mounted the directory /backup that contains backup file?" \
       #     "Or you mounted it same as an original name of the backup file?" \
       #     "This program search with it the name samba-backup-*.tar.bz2" >&2

       echo "ERROR: Failed to find backup file in /backup directory." \
            "Are you sure to have mounted the directory /backup that contains backup file?" \
            "Or you mounted it same as an original name of the backup file?" \
            "This program search with it the name samba-backup-*.tar.bz2" >&2
       return 1
   fi

   samba-tool domain backup restore \
            --backup-file=${latest_backup_file} \
            --newservername=$(uname -n) --targetdir=/var/lib/restored_samba || {
        echo "ERROR: Failed to restore from the local backup file with --backup-file=${latest_backup_file}" >&2
        return 1
   }

   return 0
}

build_primary_dc_with_joining_domain() {
    local dns_ip="$1"

    change_ip_of_dns "$dns_ip" || return 1
    join_domain || return 1

    # Move roles to this host
    samba-tool fsmo transfer --role=all -U Administrator%${ADMIN_PASSWORD} || {
        echo "ERROR: Failed to transfer fsmo from DC $dns_ip" >&2
        return 1
    }

    restore_dns || return 1

    return 0
}

change_ip_of_dns() {
    local dns_ip="$1"

    cp -f /etc/resolv.conf /etc/resolv.conf.org || {
        echo "ERROR: Failed to backup /etc/resolv.conf to /etc/resolv.conf.org" >&2
        return 1
    }

    echo "nameserver $dns_ip" > /etc/resolv.conf || {
        echo "ERROR: Failed to overwrite /etc/resolv.conf by \"nameserver $dns_ip\"" >&2
        return 1
    }
    sync

    return 0
}

restore_dns() {
    if [[ ! -f "/etc/resolv.conf.org" ]]; then
        echo "INFO: Backup file /etc/resolv.conf.org does not exist. Restoring process will be skipped"
        return 0
    fi

    cp -f /etc/resolv.conf.org /etc/resolv.conf || {
        echo "ERROR: Failed to restore resolv.conf. Copying file /etc/resolv.conf.org to /etc/resolv.conf has failed" >&2
        return 1
    }

    return 0
}

join_domain() {
    samba-tool domain join ${DOMAIN_FQDN,,} DC -U"Administrator"%"${ADMIN_PASSWORD}" || {
        echo "ERROR: Failed to join the domain \"${DOMAIN_FQDN,,}\" with samba-tool" >&2
        return 1
    }

    return 0
}

pre_provisioning() {

    if [[ "${DC_TYPE}" == "SECONDARY_DC" ]] || \
            ( [[ "${DC_TYPE}" == "PRIMARY_DC" ]] && ( [[ "$RESTORE_FROM" == "JOINING_DOMAIN" ]] || [[ "$RESTORE_FROM" =~ $REG_IP ]] ) ); then
        prepare_krb5_conf || return 1
    fi

    # There no instructions when restore-phase.
    [[ ! -z "$RESTORE_FROM" ]] && return 0

    # /etc/krb5.conf and /etc/samba/smb.conf has already removed at creating docker images.
    # If /etc/samba/smb.conf is existed, it is a file mounted by a user.
    if [[ -f "/etc/samba/smb.conf" ]]; then
        mv -f /etc/samba/smb.conf /etc/samba/smb.conf.bak
        local ret=$?

        if [[ $ret -ne 0 ]]; then
            echo "ERROR: Failed to move /etc/samba/smb.conf before running \"samba-tool domain provision\". Provisioning process will be quitted" >&2
            return 1
        fi

        # Set the flag to restore smb.conf after provisioning
        FLAG_RESTORE_USERS_SMB_CONF_AFTER_PROV=1
    fi

    # Edit /etc/hosts
    prepare_hosts || return 1

    return 0
}

prepare_krb5_conf() {
    local tab=$'\t'
    cat << EOF > /etc/krb5.conf
[libdefaults]
${tab}default_realm = ${DOMAIN_FQDN}
${tab}dns_lookup_realm = false
${tab}dns_lookup_kdc = true
EOF

    return 0
}

prepare_hosts() {
    local reg_container_ip=$(sed -e 's/\./\\./g' <<< "$CONTAINER_IP")

    sed -i -e "s/${reg_container_ip} .*/${CONTAINER_IP} ${HOSTNAME} ${HOSTNAME}.${DOMAIN_FQDN,,}/g" /etc/hosts

    grep -q -E "^${reg_container_ip} .*" /etc/hosts || {
        echo "ERROR: Failed to edit /etc/hosts. Could not add hosts information of ${HOSTNAME} ${HOSTNAME}.${DOMAIN_FQDN,,}" >&2
        return 1
    }

    return 0
}

post_provisioning() {
    local ret=0

    set_winbind_to_nsswitch || return 1

    # There no other instructions when restore-phase.
    [[ ! -z "$RESTORE_FROM" ]] && return 0

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

set_winbind_to_nsswitch() {
    grep -q -E '^passwd:.* winbind( .*)?$' /etc/nsswitch.conf || {
        sed -i -e 's/^passwd:\(.*\)/passwd:\1 winbind/' /etc/nsswitch.conf

        grep -q -E '^passwd:.* winbind( .*)?$' /etc/nsswitch.conf || {
            echo "ERROR: Failed to add winbind at line of passwd in /etc/nsswitch.conf" >&2
            return 1
        }
    }

    grep -q -E '^group:.* winbind( .*)?$' /etc/nsswitch.conf || {
        sed -i -e 's/^group:\(.*\)/group:\1 winbind/' /etc/nsswitch.conf

        grep -q -E '^group:.* winbind( .*)?$' /etc/nsswitch.conf || {
            echo "ERROR: Failed to add winbind at line of group in /etc/nsswitch.conf" >&2
            return 1
        }
    }

    return 0
}

start_samba() {
    if [[ "$RESTORE_FROM" == "BACKUP_FILE" ]]; then
        exec /usr/sbin/samba -i -s /var/lib/restored_samba/etc/smb.conf
    else
        exec /usr/sbin/samba -i
    fi
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

