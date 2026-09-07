#!/usr/bin/env bats

load setup

@test "safe_read: captures a line from stdin" {
    run bash -c 'source "'"$SENDORBIT_ROOT"'/lib/utils.sh"; safe_read 2 myvar <<< "hello"; echo "rc=$? val=$myvar"'
    [[ "$output" == *"rc=0 val=hello"* ]]
}

@test "safe_read: returns 124 on timeout" {
    run bash -c 'source "'"$SENDORBIT_ROOT"'/lib/utils.sh"; sleep 2 | safe_read 1 myvar; echo "RC=[$?]"'
    [[ "$output" == *"RC=[124]"* ]]
}

@test "safe_read: returns 1 on EOF without hanging" {
    run bash -c 'source "'"$SENDORBIT_ROOT"'/lib/utils.sh"; safe_read 5 myvar </dev/null; echo "RC=[$?]"'
    [[ "$output" == *"RC=[1]"* ]]
}

@test "safe_read: clears target variable even on failure" {
    run bash -c 'source "'"$SENDORBIT_ROOT"'/lib/utils.sh"; myvar="stale"; safe_read 5 myvar </dev/null; echo "val=[$myvar]"'
    [[ "$output" == *"val=[]"* ]]
}

@test "rotate_file: survives stat without GNU -c support under set -e (BSD/macOS)" {
    local stub="$LOGS_DIR/fakebin"
    mkdir -p "$stub"
    printf '#!/bin/sh\nexit 2\n' > "$stub/stat"
    chmod +x "$stub/stat"
    local big="$LOGS_DIR/big.log"
    head -c 20000000 /dev/zero > "$big"
    run bash -ec "
        set -euo pipefail
        source '$SENDORBIT_ROOT/lib/utils.sh'
        PATH='$stub':\$PATH
        rotate_file '$big' 10485760 5
        echo SURVIVED
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"SURVIVED"* ]]
}

@test "check_dependencies: entrypoint overwrites presets; source-time preservation intact" {
    run bash -c '
        export PATH="/usr/local/bin:/usr/bin:/bin"
        export SSH_CMD=/nonexistent/ssh SCP_CMD=/nonexistent/scp RSYNC_CMD=/nonexistent/rsync
        source "'"$SENDORBIT_ROOT"'/lib/utils.sh"
        [[ "$SSH_CMD" == "/nonexistent/ssh" ]] || exit 1
        check_dependencies >/dev/null 2>&1 || exit 9
        [[ "$SSH_CMD" == "/nonexistent/ssh" ]] && exit 2
        [[ -x "$SSH_CMD" && -x "$SCP_CMD" && -x "$RSYNC_CMD" ]] || exit 3
        exit 0
    '
    [ "$status" -eq 0 ]
}
