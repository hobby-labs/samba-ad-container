#!/usr/bin/env bash
#
# Smoke test for samba-ad-container.
# Builds the image (pdc/Dockerfile), runs real DCs on a dedicated docker bridge
# network, and checks that the AD services work. Scenarios follow README.md.
#
# Usage: test/smoke/run.sh
#
# Scenarios:
#   basic           Primary DC from scratch, then a secondary DC joins the domain
#   backup_restore  "Backup PDC" / "Restore PDC" in README.md:
#                   online backup -> lose PDC -> restore rpdc from the backup file
#                   (RESTORE_FROM=BACKUP_FILE) -> rebuild pdc01 by joining the domain
#                   (RESTORE_FROM=JOINING_DOMAIN) -> remove rpdc
#   volume_restore  "Backup/Restore PDC (Unofficial way)" in README.md:
#                   recreate the PDC container with persisted /etc/samba and /var/lib/samba
#
# Environment variables:
#   IMAGE          Image tag to build/test           (default: samba-ad-container:smoke)
#   SKIP_BUILD     Set to 1 to skip "docker build"    (default: 0)
#   KEEP           Set to 1 to keep containers, volumes and network after the test (default: 0)
#   SUBNET_PREFIX  First 3 octets of the test network (default: 172.30.99)
#   SCENARIOS      Space separated scenarios to run   (default: "basic backup_restore volume_restore")

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

IMAGE="${IMAGE:-samba-ad-container:smoke}"
SKIP_BUILD="${SKIP_BUILD:-0}"
KEEP="${KEEP:-0}"
SUBNET_PREFIX="${SUBNET_PREFIX:-172.30.99}"
SCENARIOS="${SCENARIOS:-basic backup_restore volume_restore}"

NETWORK="samba-ad-smoke"
PDC_NAME="smoke-pdc01"
PDC_HOST="pdc01"
PDC_IP="${SUBNET_PREFIX}.11"
BDC_NAME="smoke-bdc01"
BDC_HOST="bdc01"
BDC_IP="${SUBNET_PREFIX}.12"
RPDC_NAME="smoke-rpdc"
RPDC_HOST="rpdc"            # entrypoint.sh requires the name "rpdc" for restoring
RPDC_IP="${SUBNET_PREFIX}.13"
VOLUME_ETC="samba-ad-smoke-etc-samba"
VOLUME_LIB="samba-ad-smoke-var-lib-samba"
ALL_CONTAINERS=("$PDC_NAME" "$BDC_NAME" "$RPDC_NAME")
ALL_VOLUMES=("$VOLUME_ETC" "$VOLUME_LIB")

DOMAIN_FQDN="corp.smoke.example.com"
REALM="${DOMAIN_FQDN^^}"
DOMAIN="CORP"
BASE_DN="DC=corp,DC=smoke,DC=example,DC=com"
ADMIN_PASSWORD='Sm0ke-Adm1n!pass'
TEST_USER="smokeuser"
TEST_PASSWORD='Sm0ke-Us3r!pass'

BACKUP_DIR=""
PASSED=0
FAILED=0
FAILED_SCENARIOS=()

log()  { printf '\n==> %s\n' "$*"; }
pass() { printf '  [PASS] %s\n' "$*"; PASSED=$((PASSED + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAILED=$((FAILED + 1)); }

# Escape "." for regex
re() { printf '%s' "${1//./\\.}"; }

# check <description> <command...>
check() {
    local desc="$1"; shift
    local out
    if out="$("$@" 2>&1)"; then
        pass "$desc"
    else
        fail "$desc"
        printf '%s\n' "$out" | sed 's/^/         | /' | tail -20
    fi
}

# check_output <description> <regex> <command...>
check_output() {
    local desc="$1" regex="$2"; shift 2
    local out
    out="$("$@" 2>&1)"
    if grep -qE -- "$regex" <<< "$out"; then
        pass "$desc"
    else
        fail "$desc (expected /${regex}/)"
        printf '%s\n' "$out" | sed 's/^/         | /' | tail -20
    fi
}

# check_no_output <description> <regex> <command...>
check_no_output() {
    local desc="$1" regex="$2"; shift 2
    local out
    out="$("$@" 2>&1)"
    if ! grep -qE -- "$regex" <<< "$out"; then
        pass "$desc"
    else
        fail "$desc (unexpected /${regex}/)"
        printf '%s\n' "$out" | sed 's/^/         | /' | tail -20
    fi
}

remove_containers() {
    docker rm -f "${ALL_CONTAINERS[@]}" > /dev/null 2>&1
}

remove_volumes() {
    docker volume rm -f "${ALL_VOLUMES[@]}" > /dev/null 2>&1
}

cleanup() {
    if [[ "$KEEP" == "1" ]]; then
        log "KEEP=1: leaving containers, volumes, network ${NETWORK} and backup dir ${BACKUP_DIR:-(none)}"
        return
    fi
    log "Cleaning up"
    remove_containers
    remove_volumes
    docker network rm "$NETWORK" > /dev/null 2>&1
    [[ -n "$BACKUP_DIR" ]] && rm -rf "$BACKUP_DIR"
}

# start_dc <container> <hostname> <ip> [<extra docker run args>...]
# Common options for all DCs. Extra args are inserted before the image name.
start_dc() {
    local name="$1" host="$2" ip="$3"; shift 3
    docker run -d --name "$name" --hostname "$host" \
        -e DOMAIN_FQDN="$DOMAIN_FQDN" \
        -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
        --network "$NETWORK" --ip "$ip" \
        --privileged \
        "$@" \
        "$IMAGE" > /dev/null
}

# wait_for_dc <container> <timeout_sec>
wait_for_dc() {
    local name="$1" timeout="$2" i
    for ((i = 0; i < timeout; i += 2)); do
        if [[ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" != "true" ]]; then
            echo "Container ${name} is not running" >&2
            return 1
        fi
        # * /.dc_has_initialized: entrypoint.sh has finished building the DC
        #   (samba is also started temporarily while restoring, e.g. to transfer FSMO)
        # * "samba-tool domain info" (CLDAP) can answer before the LDAP listener is ready,
        #   so wait for both.
        docker exec "$name" test -f /.dc_has_initialized > /dev/null 2>&1 && \
            docker exec "$name" samba-tool domain info 127.0.0.1 > /dev/null 2>&1 && \
            docker exec "$name" ldapsearch -H ldap://127.0.0.1 -x -b '' -s base defaultNamingContext > /dev/null 2>&1 && \
            return 0
        sleep 2
    done
    echo "Timed out after ${timeout}s waiting for ${name}" >&2
    return 1
}

# start_and_wait <description> <timeout> <container> <hostname> <ip> [<extra docker run args>...]
start_and_wait() {
    local desc="$1" timeout="$2" name="$3"; shift 2
    start_dc "$@" || { fail "$desc (docker run)"; return 1; }
    if ! wait_for_dc "$name" "$timeout"; then
        fail "$desc"
        dump_logs "$name"
        return 1
    fi
    pass "$desc"
}

dump_logs() {
    printf '%s\n' "----- docker logs $1 (last 50 lines) -----"
    docker logs --tail 50 "$1" 2>&1 | sed 's/^/  | /'
}

# Run a command in a container with Kerberos configured from the provisioned krb5.conf.
# (The image removes /etc/krb5.conf; samba generates krb5.conf under its private dir.)
# kexec <container> <krb5.conf> <command...>
kexec() {
    local name="$1" krb5_conf="$2"; shift 2
    docker exec -e KRB5_CONFIG="$krb5_conf" "$name" "$@"
}

# check_kinit <description> <container> <krb5.conf> <user> <password>
check_kinit() {
    local desc="$1" name="$2" krb5_conf="$3" user="$4" password="$5"
    check_output "$desc" "Default principal: ${user}@${REALM}" \
        kexec "$name" "$krb5_conf" bash -c "echo '${password}' | kinit ${user}@${REALM} > /dev/null && klist"
}

# samba-tool over LDAP with Administrator credentials. Useful for a DC which runs with
# a non-default smb.conf (restored DC). "-d0" suppresses debug output by "log level".
# st_ldap <container> <ip> <samba-tool args...>
st_ldap() {
    local name="$1" ip="$2"; shift 2
    docker exec "$name" samba-tool "$@" -H "ldap://${ip}" -U "Administrator%${ADMIN_PASSWORD}" -d0
}

# get_domain_sid <container>
get_domain_sid() {
    docker exec "$1" wbinfo -D "$DOMAIN" 2>/dev/null | awk -F': ' '/^SID/{print $2}'
}

# --------------------------------------------------------------------------- scenarios

scenario_basic() {
    # ---------------------------------------------------------------- PDC
    log "[basic] Starting primary DC ${PDC_NAME} (${PDC_IP})"
    start_and_wait "Primary DC came up" 180 \
        "$PDC_NAME" "$PDC_HOST" "$PDC_IP" -e DC_TYPE="PRIMARY_DC" --dns "$PDC_IP" || return 1

    log "[basic] Checking primary DC"
    check_output "Samba version"                    'Version 4\.' \
        docker exec "$PDC_NAME" samba --version
    check_output "smb.conf has dns forwarder"       '^\s*dns forwarder = 8\.8\.8\.8' \
        docker exec "$PDC_NAME" cat /etc/samba/smb.conf
    check_output "smb.conf has log level"           '^\s*log level = 5' \
        docker exec "$PDC_NAME" cat /etc/samba/smb.conf
    check_output "/etc/hosts has FQDN"              "^$(re "$PDC_IP") ${PDC_HOST} ${PDC_HOST}\.$(re "$DOMAIN_FQDN")" \
        docker exec "$PDC_NAME" cat /etc/hosts
    check_output "nsswitch passwd uses winbind"     '^passwd:.* winbind' \
        docker exec "$PDC_NAME" cat /etc/nsswitch.conf
    check_output "Domain function level"            'Domain function level' \
        docker exec "$PDC_NAME" samba-tool domain level show -d0
    check_output "DNS SRV _ldap._tcp"               "has SRV record .* ${PDC_HOST}\.$(re "$DOMAIN_FQDN")" \
        docker exec "$PDC_NAME" host -t SRV "_ldap._tcp.${DOMAIN_FQDN}" "$PDC_IP"
    check_output "DNS SRV _kerberos._udp"           'has SRV record' \
        docker exec "$PDC_NAME" host -t SRV "_kerberos._udp.${DOMAIN_FQDN}" "$PDC_IP"
    check_output "DNS A record of PDC"              "has address $(re "$PDC_IP")" \
        docker exec "$PDC_NAME" host -t A "${PDC_HOST}.${DOMAIN_FQDN}" "$PDC_IP"
    check_output "DNS forwarder resolves external"  'has (IPv6 )?address' \
        docker exec "$PDC_NAME" host -W 5 example.com "$PDC_IP"
    check_output "LDAP rootDSE"                     "defaultNamingContext: ${BASE_DN}" \
        docker exec "$PDC_NAME" ldapsearch -H "ldap://${PDC_IP}" -x -b '' -s base defaultNamingContext
    check "Create user ${TEST_USER}" \
        docker exec "$PDC_NAME" samba-tool user create "$TEST_USER" "$TEST_PASSWORD" -d0
    check_output "SMB shares (sysvol/netlogon)"     'netlogon' \
        docker exec "$PDC_NAME" smbclient -L "$PDC_IP" -U "${TEST_USER}%${TEST_PASSWORD}"
    check_kinit "Kerberos kinit as ${TEST_USER}" \
        "$PDC_NAME" /var/lib/samba/private/krb5.conf "$TEST_USER" "$TEST_PASSWORD"
    check_output "winbind lists users"              "${DOMAIN}\\\\${TEST_USER}" \
        docker exec "$PDC_NAME" wbinfo -u
    check_output "getent resolves domain user"      "^${DOMAIN}\\\\${TEST_USER}:" \
        docker exec "$PDC_NAME" getent passwd "${DOMAIN}\\${TEST_USER}"

    # ---------------------------------------------------------------- BDC
    log "[basic] Starting secondary DC ${BDC_NAME} (${BDC_IP})"
    start_and_wait "Secondary DC joined and came up" 300 \
        "$BDC_NAME" "$BDC_HOST" "$BDC_IP" -e DC_TYPE="SECONDARY_DC" --dns "$PDC_IP" || return 1

    log "[basic] Checking secondary DC"
    check_output "BDC is listed as a DC on PDC"     "^${BDC_HOST^^}\\\$" \
        docker exec "$PDC_NAME" samba-tool group listmembers "Domain Controllers" -d0
    check_output "User replicated to BDC"           "^${TEST_USER}$" \
        st_ldap "$BDC_NAME" "$BDC_IP" user list
    check_output "DRS replication from PDC"         'Last attempt .* was successful' \
        docker exec "$BDC_NAME" samba-tool drs showrepl -U "Administrator%${ADMIN_PASSWORD}" -d0
    check_kinit "Kerberos kinit against BDC" \
        "$BDC_NAME" /var/lib/samba/private/krb5.conf "$TEST_USER" "$TEST_PASSWORD"
}

scenario_backup_restore() {
    local backup_file

    # ---------------------------------------------------------------- backup
    log "[backup_restore] Starting primary DC ${PDC_NAME} (${PDC_IP}) and creating data"
    start_and_wait "Primary DC came up" 180 \
        "$PDC_NAME" "$PDC_HOST" "$PDC_IP" -e DC_TYPE="PRIMARY_DC" --dns "$PDC_IP" || return 1
    check "Create user ${TEST_USER}" \
        docker exec "$PDC_NAME" samba-tool user create "$TEST_USER" "$TEST_PASSWORD" -d0

    log "[backup_restore] Backup PDC (samba-tool domain backup online)"
    check "samba-tool domain backup online" \
        docker exec "$PDC_NAME" samba-tool domain backup online --targetdir=/var/tmp \
            --server=127.0.0.1 -U "Administrator%${ADMIN_PASSWORD}" -d0
    backup_file="$(docker exec "$PDC_NAME" sh -c 'ls /var/tmp/samba-backup-*.tar.bz2' 2>/dev/null | head -1)"
    if [[ -z "$backup_file" ]] || ! docker cp "${PDC_NAME}:${backup_file}" "${BACKUP_DIR}/" > /dev/null; then
        fail "Copy backup file from PDC"
        return 1
    fi
    pass "Copy backup file from PDC ($(basename "$backup_file"))"

    log "[backup_restore] Losing primary DC ${PDC_NAME}"
    docker rm -f "$PDC_NAME" > /dev/null

    # ---------------------------------------------------------------- rpdc
    log "[backup_restore] Restoring temporary PDC ${RPDC_NAME} (${RPDC_IP}) from the backup file"
    # "--network-alias rpdc" lets docker DNS resolve "rpdc" as "--name rpdc" in README.md does.
    start_and_wait "rpdc restored from backup file and came up" 300 \
        "$RPDC_NAME" "$RPDC_HOST" "$RPDC_IP" --network-alias "$RPDC_HOST" \
        -e DC_TYPE="PRIMARY_DC" -e RESTORE_FROM="BACKUP_FILE" \
        --dns "$RPDC_IP" --volume "${BACKUP_DIR}:/backup:ro" || return 1

    log "[backup_restore] Checking rpdc"
    # (samba overwrites its process title, so "-s <smb.conf>" can not be checked from cmdline)
    check "Restored DB exists in /var/lib/restored_samba" \
        docker exec "$RPDC_NAME" test -f /var/lib/restored_samba/etc/smb.conf -a -f /var/lib/restored_samba/private/sam.ldb
    check_output "User restored on rpdc"            "^${TEST_USER}$" \
        st_ldap "$RPDC_NAME" "$RPDC_IP" user list
    check_output "rpdc is the only DC"              "^RPDC\\\$$" \
        st_ldap "$RPDC_NAME" "$RPDC_IP" group listmembers "Domain Controllers"
    check_no_output "Old PDC was removed from DCs"  "^${PDC_HOST^^}\\\$" \
        st_ldap "$RPDC_NAME" "$RPDC_IP" group listmembers "Domain Controllers"
    check_output "rpdc owns PDC emulator role"      "PdcEmulationMasterRole owner: CN=NTDS Settings,CN=RPDC," \
        st_ldap "$RPDC_NAME" "$RPDC_IP" fsmo show
    check_output "DNS SRV _ldap._tcp on rpdc"       "has SRV record .* ${RPDC_HOST}\.$(re "$DOMAIN_FQDN")" \
        docker exec "$RPDC_NAME" host -t SRV "_ldap._tcp.${DOMAIN_FQDN}" "$RPDC_IP"
    check_kinit "Kerberos kinit against rpdc" \
        "$RPDC_NAME" /var/lib/restored_samba/private/krb5.conf "$TEST_USER" "$TEST_PASSWORD"

    # ---------------------------------------------------------------- pdc01
    log "[backup_restore] Restoring ${PDC_NAME} (${PDC_IP}) by joining the domain from rpdc"
    start_and_wait "pdc01 joined the domain, took over FSMO and came up" 300 \
        "$PDC_NAME" "$PDC_HOST" "$PDC_IP" \
        -e DC_TYPE="PRIMARY_DC" -e RESTORE_FROM="JOINING_DOMAIN" \
        --dns "$PDC_IP" --dns "$RPDC_IP" || return 1

    log "[backup_restore] Checking restored pdc01"
    check_output "pdc01 owns all 7 FSMO roles"      '^7$' \
        bash -c "docker exec '$PDC_NAME' samba-tool fsmo show -d0 | grep -c 'owner: CN=NTDS Settings,CN=${PDC_HOST^^},'"
    check_output "pdc01 is the only DC"             "^${PDC_HOST^^}\\\$$" \
        docker exec "$PDC_NAME" samba-tool group listmembers "Domain Controllers" -d0
    check_no_output "rpdc was demoted"              '^RPDC\$' \
        docker exec "$PDC_NAME" samba-tool group listmembers "Domain Controllers" -d0
    check_output "DNS record of rpdc was removed"   'NXDOMAIN' \
        docker exec "$PDC_NAME" host -t A "${RPDC_HOST}.${DOMAIN_FQDN}" "$PDC_IP"
    check_no_output "resolv.conf was restored"      "^nameserver $(re "$RPDC_IP")$" \
        docker exec "$PDC_NAME" cat /etc/resolv.conf
    check_output "User exists on pdc01"             "^${TEST_USER}$" \
        docker exec "$PDC_NAME" samba-tool user list -d0
    check_output "dbcheck reports no errors"        '\(0 errors\)' \
        docker exec "$PDC_NAME" samba-tool dbcheck -d0

    log "[backup_restore] Removing rpdc"
    docker rm -f "$RPDC_NAME" > /dev/null

    log "[backup_restore] Checking pdc01 without rpdc"
    check_output "DNS SRV _ldap._tcp on pdc01"      "has SRV record .* ${PDC_HOST}\.$(re "$DOMAIN_FQDN")" \
        docker exec "$PDC_NAME" host -t SRV "_ldap._tcp.${DOMAIN_FQDN}" "$PDC_IP"
    check_output "SMB shares on pdc01"              'netlogon' \
        docker exec "$PDC_NAME" smbclient -L "$PDC_IP" -U "${TEST_USER}%${TEST_PASSWORD}"
    check_kinit "Kerberos kinit against pdc01" \
        "$PDC_NAME" /var/lib/samba/private/krb5.conf "$TEST_USER" "$TEST_PASSWORD"
    check "Create a new user on pdc01 (RID pool works)" \
        docker exec "$PDC_NAME" samba-tool user create "${TEST_USER}2" "$TEST_PASSWORD" -d0
}

scenario_volume_restore() {
    local sid_before sid_after
    local volumes=(--volume "${VOLUME_ETC}:/etc/samba" --volume "${VOLUME_LIB}:/var/lib/samba")

    log "[volume_restore] Starting primary DC ${PDC_NAME} (${PDC_IP}) with volumes"
    start_and_wait "Primary DC with volumes came up" 180 \
        "$PDC_NAME" "$PDC_HOST" "$PDC_IP" -e DC_TYPE="PRIMARY_DC" --dns "$PDC_IP" "${volumes[@]}" || return 1
    check "Create user ${TEST_USER}" \
        docker exec "$PDC_NAME" samba-tool user create "$TEST_USER" "$TEST_PASSWORD" -d0
    sid_before="$(get_domain_sid "$PDC_NAME")"

    log "[volume_restore] Recreating ${PDC_NAME} with the same volumes"
    docker rm -f "$PDC_NAME" > /dev/null
    start_and_wait "Recreated primary DC came up" 180 \
        "$PDC_NAME" "$PDC_HOST" "$PDC_IP" -e DC_TYPE="PRIMARY_DC" --dns "$PDC_IP" "${volumes[@]}" || return 1

    log "[volume_restore] Checking recreated PDC"
    sid_after="$(get_domain_sid "$PDC_NAME")"
    check "Domain SID is unchanged (${sid_before:-?})" \
        test -n "$sid_before" -a "$sid_before" == "$sid_after"
    check_output "User still exists"                "^${TEST_USER}$" \
        docker exec "$PDC_NAME" samba-tool user list -d0
    check_kinit "Kerberos kinit with existing user" \
        "$PDC_NAME" /var/lib/samba/private/krb5.conf "$TEST_USER" "$TEST_PASSWORD"
}

# --------------------------------------------------------------------------- main

main() {
    local scenario failed_before

    for scenario in $SCENARIOS; do
        if ! declare -F "scenario_${scenario}" > /dev/null; then
            echo "ERROR: Unknown scenario \"${scenario}\". Available: basic backup_restore volume_restore" >&2
            exit 1
        fi
    done

    trap cleanup EXIT

    if [[ "$SKIP_BUILD" != "1" ]]; then
        log "Building ${IMAGE} from pdc/Dockerfile"
        docker build -t "$IMAGE" "${REPO_DIR}/pdc" || { echo "docker build failed" >&2; exit 1; }
    fi

    log "Preparing network ${NETWORK} (${SUBNET_PREFIX}.0/24)"
    remove_containers
    remove_volumes
    docker network rm "$NETWORK" > /dev/null 2>&1
    docker network create --subnet "${SUBNET_PREFIX}.0/24" "$NETWORK" > /dev/null || exit 1
    BACKUP_DIR="$(mktemp -d -t samba-ad-smoke-backup.XXXXXX)" || exit 1

    for scenario in $SCENARIOS; do
        # Each scenario starts from a clean state.
        # (With KEEP=1, containers of the last scenario are left for debugging.)
        remove_containers
        remove_volumes

        printf '\n######## Scenario: %s\n' "$scenario"
        failed_before=$FAILED
        "scenario_${scenario}" || true
        if [[ "$FAILED" -ne "$failed_before" ]]; then
            FAILED_SCENARIOS+=("$scenario")
            docker ps -a --format '{{.Names}}' | grep -qx "$PDC_NAME" && dump_logs "$PDC_NAME"
        fi
    done

    log "Result: ${PASSED} passed, ${FAILED} failed"
    if [[ "$FAILED" -ne 0 ]]; then
        echo "Failed scenarios: ${FAILED_SCENARIOS[*]}"
        exit 1
    fi
    exit 0
}

main "$@"
