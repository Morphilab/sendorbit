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
