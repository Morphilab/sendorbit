#!/usr/bin/env bats

load setup

setup_file() {
    mkdir -p "$LOGS_DIR"
}

teardown_file() {
    rm -rf "$LOGS_DIR"
}

@test "log_info: writes INFO message to log" {
    log_info "test info message"
    grep -q "INFO.*test info message" "$LOG_FILE"
}

@test "log_error: writes ERROR message to log" {
    log_error "test error message"
    grep -q "ERROR.*test error message" "$LOG_FILE"
}

@test "log_security: writes message to security.log" {
    log_security "test security event"
    grep -q "SECURITY.*test security event" "$SECURITY_LOG"
}

@test "write_log: neutralizes embedded newlines (log forging)" {
    local forged
    forged=$(printf 'file: X\nFAKE-LOG-ENTRY')
    log_warning "$forged"
    run grep -F 'FAKE-LOG-ENTRY' "$LOG_FILE"
    [[ "$status" -ne 0 ]] || {
        run grep -cE '^FAKE-LOG-ENTRY' "$LOG_FILE"
        [ "$output" -eq "0" ]
    }
}

@test "write_log: preserves single-line content intact" {
    log_warning "keep-this 100% intact"
    run grep -F 'keep-this 100% intact' "$LOG_FILE"
    [ "$status" -eq 0 ]
}

@test "init_logging creates general log with 600 permissions" {
    rm -f "$LOG_FILE"
    init_logging
    [ "$(stat -c %a "$LOG_FILE")" = "600" ]
}

@test "init_logging forces 600 on log regardless of caller umask" {
    rm -f "$LOG_FILE"
    ( umask 022
      init_logging
    )
    [ "$(stat -c %a "$LOG_FILE")" = "600" ]
}
