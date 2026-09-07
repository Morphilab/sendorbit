#!/usr/bin/env bats

load setup

# ====================== connection.sh ======================

@test "connection: rejects no arguments" {
    run "$SENDORBIT_ROOT/modules/connection.sh"
    [ "$status" -eq 1 ]
}

@test "connection: rejects one argument" {
    run "$SENDORBIT_ROOT/modules/connection.sh" "user"
    [ "$status" -eq 1 ]
}

@test "connection: rejects four arguments" {
    run "$SENDORBIT_ROOT/modules/connection.sh" "user" "host" "22" "extra"
    [ "$status" -eq 1 ]
}

@test "connection: rejects invalid user" {
    run "$SENDORBIT_ROOT/modules/connection.sh" "user-;rm" "host"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid parameters"* ]]
}

@test "connection: rejects invalid host" {
    run "$SENDORBIT_ROOT/modules/connection.sh" "user" "host;evil"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid parameters"* ]]
}

# ====================== transfer.sh ======================

@test "transfer: rejects no arguments" {
    run "$SENDORBIT_ROOT/modules/transfer.sh"
    [ "$status" -eq 1 ]
}

@test "transfer: rejects three arguments" {
    run "$SENDORBIT_ROOT/modules/transfer.sh" "scp" "user" "host"
    [ "$status" -eq 1 ]
}

@test "transfer: rejects invalid type" {
    run "$SENDORBIT_ROOT/modules/transfer.sh" "invalid" "user" "host" "22" "/dest"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid type"* ]]
}

@test "transfer: rejects invalid user" {
    run "$SENDORBIT_ROOT/modules/transfer.sh" "scp" "user-;rm" "host" "22" "/dest"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid parameters"* ]]
}

@test "transfer: rejects invalid host" {
    run "$SENDORBIT_ROOT/modules/transfer.sh" "rsync" "user" "host;evil" "22" "/dest"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid parameters"* ]]
}

@test "connection: rejects invalid port" {
    run "$SENDORBIT_ROOT/modules/connection.sh" "alice" "host" "22;calc"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid parameters"* ]]
}

@test "transfer: rejects invalid port" {
    run "$SENDORBIT_ROOT/modules/transfer.sh" "scp" "user" "host" "0" "/dest"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid parameters"* ]]
}

@test "transfer: rejects destination with traversal" {
    run "$SENDORBIT_ROOT/modules/transfer.sh" "scp" "user" "host" "22" "../escape" "/etc/hostname"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid destination path"* ]]
}

@test "transfer: rejects destination with command separator" {
    run "$SENDORBIT_ROOT/modules/transfer.sh" "scp" "user" "host" "22" 'x;touch /tmp/pwned' "/etc/hostname"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid destination path"* ]]
}

@test "transfer: rejects destination with newline injection" {
    run "$SENDORBIT_ROOT/modules/transfer.sh" "rsync" "user" "host" "22" "$(printf 'x\nid')" "/etc/hostname"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid destination path"* ]]
}

# ====================== transfer.sh: native rsync backup ======================

make_net_stubs() {
    local stub="$1"
    cat > "$stub/ssh" <<'EOF'
#!/bin/bash
if [[ "${4:-}" == "mkdir -p"* ]]; then
    [[ -n "${FAKE_SSH_FAIL:-}" ]] && exit 1
    printf 'MKDIR:%s\n' "$4" >> "$CALLS"
    exit 0
fi
printf 'SSH-OTHER:%s\n' "$*" >> "$CALLS"
exit 0
EOF
    cat > "$stub/rsync" <<'EOF'
#!/bin/bash
printf 'RSYNC:%s\n' "$*" >> "$CALLS"
exit 0
EOF
    chmod +x "$stub/ssh" "$stub/rsync"
}

@test "transfer: rsync pre-creates backup dir and uses native --backup-dir" {
    local stub; stub=$(mktemp -d)
    export CALLS="$stub/calls"; : > "$CALLS"
    make_net_stubs "$stub"
    export SSH_CMD="$stub/ssh" RSYNC_CMD="$stub/rsync" SCP_CMD="$stub/rsync"
    run "$SENDORBIT_ROOT/modules/transfer.sh" rsync alice host1 22 /home/alice /etc/hostname
    [ "$status" -eq 0 ]
    grep -q '^MKDIR:mkdir -p /home/alice/backup/' "$CALLS"
    grep -q '^RSYNC:' "$CALLS"
    grep -q -- '--backup' "$CALLS"
    grep -q -- '--backup-dir=/home/alice/backup/' "$CALLS"
}

@test "transfer: rsync excludes backup store from sync" {
    local stub; stub=$(mktemp -d)
    export CALLS="$stub/calls"; : > "$CALLS"
    make_net_stubs "$stub"
    export SSH_CMD="$stub/ssh" RSYNC_CMD="$stub/rsync" SCP_CMD="$stub/rsync"
    run "$SENDORBIT_ROOT/modules/transfer.sh" rsync alice host1 22 /home/alice /etc/hostname
    [ "$status" -eq 0 ]
    grep -Fq -- '--exclude=/backup/' "$CALLS"
}

@test "transfer: aborts when remote backup dir cannot be created" {
    local stub; stub=$(mktemp -d)
    export CALLS="$stub/calls"; : > "$CALLS"
    make_net_stubs "$stub"
    export FAKE_SSH_FAIL=1 SSH_CMD="$stub/ssh" RSYNC_CMD="$stub/rsync" SCP_CMD="$stub/rsync"
    run "$SENDORBIT_ROOT/modules/transfer.sh" rsync alice host1 22 /home/alice /etc/hostname
    [ "$status" -ne 0 ]
    [[ "$output" == *"Aborting to avoid data loss"* ]]
    ! grep -q '^RSYNC:' "$CALLS"
}

# ====================== transfer.sh: -- separator guards file args ======================

@test "transfer: rsync puts -- separator before file args" {
    local stub; stub=$(mktemp -d)
    export CALLS="$stub/calls"; : > "$CALLS"
    make_net_stubs "$stub"
    export SSH_CMD="$stub/ssh" RSYNC_CMD="$stub/rsync" SCP_CMD="$stub/rsync"
    run "$SENDORBIT_ROOT/modules/transfer.sh" rsync alice host1 22 /home/alice /etc/hostname
    [ "$status" -eq 0 ]
    grep -q -- ' -- /etc/hostname' "$CALLS"
}

@test "transfer: scp puts -- separator before file args" {
    local stub; stub=$(mktemp -d)
    export CALLS="$stub/calls"; : > "$CALLS"
    cat > "$stub/scp" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$CALLS"
exit 0
EOF
    chmod +x "$stub/scp"
    export SSH_CMD=/bin/true SCP_CMD="$stub/scp" RSYNC_CMD=/bin/true
    run "$SENDORBIT_ROOT/modules/transfer.sh" scp alice host1 22 /home/alice /etc/hostname
    [ "$status" -eq 0 ]
    local -a args
    mapfile -t args < "$CALLS"
    [ "${args[3]}" == "--" ]
    [ "${args[4]}" == "/etc/hostname" ]
}

# ====================== transfer.sh: umask 077 on created files ======================

@test "transfer: lock file created under umask 077 lands as 600" {
    local stub; stub=$(mktemp -d)
    export SSH_CMD=/bin/true RSYNC_CMD=/bin/true SCP_CMD=/bin/true
    rm -f "$LOGS_DIR/sendorbit.lock"
    run "$SENDORBIT_ROOT/modules/transfer.sh" scp alice host1 22 /home/alice /etc/hostname
    [ "$status" -eq 0 ]
    [ "$(stat -c %a "$LOGS_DIR/sendorbit.lock")" = "600" ]
}

# ====================== direct invocation: lock + session log ======================

@test "transfer: direct invocation rejected while another instance holds lock" {
    local stub; stub=$(mktemp -d)
    local lock="$LOGS_DIR/sendorbit.lock"
    : > "$lock"
    make_net_stubs "$stub"
    export SSH_CMD="$stub/ssh" RSYNC_CMD="$stub/rsync" SCP_CMD="$stub/rsync"
    exec 9>"$lock"
    flock 9
    run env -u SENDORBIT_SESSION "$SENDORBIT_ROOT/modules/transfer.sh" scp alice host1 22 /home/alice /etc/hostname
    exec 9>&-
    [ "$status" -eq 1 ]
    [[ "$output" == *"holds the lock"* ]]
}

@test "connection: direct invocation rejected while another instance holds lock" {
    local lock="$LOGS_DIR/sendorbit.lock"
    : > "$lock"
    exec 9>"$lock"
    flock 9
    run env -u SENDORBIT_SESSION "$SENDORBIT_ROOT/modules/connection.sh" alice host1 22
    exec 9>&-
    [ "$status" -eq 1 ]
    [[ "$output" == *"holds the lock"* ]]
}

@test "transfer: direct invocation logs session start in security log" {
    local sec="$LOGS_DIR/security.log"
    rm -f "$sec"
    run env -u SENDORBIT_SESSION "$SENDORBIT_ROOT/modules/transfer.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
    grep -q "MODULE .*transfer.sh.* invoked directly" "$sec"
}

@test "transfer: SENDORBIT_SESSION=1 skips lock and session log" {
    local stub; stub=$(mktemp -d)
    local lock="$LOGS_DIR/sendorbit.lock"
    local sec="$LOGS_DIR/security.log"
    : > "$lock"
    rm -f "$sec"
    make_net_stubs "$stub"
    export SSH_CMD="$stub/ssh" RSYNC_CMD="$stub/rsync" SCP_CMD="$stub/rsync"
    exec 9>"$lock"
    flock 9
    run env SENDORBIT_SESSION=1 "$SENDORBIT_ROOT/modules/transfer.sh" scp alice host1 22 /home/alice /etc/hostname
    exec 9>&-
    [ "$status" -eq 0 ]
    ! grep -q "invoked directly" "$sec"
}
