#!/usr/bin/env bats
load helpers "/pdc/entrypoint.sh"

function setup() {
    stub echo
    stub_and_eval find '{ command echo "/backup/samba-backup-corp.mysite.example.com-2020-08-16T07-42-59.421050.tar.bz2"; }'
    stub samba-tool
}

function teardown() {
    true
}

@test '#build_primary_dc_with_backup_file should return 0 if all instructions were succeeded' {
    run build_primary_dc_with_backup_file; command echo "$output"

    [[ "$status" -eq 0 ]]
    [[ "$(stub_called_times find)" -eq 1 ]]
    [[ "$(stub_called_times samba-tool)" -eq 1 ]]
    [[ "$(stub_called_times echo)" -eq 0 ]]

    stub_called_with_exactly_times find 1 '/backup' '-maxdepth' '1' '-mindepth' '1' '-type' 'f' '-regextype' 'posix-extended' '-regex' '.*/samba\-backup\-.*\.tar\.bz2$'
    stub_called_with_exactly_times samba-tool 1 "domain" "backup" "restore" \
                                                "--backup-file=/backup/samba-backup-corp.mysite.example.com-2020-08-16T07-42-59.421050.tar.bz2" \
                                                "--newservername=${HOSTNAME}" "--targetdir=/var/lib/restored_samba"
}

@test '#build_primary_dc_with_backup_file should return 1 if find command does not find backup file' {
    stub find
    run build_primary_dc_with_backup_file; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times find)" -eq 1 ]]
    [[ "$(stub_called_times samba-tool)" -eq 0 ]]
    [[ "$(stub_called_times echo)" -eq 1 ]]

    stub_called_with_exactly_times echo 1 "ERROR: Failed to find backup file in /backup directory." \
                                          "Are you sure to have mounted the directory /backup that contains backup file?" \
                                          "Or you mounted it same as an original name of the backup file?" \
                                          "This program search with it the name samba-backup-*.tar.bz2"
}

@test '#build_primary_dc_with_backup_file should return 1 if samba-tool command has failed' {
    stub_and_eval samba-tool '{ return 1; }'
    run build_primary_dc_with_backup_file; command echo "$output"

    [[ "$status" -eq 1 ]]
    [[ "$(stub_called_times find)" -eq 1 ]]
    [[ "$(stub_called_times samba-tool)" -eq 1 ]]
    [[ "$(stub_called_times echo)" -eq 1 ]]

    stub_called_with_exactly_times samba-tool 1 "domain" "backup" "restore" \
                                                "--backup-file=/backup/samba-backup-corp.mysite.example.com-2020-08-16T07-42-59.421050.tar.bz2" \
                                                "--newservername=${HOSTNAME}" "--targetdir=/var/lib/restored_samba"

}

