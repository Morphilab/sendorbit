#!/usr/bin/env bats

load setup

source "$SENDORBIT_ROOT/sendorbit.sh"

setup() {
    configs=("alice host1 /home/alice 22" "bob host2 /srv/data")
    unset DRY_RUN
}

# ====================== run_push_dir: argument validation ======================

@test "push_dir: rejects missing --host" {
    run run_push_dir
    [ "$status" -eq 1 ]
    [[ "$output" == *"--push-dir requires --host"* ]]
}

@test "push_dir: rejects --host without argument" {
    run run_push_dir --host
    [ "$status" -eq 1 ]
    [[ "$output" == *"--host requires an argument"* ]]
}

@test "push_dir: rejects non-numeric --host" {
    run run_push_dir --host abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"must be a numeric index"* ]]
}

@test "push_dir: rejects --host 0 (out of range)" {
    run run_push_dir --host 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"out of range"* ]]
}

@test "push_dir: rejects --host above config count" {
    run run_push_dir --host 3
    [ "$status" -eq 1 ]
    [[ "$output" == *"out of range"* ]]
}

@test "push_dir: rejects unknown option" {
    run run_push_dir --host 1 --foo
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ====================== run_push_dir: config load-time rejection ======================

@test "push-dir: config entry with tab in folder is rejected at load time" {
    local confdir saved_config_dir st
    confdir=$(mktemp -d)
    printf 'configs=("u1 host1 do\tcuments")\n' > "$confdir/hosts.conf"
    saved_config_dir="$CONFIG_DIR"
    CONFIG_DIR="$confdir"
    run load_configuration
    st=$status
    CONFIG_DIR="$saved_config_dir"
    rm -rf "$confdir"
    [ "$st" -eq 1 ]
    [[ "$output" == *"Invalid"* ]]
}

# ====================== run_push_dir: dry-run ======================

@test "push_dir: dry-run uses rsync by default" {
    run run_push_dir --host 1 --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY-RUN] Would rsync"* ]]
    [[ "$output" == *"alice@host1:22 /home/alice/"* ]]
}

@test "push_dir: dry-run with --scp forces scp" {
    run run_push_dir --host 2 --scp --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY-RUN] Would scp"* ]]
    [[ "$output" == *"bob@host2:22 /srv/data/"* ]]
}

@test "push_dir: dry-run shows invocation dir, not project root" {
    local proj saved
    proj="$INVOCATION_DIR"
    saved="$INVOCATION_DIR"
    INVOCATION_DIR="/tmp/some-invoke-dir"
    run run_push_dir --host 1 --dry-run
    INVOCATION_DIR="$saved"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY-RUN] Would rsync: /tmp/some-invoke-dir"* ]]
    [[ "$output" != *"$proj"* ]]
}

@test "push_dir: dry-run normalizes dest trailing slash" {
    configs=("alice host3 /home/alice/data/ 22")
    run run_push_dir --host 1 --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"/home/alice/data/"* ]]
    [[ "$output" != *"data//"* ]]
}

# ====================== run_push_dir: real execution ======================

@test "push_dir: non-dry-run invokes transfer.sh with cwd and resolved dest" {
    local stub_dir record
    stub_dir=$(mktemp -d)
    record="$stub_dir/args"
    cat > "$stub_dir/transfer.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$RECORD_FILE"
EOF
    chmod +x "$stub_dir/transfer.sh"
    export RECORD_FILE="$record"
    export MODULES_DIR="$stub_dir"

    run run_push_dir --host 1
    [ "$status" -eq 0 ]

    local -a recorded
    mapfile -t recorded < "$record"
    [ "${recorded[0]}" == "rsync" ]
    [ "${recorded[1]}" == "alice" ]
    [ "${recorded[2]}" == "host1" ]
    [ "${recorded[3]}" == "22" ]
    [ "${recorded[4]}" == "/home/alice" ]
    [ "${recorded[5]}" == "$INVOCATION_DIR" ]
}
