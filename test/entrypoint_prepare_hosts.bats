#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    stub_and_eval sed '{
        if [[ "$1" == "-e" ]] && [[ "$2" == "s/\\./\\\\./g" ]]; then
            command echo "192\.168\.1\.72"
        fi
        return 0
    }'
    stub grep
    stub echo
    export CONTAINER_IP="192.168.1.72"
    export DOMAIN_FQDN="corp.mysite.example.com"
    export BK_HOSTNAME=${HOSTNAME}
    export HOSTNAME="bdc01"
}

function teardown() {
    export HOSTNAME=${BK_HOSTNAME}
    unset CONTAINER_IP
    unset DOMAIN_FQDN
    unset BK_HOSTNAME
}

@test '#prepare_hosts should return 0 if all instructions has succeeded' {
    run prepare_hosts; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times sed)"       -eq 2 ]]
    [[ "$(stub_called_times grep)"      -eq 1 ]]
    [[ "$(stub_called_times echo)"      -eq 0 ]]

    stub_called_with_exactly_times sed 1 '-e' 's/\./\\./g'
    stub_called_with_exactly_times sed 1 '-i' '-e' 's/192\.168\.1\.72 .*/192.168.1.72 bdc01 bdc01.corp.mysite.example.com/g' '/etc/hosts'
    stub_called_with_exactly_times grep 1 '-q' '-E' '^192\.168\.1\.72 .*' '/etc/hosts'
}

@test '#prepare_hosts should return 1 if grep after modified /etc/hosts has failed' {
    stub_and_eval grep '{ return 1; }'
    run prepare_hosts; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times sed)"       -eq 2 ]]
    [[ "$(stub_called_times grep)"      -eq 1 ]]
    [[ "$(stub_called_times echo)"      -eq 1 ]]

    stub_called_with_exactly_times sed 1 '-e' 's/\./\\./g'
    stub_called_with_exactly_times sed 1 '-i' '-e' 's/192\.168\.1\.72 .*/192.168.1.72 bdc01 bdc01.corp.mysite.example.com/g' '/etc/hosts'
    stub_called_with_exactly_times grep 1 '-q' '-E' '^192\.168\.1\.72 .*' '/etc/hosts'
    stub_called_with_exactly_times echo 1 'ERROR: Failed to edit /etc/hosts. Could not add hosts information of bdc01 bdc01.corp.mysite.example.com'
}


