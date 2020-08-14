#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    stub is_already_initialized
    stub start_samba
    stub build_dc
    stub flag_initialized
    stub echo
}

function teardown() {
    true
}

@test '#run_dc return 0 if is_already_initialized return 1 and start_samba return 0' {
    run run_dc; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times is_already_initialized)"    -eq 1 ]]
    [[ "$(stub_called_times start_samba)"               -eq 1 ]]
    [[ "$(stub_called_times build_dc)"                  -eq 0 ]]
    [[ "$(stub_called_times flag_initialized)"          -eq 0 ]]
    [[ "$(stub_called_times echo)"                      -eq 0 ]]
}

@test '#run_dc return 0 if is_already_initialized return 0 and build_dc return 0' {
    stub_and_eval is_already_initialized '{ return 1; }'
    run run_dc; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times is_already_initialized)"    -eq 1 ]]
    [[ "$(stub_called_times start_samba)"               -eq 1 ]]
    [[ "$(stub_called_times build_dc)"                  -eq 1 ]]
    [[ "$(stub_called_times flag_initialized)"          -eq 1 ]]
    [[ "$(stub_called_times echo)"                      -eq 0 ]]
}

@test '#run_dc return 0 if is_already_initialized return 0 and build_dc return 1' {
    stub_and_eval is_already_initialized '{ return 1; }'
    stub_and_eval build_dc '{ return 1; }'
    run run_dc; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times is_already_initialized)"    -eq 1 ]]
    [[ "$(stub_called_times start_samba)"               -eq 0 ]]
    [[ "$(stub_called_times build_dc)"                  -eq 1 ]]
    [[ "$(stub_called_times flag_initialized)"          -eq 0 ]]
    [[ "$(stub_called_times echo)"                      -eq 1 ]]
    stub_called_with_exactly_times echo 1 "ERROR: Failed to build dc"
}

