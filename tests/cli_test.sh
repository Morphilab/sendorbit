#!/usr/bin/env bats

load setup

# sendorbit.sh resets LOGS_DIR to "$PROJECT_ROOT/logs" when sourced; preserve
# the isolated temp dir from setup.bash so tests never touch the real logs/.
ISOLATED_LOGS_DIR="$LOGS_DIR"
source "$SENDORBIT_ROOT/sendorbit.sh"
export LOGS_DIR="$ISOLATED_LOGS_DIR"

setup() {
    configs=("alice host1 /home/alice 22")
    unset DRY_RUN
}

make_stub() {
    local stub
    stub=$(mktemp -d)
    cat > "$stub/transfer.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$RECORD_FILE"
EOF
    chmod +x "$stub/transfer.sh"
    export RECORD_FILE="$stub/args"
    : > "$RECORD_FILE"
    export MODULES_DIR="$stub"
}

# ====================== run_transfer: argument alignment ======================

@test "run_transfer: plain call passes aligned args to module (regression)" {
    make_stub
    run run_transfer scp alice host1 22 /home/alice fileA.txt
    [ "$status" -eq 0 ]

    local -a recorded
    mapfile -t recorded < "$RECORD_FILE"
    [ "${recorded[0]}" == "scp" ]
    [ "${recorded[1]}" == "alice" ]
    [ "${recorded[2]}" == "host1" ]
    [ "${recorded[3]}" == "22" ]
    [ "${recorded[4]}" == "/home/alice" ]
    [ "${recorded[5]}" == "fileA.txt" ]
}

@test "run_transfer: works with exactly one file (regression)" {
    make_stub
    run run_transfer rsync alice host1 22 /home/alice fileA.txt
    [ "$status" -eq 0 ]
    grep -q "^rsync$" "$RECORD_FILE"
}

@test "run_transfer: requires six positional arguments minimum" {
    make_stub
    run run_transfer scp alice host1 22 /home/alice
    [ "$status" -eq 1 ]
}

@test "run_transfer: DRY_RUN prints preview without invoking module" {
    make_stub
    DRY_RUN=1
    run run_transfer scp alice host1 22 /home/alice fileA.txt
    unset DRY_RUN
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY-RUN]"* ]]
    [ ! -s "$RECORD_FILE" ]
}

# ====================== run_transfer: port/dest validation ======================

@test "run_transfer: rejects invalid port" {
    make_stub
    run run_transfer scp alice host1 '22;calc' /home/alice fileA.txt
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid port"* ]]
    [ ! -s "$RECORD_FILE" ]
}

@test "run_transfer: rejects out-of-range port" {
    make_stub
    run run_transfer scp alice host1 99999 /home/alice fileA.txt
    [ "$status" -eq 1 ]
}

@test "run_transfer: rejects empty port argument" {
    make_stub
    run run_transfer scp alice host1 "" /home/alice fileA.txt
    [ "$status" -eq 1 ]
    [[ "$output" == *"Port argument is present but empty"* ]]
    [ ! -s "$RECORD_FILE" ]
}

@test "run_transfer: rejects destination with traversal" {
    make_stub
    run run_transfer scp alice host1 22 ../etc fileA.txt
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid destination"* ]]
    [ ! -s "$RECORD_FILE" ]
}

@test "run_transfer: rejects destination with newline injection" {
    make_stub
    run run_transfer scp alice host1 22 "$(printf 'x\nMALICIOUS')" fileA.txt
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid destination"* ]]
    [ ! -s "$RECORD_FILE" ]
}

@test "run_transfer: rejects unknown transfer type" {
    make_stub
    run run_transfer weird alice host1 22 /home/alice fileA.txt
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid transfer type"* ]]
    [ ! -s "$RECORD_FILE" ]
}

@test "run_transfer: rejects unknown type even under DRY_RUN" {
    make_stub
    DRY_RUN=1
    run run_transfer weird alice host1 22 /home/alice fileA.txt
    unset DRY_RUN
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid transfer type"* ]]
    [ ! -s "$RECORD_FILE" ]
}

@test "run_connect: rejects invalid port" {
    run run_connect alice host1 '22;calc'
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid port"* ]]
}

@test "run_connect: rejects empty port argument" {
    run run_connect alice host1 ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"Port argument is present but empty"* ]]
}

# ====================== clean_resources: lockfile lifecycle ======================

@test "clean_resources does not delete the lock file (flock-unlink race)" {
    touch "$LOGS_DIR/sendorbit.lock"
    LOCK_FILE="$LOGS_DIR/sendorbit.lock"
    run clean_resources
    [ "$status" -eq 0 ]
    [ -f "$LOCK_FILE" ]
}

@test "clean_resources rotates oversized logs on session close" {
    head -c 11000000 /dev/zero >> "$LOG_FILE"
    rm -f "$LOG_FILE.1"
    run clean_resources
    [ "$status" -eq 0 ]
    [ -f "$LOG_FILE.1" ]
}

# ====================== manage_transfer: input contract ======================

@test "manage_transfer: reads file list through safe_read contract" {
    run bash -c '
        source "'"$SENDORBIT_ROOT"'/sendorbit.sh" >/dev/null 2>&1
        set +e   # capture rc instead of letting errexit abort before the check below
        SAFE_READ_CALLED=0
        safe_read() { SAFE_READ_CALLED=1; return 1; }   # simulated EOF
        manage_transfer scp alice host1 22 /tmp </dev/null
        rc=$?
        [ "$SAFE_READ_CALLED" -eq 1 ] || { echo "FAIL: safe_read not used"; exit 99; }
        exit $rc
    '
    [ "$status" -eq 1 ]
    [[ "$output" != *"FAIL: safe_read not used"* ]]
}

@test "manage_transfer: aborts on single filename with spaces instead of mis-transferring parts" {
    local tmpdir mods
    tmpdir=$(mktemp -d)
    : > "$tmpdir/mi"
    : > "$tmpdir/archivo.txt"
    : > "$tmpdir/mi archivo.txt"
    mods=$(mktemp -d)
    cat > "$mods/transfer.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >> "$RECORD_FILE"
EOF
    chmod +x "$mods/transfer.sh"
    export RECORD_FILE="$mods/args"
    : > "$RECORD_FILE"
    export MODS_STUB="$mods"

    run bash -c '
        source "'"$SENDORBIT_ROOT"'/sendorbit.sh" >/dev/null 2>&1
        MODULES_DIR="$MODS_STUB"   # sendorbit.sh clobbers MODULES_DIR at source time
        cd "'"$tmpdir"'"
        set +e   # capture rc instead of letting errexit abort before the check below
        SAFE_READ_CALLED=0
        safe_read() {   # feed "mi archivo.txt", then confirm "y"
            local -n _out="$2"
            if (( SAFE_READ_CALLED++ == 0 )); then
                _out="mi archivo.txt"
            else
                _out="y"
            fi
            return 0
        }
        manage_transfer scp alice host1 22 /home/alice
        rc=$?
        if [[ -s "$RECORD_FILE" ]]; then
            echo "FAIL: module invoked with: $(cat "$RECORD_FILE")"
            exit 98
        fi
        exit $rc
    '
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not support filenames with spaces"* ]]
    [[ "$output" != *"FAIL: module invoked"* ]]
}

@test "manage_transfer: confirm read failure fails safe, module not invoked" {
    local tmpdir mods
    tmpdir=$(mktemp -d)
    : > "$tmpdir/fileA.txt"
    mods=$(mktemp -d)
    cat > "$mods/transfer.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >> "$RECORD_FILE"
EOF
    chmod +x "$mods/transfer.sh"
    export RECORD_FILE="$mods/args"
    : > "$RECORD_FILE"
    export MODS_STUB="$mods"

    run bash -c '
        source "'"$SENDORBIT_ROOT"'/sendorbit.sh" >/dev/null 2>&1
        MODULES_DIR="$MODS_STUB"   # sendorbit.sh clobbers MODULES_DIR at source time
        cd "'"$tmpdir"'"
        set +e   # capture rc instead of letting errexit abort before the check below
        SAFE_READ_CALLED=0
        safe_read() {   # file list ok, then the confirm read FAILS (timeout/EOF)
            local -n _out="$2"
            if (( SAFE_READ_CALLED++ == 0 )); then
                _out="fileA.txt"
                return 0
            fi
            _out=""
            return 1
        }
        manage_transfer scp alice host1 22 /home/alice
        rc=$?
        if [[ -s "$RECORD_FILE" ]]; then
            echo "FAIL: module invoked"
            exit 98
        fi
        exit $rc
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Transfer cancelled"* ]]
    [[ "$output" != *"FAIL: module invoked"* ]]
}

@test "process_action: connect confirm read failure cancels without invoking module" {
    local mods
    mods=$(mktemp -d)
    cat > "$mods/connection.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >> "$RECORD_FILE"
EOF
    chmod +x "$mods/connection.sh"
    export RECORD_FILE="$mods/args"
    : > "$RECORD_FILE"
    export MODS_STUB="$mods"

    run bash -c '
        source "'"$SENDORBIT_ROOT"'/sendorbit.sh" >/dev/null 2>&1
        MODULES_DIR="$MODS_STUB"   # sendorbit.sh clobbers MODULES_DIR at source time
        set +e   # capture rc instead of letting errexit abort before the check below
        safe_read() {   # confirm read FAILS (timeout/EOF)
            local -n _out="$2"
            _out=""
            return 1
        }
        process_action alice host1 /home/alice 22 1
        rc=$?
        if [[ -s "$RECORD_FILE" ]]; then
            echo "FAIL: connection module invoked"
            exit 98
        fi
        exit $rc
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Connection cancelled"* ]]
    [[ "$output" != *"FAIL: connection module invoked"* ]]
}

# ====================== init_system: PATH sanitization ======================

@test "init_system: resolves binaries from sanitized PATH, not hostile inherited PATH" {
    local hostile; hostile=$(mktemp -d)
    cat > "$hostile/ssh" <<'EOF'
#!/bin/bash
printf 'HOSTILE-SSH\n' > "$MARKER"
EOF
    chmod +x "$hostile/ssh"
    export HOSTILE_DIR="$hostile"
    export MARKER="$hostile/marker"
    : > "$MARKER"

    run bash -c '
        source "'"$SENDORBIT_ROOT"'/sendorbit.sh" >/dev/null 2>&1
        unset SSH_CMD SCP_CMD RSYNC_CMD
        PATH="$HOSTILE_DIR:$PATH"
        export PATH
        init_system
        if [[ "$SSH_CMD" == "$HOSTILE_DIR/ssh" ]]; then
            echo "FAIL: hostile ssh shim resolved"
            exit 97
        fi
        resolved=$(type -P ssh)
        if [[ "$resolved" == "$HOSTILE_DIR/ssh" ]]; then
            echo "FAIL: ssh on sanitized PATH resolves to hostile shim"
            exit 96
        fi
        exit 0
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *"FAIL: hostile ssh shim resolved"* ]]
    [[ "$output" != *"FAIL: ssh on sanitized PATH resolves to hostile shim"* ]]
    [ ! -s "$MARKER" ]
}

# ====================== main: arity and unknown flags ======================

@test "main: --connect without args exits 1 with usage" {
    run main --connect
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "main: --connect with single arg exits 1 with usage" {
    run main --connect alice
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "main: --transfer without args exits 1 with usage" {
    run main --transfer
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "main: unknown flag exits 1 with error" {
    CONFIG_DIR="$(mktemp -d)"
    run main --foo
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "main: no args still reaches interactive TUI (no false unknown-flag error)" {
    CONFIG_DIR="$(mktemp -d)"
    run main </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" != *"Unknown option"* ]]
}
