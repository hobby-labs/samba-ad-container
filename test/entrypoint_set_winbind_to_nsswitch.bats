#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    stub sed
    stub grep
    stub echo

    export COUNT_GREP_PASSWD=0
    export COUNT_GREP_GROUP=0
}

function teardown() {
    unset COUNT_GREP_PASSWD
    unset COUNT_GREP_GROUP
}

@test '#set_winbind_to_nsswitch should return 0 if all instructions were succeeded' {
    run set_winbind_to_nsswitch; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times grep)"          -eq 2 ]]
    [[ "$(stub_called_times sed)"           -eq 0 ]]
    [[ "$(stub_called_times mv)"            -eq 0 ]]

    stub_called_with_exactly_times grep 1 '-q' '-E' '^passwd:.* winbind( .*)?$' '/etc/nsswitch.conf'
    stub_called_with_exactly_times grep 1 '-q' '-E' '^group:.* winbind( .*)?$' '/etc/nsswitch.conf'
}

@test '#set_winbind_to_nsswitch should return 0 if add winbind are succeeded' {
    stub_and_eval grep '{
        if [[ "$3" == "^passwd:.* winbind( .*)?\$" ]]; then
            (( ++COUNT_GREP_PASSWD ))
            if [[ $COUNT_GREP_PASSWD -lt 2 ]]; then
                return 1
            fi
        elif [[ "$3" == "^group:.* winbind( .*)?\$" ]]; then
            (( ++COUNT_GREP_GROUP ))
            if [[ $COUNT_GREP_GROUP -lt 2 ]]; then
                return 1
            fi
        fi
        return 0
    }'
    run set_winbind_to_nsswitch; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times grep)"          -eq 4 ]]
    [[ "$(stub_called_times sed)"           -eq 2 ]]
    [[ "$(stub_called_times mv)"            -eq 0 ]]

    stub_called_with_exactly_times grep 2 '-q' '-E' '^passwd:.* winbind( .*)?$' '/etc/nsswitch.conf'
    stub_called_with_exactly_times grep 2 '-q' '-E' '^group:.* winbind( .*)?$' '/etc/nsswitch.conf'
    stub_called_with_exactly_times sed 1 '-i' '-e' 's/^passwd:\(.*\)/passwd:\1 winbind/' '/etc/nsswitch.conf'
    stub_called_with_exactly_times sed 1 '-i' '-e' 's/^group:\(.*\)/group:\1 winbind/' '/etc/nsswitch.conf'
}

@test '#set_winbind_to_nsswitch should return 1 if add winbind to passwd line has failed' {
    stub_and_eval grep '{
        if [[ "$3" == "^passwd:.* winbind( .*)?\$" ]]; then
            return 1
        fi
        return 0
    }'
    run set_winbind_to_nsswitch; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times grep)"          -eq 2 ]]
    [[ "$(stub_called_times sed)"           -eq 1 ]]
    [[ "$(stub_called_times mv)"            -eq 0 ]]

    stub_called_with_exactly_times grep 2 '-q' '-E' '^passwd:.* winbind( .*)?$' '/etc/nsswitch.conf'
    stub_called_with_exactly_times echo 1 'ERROR: Failed to add winbind at line of passwd in /etc/nsswitch.conf'
    stub_called_with_exactly_times sed 1 '-i' '-e' 's/^passwd:\(.*\)/passwd:\1 winbind/' '/etc/nsswitch.conf'
}

@test '#set_winbind_to_nsswitch should return 1 if add winbind to group line has failed' {
    stub_and_eval grep '{
        if [[ "$3" == "^group:.* winbind( .*)?\$" ]]; then
            return 1
        fi
        return 0
    }'
    run set_winbind_to_nsswitch; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times grep)"          -eq 3 ]]
    [[ "$(stub_called_times sed)"           -eq 1 ]]
    [[ "$(stub_called_times mv)"            -eq 0 ]]

    stub_called_with_exactly_times grep 1 '-q' '-E' '^passwd:.* winbind( .*)?$' '/etc/nsswitch.conf'
    stub_called_with_exactly_times grep 2 '-q' '-E' '^group:.* winbind( .*)?$' '/etc/nsswitch.conf'
    stub_called_with_exactly_times echo 1 'ERROR: Failed to add winbind at line of group in /etc/nsswitch.conf'
    stub_called_with_exactly_times sed 1 '-i' '-e' 's/^group:\(.*\)/group:\1 winbind/' '/etc/nsswitch.conf'
}



