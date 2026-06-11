#!/usr/bin/env bats

load setup

# ====================== validate_user ======================

@test "validate_user: accepts normal user" {
    run validate_user "admin"
    [ "$status" -eq 0 ]
}

@test "validate_user: rejects empty user" {
    run validate_user ""
    [ "$status" -eq 1 ]
}

@test "validate_user: rejects user with trailing dash" {
    run validate_user "admin-"
    [ "$status" -eq 1 ]
}

@test "validate_user: rejects user with shell metachar" {
    run validate_user "admin;rm"
    [ "$status" -eq 1 ]
}

@test "validate_user: rejects very long user (33 chars)" {
    run validate_user "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    [ "$status" -eq 1 ]
}

@test "validate_user: accepts 32-char user" {
    local u
    printf -v u '%32s' ""; u="${u// /a}"
    run validate_user "$u"
    [ "$status" -eq 0 ]
}

@test "validate_user: accepts user with underscore" {
    run validate_user "my_user"
    [ "$status" -eq 0 ]
}

@test "validate_user: rejects user with spaces" {
    run validate_user "my user"
    [ "$status" -eq 1 ]
}

@test "validate_user: accepts user with uppercase" {
    run validate_user "Admin"
    [ "$status" -eq 0 ]
}

@test "validate_user: accepts user with mixed case" {
    run validate_user "My_User-01"
    [ "$status" -eq 0 ]
}

# ====================== validate_ip ======================

@test "validate_ip: accepts valid IP" {
    run validate_ip "192.168.1.1"
    [ "$status" -eq 0 ]
}

@test "validate_ip: accepts edge IP 0.0.0.0" {
    run validate_ip "0.0.0.0"
    [ "$status" -eq 0 ]
}

@test "validate_ip: accepts edge IP 255.255.255.255" {
    run validate_ip "255.255.255.255"
    [ "$status" -eq 0 ]
}

@test "validate_ip: rejects IP with octet > 255" {
    run validate_ip "192.168.1.256"
    [ "$status" -eq 1 ]
}

@test "validate_ip: rejects non-IP string" {
    run validate_ip "not-an-ip"
    [ "$status" -eq 1 ]
}

@test "validate_ip: rejects IP with extra chars" {
    run validate_ip "192.168.1.1;rm"
    [ "$status" -eq 1 ]
}

@test "validate_ip: rejects IP with only 3 octets" {
    run validate_ip "192.168.1"
    [ "$status" -eq 1 ]
}

@test "validate_ip: rejects IP with 5 octets" {
    run validate_ip "1.2.3.4.5"
    [ "$status" -eq 1 ]
}

@test "validate_ip: rejects IP with leading zero octet 08" {
    run validate_ip "192.168.1.08"
    [ "$status" -eq 1 ]
}

@test "validate_ip: rejects IP with leading zero octet 09" {
    run validate_ip "10.0.0.09"
    [ "$status" -eq 1 ]
}

@test "validate_ip: rejects IP with leading zero octet 099" {
    run validate_ip "172.16.0.099"
    [ "$status" -eq 1 ]
}

@test "validate_ip: accepts IP with octet 0" {
    run validate_ip "10.0.0.1"
    [ "$status" -eq 0 ]
}

@test "validate_ip: rejects IP with leading zero octet 01" {
    run validate_ip "10.0.0.01"
    [ "$status" -eq 1 ]
}

# ====================== validate_hostname ======================

@test "validate_hostname: accepts simple hostname" {
    run validate_hostname "example.com"
    [ "$status" -eq 0 ]
}

@test "validate_hostname: accepts SSH alias with underscore" {
    run validate_hostname "prod_web"
    [ "$status" -eq 0 ]
}

@test "validate_hostname: accepts hostname with subdomains" {
    run validate_hostname "server.east.example.com"
    [ "$status" -eq 0 ]
}

@test "validate_hostname: rejects hostname with shell metachar" {
    run validate_hostname "host;rm"
    [ "$status" -eq 1 ]
}

@test "validate_hostname: rejects hostname with spaces" {
    run validate_hostname "my host"
    [ "$status" -eq 1 ]
}

@test "validate_hostname: accepts hostname with numbers" {
    run validate_hostname "server-01.example.com"
    [ "$status" -eq 0 ]
}

# ====================== validate_config_entry ======================

@test "validate_config_entry: accepts 3-element entry" {
    run validate_config_entry "user 1xx.1xx.1.1xx backups"
    [ "$status" -eq 0 ]
}

@test "validate_config_entry: accepts 4-element entry" {
    run validate_config_entry "user example.com /home/deploy 2222"
    [ "$status" -eq 0 ]
}

@test "validate_config_entry: rejects entry with path traversal" {
    run validate_config_entry "user host ../etc"
    [ "$status" -eq 1 ]
}

@test "validate_config_entry: rejects entry with nested path traversal" {
    run validate_config_entry "user host a/../../../b"
    [ "$status" -eq 1 ]
}

@test "validate_config_entry: rejects entry with fewer than 3 fields" {
    run validate_config_entry "user host"
    [ "$status" -eq 1 ]
}

@test "validate_config_entry: rejects entry with port out of range" {
    run validate_config_entry "user host folder 99999"
    [ "$status" -eq 1 ]
}

@test "validate_config_entry: rejects entry with port 0" {
    run validate_config_entry "user host folder 0"
    [ "$status" -eq 1 ]
}

@test "validate_config_entry: rejects entry with non-numeric port" {
    run validate_config_entry "user host folder abc"
    [ "$status" -eq 1 ]
}

@test "validate_config_entry: rejects entry with invalid user" {
    run validate_config_entry "user- host folder"
    [ "$status" -eq 1 ]
}

@test "validate_config_entry: rejects entry with invalid host" {
    run validate_config_entry "user ';rm' folder"
    [ "$status" -eq 1 ]
}

@test "validate_config_entry: accepts entry with dot-path .ssh" {
    run validate_config_entry "user host .ssh"
    [ "$status" -eq 0 ]
}

@test "validate_config_entry: accepts entry with absolute dot-path" {
    run validate_config_entry "user host /home/user/.ssh/keys"
    [ "$status" -eq 0 ]
}

@test "validate_config_entry: accepts entry with nested dot-path" {
    run validate_config_entry "user host path/.hidden/file"
    [ "$status" -eq 0 ]
}

@test "validate_config_entry: accepts literal dot-path ." {
    run validate_config_entry "user host a/./b"
    [ "$status" -eq 0 ]
}

@test "validate_config_entry: accepts entry with dot in name (not a hidden path)" {
    run validate_config_entry "user host foo.bar"
    [ "$status" -eq 0 ]
}

@test "validate_config_entry: rejects entry with dangerous characters in folder" {
    run validate_config_entry "user host folder\;rm"
    [ "$status" -eq 1 ]
}

# ====================== validate_transfer_files ======================

@test "validate_transfer_files: rejects empty list" {
    run validate_transfer_files
    [ "$status" -eq 1 ]
}

@test "validate_transfer_files: rejects non-existent file" {
    run validate_transfer_files "/tmp/nonexistent_file_for_test_xyz"
    [ "$status" -eq 1 ]
}

@test "validate_transfer_files: accepts existing file" {
    local tmpf
    tmpf=$(mktemp)
    run validate_transfer_files "$tmpf"
    [ "$status" -eq 0 ]
    rm -f "$tmpf"
}

@test "validate_transfer_files: accepts multiple existing files" {
    local tmpf1 tmpf2
    tmpf1=$(mktemp)
    tmpf2=$(mktemp)
    run validate_transfer_files "$tmpf1" "$tmpf2"
    [ "$status" -eq 0 ]
    rm -f "$tmpf1" "$tmpf2"
}

@test "validate_transfer_files: rejects if any file does not exist" {
    local tmpf
    tmpf=$(mktemp)
    run validate_transfer_files "$tmpf" "/tmp/nonexistent_file_for_test_xyz"
    [ "$status" -eq 1 ]
    rm -f "$tmpf"
}

# ====================== resolve_dest_path ======================

@test "resolve_dest_path: returns absolute path unchanged" {
    run resolve_dest_path "/absolute/path"
    [ "$status" -eq 0 ]
    [ "$output" = "/absolute/path" ]
}

@test "resolve_dest_path: expands relative path with HOME" {
    run resolve_dest_path "relative/path"
    [ "$status" -eq 0 ]
    [[ "$output" == "$HOME/relative/path" ]]
}

@test "resolve_dest_path: handles root path" {
    run resolve_dest_path "/"
    [ "$status" -eq 0 ]
    [ "$output" = "/" ]
}

@test "resolve_dest_path: handles trailing slash absolute" {
    run resolve_dest_path "/var/log/"
    [ "$status" -eq 0 ]
    [ "$output" = "/var/log/" ]
}

# ====================== validate_configuration ======================

@test "validate_configuration: accepts valid config with one entry" {
    local tmpconf
    tmpconf=$(mktemp)
    echo 'configs=("user host folder")' > "$tmpconf"
    run validate_configuration "$tmpconf"
    [ "$status" -eq 0 ]
    rm -f "$tmpconf"
}

@test "validate_configuration: accepts valid config with multiple entries" {
    local tmpconf
    tmpconf=$(mktemp)
    echo 'configs=("user1 host1 folder1" "user2 host2 folder2")' > "$tmpconf"
    run validate_configuration "$tmpconf"
    [ "$status" -eq 0 ]
    rm -f "$tmpconf"
}

@test "validate_configuration: rejects missing file" {
    run validate_configuration "/tmp/opencode/nonexistent_config_abc"
    [ "$status" -eq 1 ]
}

@test "validate_configuration: rejects invalid syntax" {
    local tmpconf
    tmpconf=$(mktemp)
    echo 'configs=(' > "$tmpconf"
    run validate_configuration "$tmpconf"
    [ "$status" -eq 1 ]
    rm -f "$tmpconf"
}

@test "validate_configuration: rejects config without configs array" {
    local tmpconf
    tmpconf=$(mktemp)
    echo 'not_configs=("user host folder")' > "$tmpconf"
    run validate_configuration "$tmpconf"
    [ "$status" -eq 1 ]
    rm -f "$tmpconf"
}

@test "validate_configuration: rejects config with invalid entry" {
    local tmpconf
    tmpconf=$(mktemp)
    echo 'configs=("user host folder 99999")' > "$tmpconf"
    run validate_configuration "$tmpconf"
    [ "$status" -eq 1 ]
    rm -f "$tmpconf"
}

@test "validate_configuration: rejects empty configs array" {
    local tmpconf
    tmpconf=$(mktemp)
    echo 'configs=()' > "$tmpconf"
    run validate_configuration "$tmpconf"
    [ "$status" -eq 1 ]
    rm -f "$tmpconf"
}
