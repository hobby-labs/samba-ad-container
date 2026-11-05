#!/usr/bin/env bash
#
# Smoke test for samba-ad-container.
# Builds the image (pdc/Dockerfile), runs a real primary DC and a secondary DC
# on a dedicated docker bridge network, and checks that the AD services work.
#
# Usage: test/smoke/run.sh
#
# Environment variables:
#   IMAGE       Image tag to build/test        (default: samba-ad-container:smoke)
#   SKIP_BUILD  Set to 1 to skip "docker build" (default: 0)
#   KEEP        Set to 1 to keep containers and network after the test (default: 0)
#   SUBNET_PREFIX  First 3 octets of the test network (default: 172.30.99)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

IMAGE="${IMAGE:-samba-ad-container:smoke}"
SKIP_BUILD="${SKIP_BUILD:-0}"
KEEP="${KEEP:-0}"
SUBNET_PREFIX="${SUBNET_PREFIX:-172.30.99}"

NETWORK="samba-ad-smoke"
PDC_NAME="smoke-pdc01"
PDC_HOST="pdc01"
PDC_IP="${SUBNET_PREFIX}.11"
BDC_NAME="smoke-bdc01"
BDC_HOST="bdc01"
BDC_IP="${SUBNET_PREFIX}.12"

DOMAIN_FQDN="corp.smoke.example.com"
REALM="${DOMAIN_FQDN^^}"
DOMAIN="CORP"
ADMIN_PASSWORD='Sm0ke-Adm1n!pass'
TEST_USER="smokeuser"
TEST_PASSWORD='Sm0ke-Us3r!pass'

PASSED=0
FAILED=0

log()  { printf '\n==> %s\n' "$*"; }
pass() { printf '  [PASS] %s\n' "$*"; PASSED=$((PASSED + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAILED=$((FAILED + 1)); }

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

cleanup() {
    if [[ "$KEEP" == "1" ]]; then
        log "KEEP=1: leaving ${PDC_NAME}, ${BDC_NAME} and network ${NETWORK} running"
        return
    fi
    log "Cleaning up"
    docker rm -f "$PDC_NAME" "$BDC_NAME" > /dev/null 2>&1
    docker network rm "$NETWORK" > /dev/null 2>&1
}

# wait_for_dc <container> <timeout_sec>
wait_for_dc() {
    local name="$1" timeout="$2" i
    for ((i = 0; i < timeout; i += 2)); do
        if [[ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" != "true" ]]; then
            echo "Container ${name} is not running" >&2
            return 1
        fi
        # "samba-tool domain info" (CLDAP) can answer before the LDAP listener is ready,
        # so wait for both.
        docker exec "$name" samba-tool domain info 127.0.0.1 > /dev/null 2>&1 && \
            docker exec "$name" ldapsearch -H ldap://127.0.0.1 -x -b '' -s base defaultNamingContext > /dev/null 2>&1 && \
            return 0
        sleep 2
    done
    echo "Timed out after ${timeout}s waiting for ${name}" >&2
    return 1
}

dump_logs() {
    printf '%s\n' "----- docker logs $1 (last 50 lines) -----"
    docker logs --tail 50 "$1" 2>&1 | sed 's/^/  | /'
}

# Run a command in a container with Kerberos configured from the provisioned krb5.conf.
# (The image removes /etc/krb5.conf; samba generates /var/lib/samba/private/krb5.conf.)
kexec() {
    local name="$1"; shift
    docker exec -e KRB5_CONFIG=/var/lib/samba/private/krb5.conf "$name" "$@"
}

main() {
    trap cleanup EXIT

    if [[ "$SKIP_BUILD" != "1" ]]; then
        log "Building ${IMAGE} from pdc/Dockerfile"
        docker build -t "$IMAGE" "${REPO_DIR}/pdc" || { echo "docker build failed" >&2; exit 1; }
    fi

    log "Preparing network ${NETWORK} (${SUBNET_PREFIX}.0/24)"
    docker rm -f "$PDC_NAME" "$BDC_NAME" > /dev/null 2>&1
    docker network rm "$NETWORK" > /dev/null 2>&1
    docker network create --subnet "${SUBNET_PREFIX}.0/24" "$NETWORK" > /dev/null || exit 1

    # ---------------------------------------------------------------- PDC
    log "Starting primary DC ${PDC_NAME} (${PDC_IP})"
    docker run -d --name "$PDC_NAME" --hostname "$PDC_HOST" \
        -e DC_TYPE="PRIMARY_DC" \
        -e DOMAIN_FQDN="$DOMAIN_FQDN" \
        -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
        --network "$NETWORK" --ip "$PDC_IP" --dns "$PDC_IP" \
        --privileged \
        "$IMAGE" > /dev/null || exit 1

    if ! wait_for_dc "$PDC_NAME" 180; then
        fail "Primary DC came up"
        dump_logs "$PDC_NAME"
        exit 1
    fi
    pass "Primary DC came up"

    log "Checking primary DC"
    check_output "Samba version"                    'Version 4\.' \
        docker exec "$PDC_NAME" samba --version
    check_output "smb.conf has dns forwarder"       '^\s*dns forwarder = 8\.8\.8\.8' \
        docker exec "$PDC_NAME" cat /etc/samba/smb.conf
    check_output "smb.conf has log level"           '^\s*log level = 5' \
        docker exec "$PDC_NAME" cat /etc/samba/smb.conf
    check_output "/etc/hosts has FQDN"              "^${PDC_IP//./\\.} ${PDC_HOST} ${PDC_HOST}\.${DOMAIN_FQDN//./\\.}" \
        docker exec "$PDC_NAME" cat /etc/hosts
    check_output "nsswitch passwd uses winbind"     '^passwd:.* winbind' \
        docker exec "$PDC_NAME" cat /etc/nsswitch.conf
    check_output "Domain function level"            'Domain function level' \
        docker exec "$PDC_NAME" samba-tool domain level show
    check_output "DNS SRV _ldap._tcp"               "has SRV record .* ${PDC_HOST}\.${DOMAIN_FQDN//./\\.}" \
        docker exec "$PDC_NAME" host -t SRV "_ldap._tcp.${DOMAIN_FQDN}" "$PDC_IP"
    check_output "DNS SRV _kerberos._udp"           'has SRV record' \
        docker exec "$PDC_NAME" host -t SRV "_kerberos._udp.${DOMAIN_FQDN}" "$PDC_IP"
    check_output "DNS A record of PDC"              "has address ${PDC_IP//./\\.}" \
        docker exec "$PDC_NAME" host -t A "${PDC_HOST}.${DOMAIN_FQDN}" "$PDC_IP"
    check_output "DNS forwarder resolves external"  'has (IPv6 )?address' \
        docker exec "$PDC_NAME" host -W 5 example.com "$PDC_IP"
    check_output "LDAP rootDSE"                     "defaultNamingContext: DC=corp,DC=smoke" \
        docker exec "$PDC_NAME" ldapsearch -H "ldap://${PDC_IP}" -x -b '' -s base defaultNamingContext
    check "Create user ${TEST_USER}" \
        docker exec "$PDC_NAME" samba-tool user create "$TEST_USER" "$TEST_PASSWORD"
    check_output "SMB shares (sysvol/netlogon)"     'netlogon' \
        docker exec "$PDC_NAME" smbclient -L "$PDC_IP" -U "${TEST_USER}%${TEST_PASSWORD}"
    check_output "Kerberos kinit as ${TEST_USER}"   "Default principal: ${TEST_USER}@${REALM}" \
        kexec "$PDC_NAME" bash -c "echo '${TEST_PASSWORD}' | kinit ${TEST_USER}@${REALM} > /dev/null && klist"
    check_output "winbind lists users"              "${DOMAIN}\\\\${TEST_USER}" \
        docker exec "$PDC_NAME" wbinfo -u
    check_output "getent resolves domain user"      "^${DOMAIN}\\\\${TEST_USER}:" \
        docker exec "$PDC_NAME" getent passwd "${DOMAIN}\\${TEST_USER}"

    # ---------------------------------------------------------------- BDC
    log "Starting secondary DC ${BDC_NAME} (${BDC_IP})"
    docker run -d --name "$BDC_NAME" --hostname "$BDC_HOST" \
        -e DC_TYPE="SECONDARY_DC" \
        -e DOMAIN_FQDN="$DOMAIN_FQDN" \
        -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
        --network "$NETWORK" --ip "$BDC_IP" --dns "$PDC_IP" \
        --privileged \
        "$IMAGE" > /dev/null || exit 1

    if ! wait_for_dc "$BDC_NAME" 300; then
        fail "Secondary DC joined and came up"
        dump_logs "$BDC_NAME"
        exit 1
    fi
    pass "Secondary DC joined and came up"

    log "Checking secondary DC"
    check_output "BDC is listed as a DC on PDC"     "^${BDC_HOST^^}\\$" \
        docker exec "$PDC_NAME" samba-tool group listmembers "Domain Controllers"
    check_output "User replicated to BDC"           "^${TEST_USER}$" \
        docker exec "$BDC_NAME" samba-tool user list -H "ldap://${BDC_IP}" -U "Administrator%${ADMIN_PASSWORD}"
    check_output "DRS replication from PDC"         'Last attempt .* was successful' \
        docker exec "$BDC_NAME" samba-tool drs showrepl -U "Administrator%${ADMIN_PASSWORD}"
    check_output "Kerberos kinit against BDC"       "Default principal: ${TEST_USER}@${REALM}" \
        kexec "$BDC_NAME" bash -c "echo '${TEST_PASSWORD}' | kinit ${TEST_USER}@${REALM} > /dev/null && klist"

    log "Result: ${PASSED} passed, ${FAILED} failed"
    if [[ "$FAILED" -ne 0 ]]; then
        dump_logs "$PDC_NAME"
        dump_logs "$BDC_NAME"
        exit 1
    fi
    exit 0
}

main "$@"
