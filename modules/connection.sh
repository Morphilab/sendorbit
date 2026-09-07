#!/bin/bash
# modules/connection.sh - Secure SSH connections

set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

source "$PROJECT_ROOT/lib/utils.sh"
source "$PROJECT_ROOT/lib/validation.sh"
source "$PROJECT_ROOT/lib/security.sh"

main() {
    PATH="/usr/local/bin:/usr/bin:/bin"
    export PATH
    umask 077
    if [[ -z "$SSH_CMD" ]]; then
        check_dependencies || exit 1
    fi

    module_session_init
    if [[ -z "${SENDORBIT_SESSION:-}" ]]; then
        log_security "MODULE $0 invoked directly"
    fi

    if [[ $# -lt 2 || $# -gt 3 ]]; then
        printf '%b\n' "${Y}Usage: $0 <user> <host> [port]${NC}"
        exit 1
    fi

    local user="$1" host="$2" port="${3:-22}"

    if ! validate_secure_host "$host" || ! validate_user "$user" || ! validate_port "$port"; then
        printf '%b\n' "${R}ERROR: Invalid parameters for security reasons${NC}"
        exit 1
    fi

    printf '%b\n' ""
    printf '%b\n' "${B}Connecting to $user@$host:$port...${NC}"
    log_security "Starting connection to $user@$host:$port"

    local result=0
    "${SSH_CMD:-ssh}" -p "$port" "$user@$host" || result=$?

    if [[ $result -eq 0 ]]; then
        log_security "Connection closed successfully: $user@$host:$port"
        printf '%b\n' "${G}Connection closed successfully${NC}"
    else
        log_security "Connection failed (code $result): $user@$host:$port"
        printf '%b\n' "${R}Connection failed (code $result)${NC}"
    fi

    return $result
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
