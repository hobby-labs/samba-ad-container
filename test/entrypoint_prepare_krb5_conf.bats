#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    stub cat
    stub echo
}

function teardown() {
    true
}

@test '#prepare_krb5_conf return 0 if all instructions were succeeded' {
    run prepare_krb5_conf; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times cat)"       -eq 1 ]]
    [[ "$(stub_called_times echo)"      -eq 0 ]]
}

@test '#prepare_krb5_conf return 1 if modify /etc/krb5.conf has failed' {
    stub_and_eval cat '{ return 1; }'
    run prepare_krb5_conf; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times cat)"       -eq 1 ]]
    [[ "$(stub_called_times echo)"      -eq 1 ]]

    stub_called_with_exactly_times echo 1 'ERROR: Failed to modify /etc/krb5.conf'
}

