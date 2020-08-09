#!/bin/bash

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
    export DOMAIN_FQDN=${DOMAIN_FQDN:-corp.mysite.example.com}
    [[ -z "$DOMAIN" ]] || export DOMAIN="$(cut -d '.' -f1 <<< "${DOMAIN_FQDN^^}")"
}

run_primary_dc() {

    if do_already_initialized; then
        build_primary_dc || {
            echo "ERROR: Failed to build primary DC due to previous error." >&2
            return 1
        }
    fi

    /usr/sbin/samba -i

}

build_primary_dc() {
    mv /etc/krb5.conf /etc/krb5.conf.org
    mv /etc/samba/smb.conf /etc/samba/smb.conf.org

    samba-tool domain provision --use-rfc2307 --domain=${SAMBA_DOMAIN} \
        --realm=${DOMAIN^^} --server-role=dc \
        --dns-backend=SAMBA_INTERNAL --adminpass=${PASSWD} --host-ip=${IP}

}


main "$@" || exit $?

