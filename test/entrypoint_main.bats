#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    stub_and_eval init_env_variables '{ return 0; }'
    stub run_primary_dc
    stub echo
}

function teardown() {
    rm -f "$INITIALIZED_FLAG_FILE"
}

@test '#main should return 1 if init_env_variables() returns not 0' {
    stub_and_eval init_env_variables '{ return 1; }'

    run main

    command echo "$output"
    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times run_primary_dc)" -eq 0 ]]
    stub_called_with_exactly_times echo 1 'ERROR: Failed to initialize environment variables.'
}

@test '#main should return 1 if DC_TYPE was not supported' {
    DC_TYPE="FOO"
    run main

    command echo "$output"
    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times run_primary_dc)" -eq 0 ]]
    stub_called_with_exactly_times echo 1 "ERROR: Unsupported DC_TYPE environment variable (DC_TYPE=FOO). This program only support \"PRIMARY_DC\", \"SECONDARY_DC\", \"TEMPORARY_DC\" or \"RESTORED_PRIMARY_DC\""
}

@test '#main should return 0 if DC_TYPE is PRIMARY_DC and run_primary_dc has return 0' {
    DC_TYPE="PRIMARY_DC"
    run main

    command echo "$output"
    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times run_primary_dc)" -eq 1 ]]
    [[ "$(stub_called_times echo)" -eq 0 ]]
}

