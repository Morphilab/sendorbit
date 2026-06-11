# shellcheck shell=bash
# lib/security.sh - Security functions - sendorbit v1.0.0

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOGS_DIR="${LOGS_DIR:-$PROJECT_ROOT/logs}"
SECURITY_LOG="${SECURITY_LOG:-$LOGS_DIR/security.log}"

init_security_log() {
    mkdir -p "$LOGS_DIR"
    touch "$SECURITY_LOG"
    chmod 600 "$SECURITY_LOG"
    rotate_security_log
}

MAX_SEC_LOG_SIZE=10485760
MAX_SEC_LOG_FILES=5

rotate_security_log() {
    rotate_file "$SECURITY_LOG" "$MAX_SEC_LOG_SIZE" "$MAX_SEC_LOG_FILES"
}

log_security() {
    local message="$1"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [SECURITY] $message" >> "$SECURITY_LOG"
}

validate_secure_host() {
    local host="$1"

    local dangerous_patterns=(
        "[;&|<>]"
        "\.\."
        "[(){}]"
        '`'
        '\$'
        "'"
        '\!'
        '\]'
        '\['
        '\*'
        '\?'
        '\~'
        $'\n'
        $'\t'
        $'\r'
    )

    for pattern in "${dangerous_patterns[@]}"; do
        if [[ $host =~ $pattern ]]; then
            log_security "Host rejected by dangerous pattern '$pattern': $host"
            return 1
        fi
    done

    if validate_ip "$host" || validate_hostname "$host"; then
        return 0
    fi

    log_security "Host invalid format: $host"
    return 1
}


