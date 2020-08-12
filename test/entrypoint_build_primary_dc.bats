#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    mkdir -p /etc/samba/
    touch /etc/krb5.conf /etc/samba/smb.conf

    export DOMAIN="CORP"
    export DOMAIN_FQDN="corp.mysite.example.com"
    export ADMIN_PASSWORD="p@ssword0"
    export CONTAINER_IP="172.16.0.2"
    export DNS_FORWARDER="192.168.1.1"

    stub_and_eval mv '{ command mv $@; }'
    stub samba-tool
    stub echo
    stub sed
}

function teardown() {
    unset DOMAIN
    unset DOMAIN_FQDN
    unset ADMIN_PASSWORD
    unset CONTAINER_IP
    unset DNS_FORWARDER
}

@test '#build_primary_dc should return 0 if all processes are succeeded' {
    run build_primary_dc; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times mv)"             -eq 2 ]]
    [[ "$(stub_called_times samba-tool)" -eq 1 ]]
    [[ "$(stub_called_times echo)" -eq 0 ]]
    [[ "$(stub_called_times sed)" -eq 1 ]]

    stub_called_with_exactly_times mv 1 "-f" "/etc/krb5.conf" "/etc/krb5.conf.org"
    stub_called_with_exactly_times mv 1 "-f" "/etc/samba/smb.conf" "/etc/samba/smb.conf.org"
    stub_called_with_exactly_times samba-tool 1 "domain" "provision" "--use-rfc2307" "--domain=CORP" \
                                                "--realm=CORP.MYSITE.EXAMPLE.COM" "--server-role=dc" \
                                                "--dns-backend=SAMBA_INTERNAL" "--adminpass=p@ssword0" "--host-ip=172.16.0.2"
    stub_called_with_exactly_times sed 1 "-i" "-e" "s/dns forwarder = .*/dns forwarder = 192.168.1.1/g" "/etc/samba/smb.conf"
}

@test '#build_primary_dc should return 1 if mv krb5.conf was failed' {
    stub_and_eval mv '{
        [[ "$2" == "/etc/krb5.conf" ]] && return 0;
        command mv $@
    }'
    run build_primary_dc; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times mv)"             -eq 1 ]]
    [[ "$(stub_called_times samba-tool)" -eq 0 ]]
    [[ "$(stub_called_times echo)" -eq 1 ]]
    [[ "$(stub_called_times sed)" -eq 0 ]]

    stub_called_with_exactly_times mv 1 "-f" "/etc/krb5.conf" "/etc/krb5.conf.org"
    stub_called_with_exactly_times echo 1 "ERROR: Failed to delete(move) /etc/krb5.conf before running \"samba-tool domain provision\". Processes following it will be quitted."
}

@test '#build_primary_dc should return 1 if mv smb.conf was failed' {
    stub_and_eval mv '{
        [[ "$2" == "/etc/samba/smb.conf" ]] && return 0;
        command mv $@
    }'
    run build_primary_dc; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times mv)"             -eq 2 ]]
    [[ "$(stub_called_times samba-tool)" -eq 0 ]]
    [[ "$(stub_called_times echo)" -eq 1 ]]
    [[ "$(stub_called_times sed)" -eq 0 ]]

    stub_called_with_exactly_times mv 1 "-f" "/etc/krb5.conf" "/etc/krb5.conf.org"
    stub_called_with_exactly_times mv 1 "-f" "/etc/samba/smb.conf" "/etc/samba/smb.conf.org"
    stub_called_with_exactly_times echo 1 "ERROR: Failed to delete(move) /etc/samba/smb.conf before running \"samba-tool domain provision\". Processes following it will be quitted."
}

@test '#build_primary_dc should return 1 if samba-tool command was failed' {
    stub_and_eval samba-tool '{ return 1; }'
    run build_primary_dc; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times mv)"             -eq 2 ]]
    [[ "$(stub_called_times samba-tool)" -eq 1 ]]
    [[ "$(stub_called_times echo)" -eq 1 ]]
    [[ "$(stub_called_times sed)" -eq 0 ]]

    stub_called_with_exactly_times mv 1 "-f" "/etc/krb5.conf" "/etc/krb5.conf.org"
    stub_called_with_exactly_times mv 1 "-f" "/etc/samba/smb.conf" "/etc/samba/smb.conf.org"
    stub_called_with_exactly_times samba-tool 1 "domain" "provision" "--use-rfc2307" "--domain=CORP" \
                                                "--realm=CORP.MYSITE.EXAMPLE.COM" "--server-role=dc" \
                                                "--dns-backend=SAMBA_INTERNAL" "--adminpass=p@ssword0" "--host-ip=172.16.0.2"
    stub_called_with_exactly_times echo 1 "ERROR: Failed to \"samba-tool domain provision\"[ret=1]."
}

@test '#build_primary_dc should return 1 if sed command was failed' {
    stub_and_eval sed '{ return 1; }'
    run build_primary_dc; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times mv)"             -eq 2 ]]
    [[ "$(stub_called_times samba-tool)" -eq 1 ]]
    [[ "$(stub_called_times echo)" -eq 1 ]]
    [[ "$(stub_called_times sed)" -eq 1 ]]

    stub_called_with_exactly_times mv 1 "-f" "/etc/krb5.conf" "/etc/krb5.conf.org"
    stub_called_with_exactly_times mv 1 "-f" "/etc/samba/smb.conf" "/etc/samba/smb.conf.org"
    stub_called_with_exactly_times samba-tool 1 "domain" "provision" "--use-rfc2307" "--domain=CORP" \
                                                "--realm=CORP.MYSITE.EXAMPLE.COM" "--server-role=dc" \
                                                "--dns-backend=SAMBA_INTERNAL" "--adminpass=p@ssword0" "--host-ip=172.16.0.2"
    stub_called_with_exactly_times sed 1 "-i" "-e" "s/dns forwarder = .*/dns forwarder = 192.168.1.1/g" "/etc/samba/smb.conf"
    stub_called_with_exactly_times echo 1 "ERROR: Failed to modify /etc/samba/smb.conf to change \"dns forwarder = ${DNS_FORWARDER}\" after DC has profisioned"
}

