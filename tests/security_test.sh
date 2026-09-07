#!/usr/bin/env bats

load setup

setup_file() {
    mkdir -p "$LOGS_DIR"
}

teardown_file() {
    rm -rf "$LOGS_DIR"
}

# ====================== validate_secure_host ======================

@test "validate_secure_host: accepts normal IP" {
    run validate_secure_host "192.168.1.1"
    [ "$status" -eq 0 ]
}

@test "validate_secure_host: accepts normal hostname" {
    run validate_secure_host "example.com"
    [ "$status" -eq 0 ]
}

@test "validate_secure_host: accepts SSH alias with underscore" {
    run validate_secure_host "prod_web"
    [ "$status" -eq 0 ]
}

@test "validate_secure_host: rejects host with shell metachar ;" {
    run validate_secure_host "host;rm -rf /"
    [ "$status" -eq 1 ]
}

@test "validate_secure_host: rejects host with pipe" {
    run validate_secure_host "host|ls"
    [ "$status" -eq 1 ]
}

@test "validate_secure_host: rejects host with path traversal .." {
    run validate_secure_host "host..evil"
    [ "$status" -eq 1 ]
}

@test "validate_secure_host: rejects host with ampersand" {
    run validate_secure_host "host&whoami"
    [ "$status" -eq 1 ]
}

@test "validate_secure_host: rejects host with redirection >" {
    run validate_secure_host "host>file"
    [ "$status" -eq 1 ]
}

@test "validate_secure_host: rejects host with redirection <" {
    run validate_secure_host "host<file"
    [ "$status" -eq 1 ]
}

@test "validate_secure_host: rejects host with braces {}" {
    run validate_secure_host "host{evil}"
    [ "$status" -eq 1 ]
}

@test "validate_secure_host: rejects host with parentheses" {
    run validate_secure_host "host(evil)"
    [ "$status" -eq 1 ]
}

@test "validate_secure_host: rejects empty host" {
    run validate_secure_host ""
    [ "$status" -eq 1 ]
}

@test "validate_secure_host: rejects host with spaces" {
    run validate_secure_host "my host"
    [ "$status" -eq 1 ]
}

@test "validate_secure_host: rejects host with backtick" {
    run validate_secure_host "host\`whoami\`"
    [ "$status" -eq 1 ]
}

@test "validate_secure_host: rejects host with dollar" {
    run validate_secure_host "host\$PATH"
    [ "$status" -eq 1 ]
}

@test "validate_secure_host: rejects host with newline" {
    run validate_secure_host $'host\nls'
    [ "$status" -eq 1 ]
}

@test "validate_secure_host: rejects host with single quote" {
    run validate_secure_host "host'evil"
    [ "$status" -eq 1 ]
}

@test "validate_secure_host: rejects host with exclamation" {
    run validate_secure_host "host!evil"
    [ "$status" -eq 1 ]
}

@test "validate_secure_host: rejects host with bracket [" {
    run validate_secure_host "host[evil]"
    [ "$status" -eq 1 ]
}

@test "validate_secure_host: rejects host with asterisk" {
    run validate_secure_host "host*evil"
    [ "$status" -eq 1 ]
}

@test "validate_secure_host: rejects host with question mark" {
    run validate_secure_host "host?evil"
    [ "$status" -eq 1 ]
}

@test "validate_secure_host: rejects host with tilde" {
    run validate_secure_host "host~evil"
    [ "$status" -eq 1 ]
}

@test "validate_secure_host: rejects host with tab" {
    run validate_secure_host $'host\tevil'
    [ "$status" -eq 1 ]
}

@test "validate_secure_host: rejects host with carriage return" {
    run validate_secure_host $'host\revil'
    [ "$status" -eq 1 ]
}

@test "validate_secure_host: rejects accented host even under non-C locale" {
    if ! locale -a 2>/dev/null | grep -qi '^es_ES'; then
        skip "es_ES locale not available"
    fi
    LC_ALL=es_ES.UTF-8 run validate_secure_host "hóst"
    [ "$status" -eq 1 ]
}

# ====================== log_security ======================

@test "log_security: writes SECURITY label" {
    run log_security "label verification"
    grep -q "\[SECURITY\]" "$SECURITY_LOG"
}

@test "log_security: writes message content" {
    local test_msg
    test_msg="unique_test_message_$(date +%s)"
    run log_security "$test_msg"
    grep -q "$test_msg" "$SECURITY_LOG"
}

@test "log_security: neutralizes embedded newlines (log forging)" {
    local forged
    forged=$(printf 'host: X\nFAKE-ENTRY without timestamp')
    log_security "$forged"
    run grep -F 'FAKE-ENTRY without timestamp' "$SECURITY_LOG"
    [[ "$status" -ne 0 ]] || {
        # if it appears, it must be INSIDE a single timestamped line, never after \n
        run grep -cE '^FAKE-ENTRY' "$SECURITY_LOG"
        [ "$output" -eq "0" ]
    }
}

@test "log_security: preserves single-line content intact" {
    log_security "keep-me 100% intact"
    run grep -F 'keep-me 100% intact' "$SECURITY_LOG"
    [ "$status" -eq 0 ]
}

@test "init_security_log creates security log with 600 permissions" {
    rm -f "$SECURITY_LOG"
    init_security_log
    [ "$(stat -c %a "$SECURITY_LOG")" = "600" ]
}
