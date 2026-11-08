#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    SAM_LDB_FILE="$(mktemp -u)"
}

function teardown() {
    rm -f "$SAM_LDB_FILE"
}

@test '#has_existing_dc_data should return 0 if sam.ldb exists' {
    touch "$SAM_LDB_FILE"
    run has_existing_dc_data

    [[ "$status" -eq 0 ]]
}

@test '#has_existing_dc_data should return 1 if sam.ldb does not exist' {
    run has_existing_dc_data

    [[ "$status" -eq 1 ]]
}

@test '#SAM_LDB_FILE should be the path of sam.ldb of samba' {
    [[ "$(grep -E '^SAM_LDB_FILE=' "${BATS_TEST_DIRNAME}/../pdc/entrypoint.sh")" == 'SAM_LDB_FILE="/var/lib/samba/private/sam.ldb"' ]]
}
