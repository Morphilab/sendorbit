#!/bin/bash
# sendorbit.sh - sendorbit v1.0.0
# Modular, secure SSH connection + transfer manager

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || { echo "ERROR: Cannot change to project directory" >&2; exit 1; }
PROJECT_ROOT="$PWD"
export PROJECT_ROOT
CONFIG_DIR="$PROJECT_ROOT/config"
MODULES_DIR="$PROJECT_ROOT/modules"
LIB_DIR="$PROJECT_ROOT/lib"
LOGS_DIR="$PROJECT_ROOT/logs"
LOCK_FILE="$LOGS_DIR/sendorbit.lock"

# ====================== VERSION ======================
# VERSION is defined in lib/utils.sh

# ====================== DEPENDENCY LOADING ======================
load_all_dependencies() {
    source "$LIB_DIR/utils.sh"
    source "$LIB_DIR/validation.sh"
    source "$LIB_DIR/logging.sh"
    source "$LIB_DIR/security.sh"

    local funcs=("validate_user" "validate_secure_host" \
                 "log_info" "log_security" "check_dependencies")
    for f in "${funcs[@]}"; do
        declare -f "$f" > /dev/null || {
            print_color "${R}ERROR: Critical function not available: $f${NC}"
            exit 1
        }
    done
}

load_all_dependencies

# ====================== INITIALIZATION ======================
init_system() {
    trap clean_resources EXIT INT TERM HUP
    trap 'log_error "Unexpected error at line $LINENO: $BASH_COMMAND"' ERR

    mkdir -p "$LOGS_DIR" "$CONFIG_DIR"

    exec 9>"$LOCK_FILE" || { echo "ERROR: Cannot create lock at $LOCK_FILE" >&2; exit 1; }
    if ! flock -n 9; then
        echo "Another instance of sendorbit is already running"
        exit 1
    fi

    init_logging
    init_security_log

    log_info "Initializing sendorbit v${VERSION}"
    log_security "Session start - User: $(whoami) - Version: ${VERSION}"

    # Sanitize PATH before resolving binary paths
    PATH="/usr/local/bin:/usr/bin:/bin"
    export PATH

    check_dependencies || { log_error "Missing dependencies"; return 1; }

    check_file_permissions
}

check_file_permissions() {
    local files=("$CONFIG_DIR/hosts.conf" "$LOGS_DIR/security.log")
    for a in "${files[@]}"; do
        [[ -f "$a" ]] && chmod 600 "$a" 2>/dev/null || true
    done
}

load_configuration() {
    local file="$CONFIG_DIR/hosts.conf"
    [[ ! -f "$file" ]] && {
        print_color "${R}ERROR: config/hosts.conf not found${NC}"
        print_color "${Y}Copy config/example_hosts.conf to config/hosts.conf and edit it${NC}"
        return 1
    }
    validate_configuration "$file" || { log_error "Invalid configuration"; return 1; }

    # shellcheck disable=SC2154
    log_info "Loaded ${#configs[@]} hosts from hosts.conf"
}

# ====================== MAIN MENU ======================
show_main_menu() {
    print_color "${G}╔════════════════════════════════════════════╗${NC}"
    print_color "${G}║              sendorbit v${VERSION}               ║${NC}"
    print_color "${G}╚════════════════════════════════════════════╝${NC}"

    if (( ${#configs[@]} == 0 )); then
        print_color "${R}No hosts configured.${NC}"
        print_color "${Y}Edit config/hosts.conf and re-run.${NC}"
        read -r -t 120 -p "Press Enter to exit..."
        return 1
    fi

    print_color "${B}Available hosts:${NC}"
    show_available_hosts
}

show_available_hosts() {
    for i in "${!configs[@]}"; do
        local -a c
        IFS=' ' read -ra c <<< "${configs[$i]}"
        (( ${#c[@]} < 3 )) && { print_color "${Y}Host index $((i+1)) skipped (invalid format)${NC}"; continue; }
        local user="${c[0]}" host="${c[1]}" folder="${c[2]}" port="${c[3]:-22}"
        local dest_path
        dest_path=$(resolve_dest_path "$folder")

        printf '%b' " ${B}$((i+1)).${NC} $user@${host}${port:+:$port} -> $dest_path\n"
    done
}

get_user_selection() {
    local max=${#configs[@]}
    while true; do
        print_color_n "${B}Host (1-$max) or 'q' to quit: ${NC}"
        read -r -t 120 sel || { print_color "${Y}Input timed out${NC}"; continue; }
        case "$sel" in
            q|Q) log_security "Voluntary exit"; exit 0 ;;
            ''|*[!0-9]*) print_color "${R}Invalid input${NC}" ;;
            *) if (( sel >= 1 && sel <= max )); then
                   HOST_SELECTION="$sel"
                   break
               else
                   print_color "${R}Number out of range${NC}"
               fi ;;
        esac
    done
}

# ====================== ACTIONS MENU ======================
show_actions_menu() {
    print_color "${B}Available actions:${NC}"
    print_color " 1. Connect SSH"
    print_color " 2. Send files (SCP)"
    print_color " 3. Smart sync (RSync + automatic backup)"
    print_color " 4. View system logs"
    print_color " 5. Exit"
}

get_action_selection() {
    while true; do
        print_color_n "${B}Select action (1-5): ${NC}"
        read -r -t 120 acc || { print_color "${Y}Input timed out${NC}"; continue; }
        if [[ "$acc" =~ ^[1-5]$ ]]; then
            ACTION_SELECTION="$acc"
            log_security "Action selected: $acc"
            break
        else
            print_color "${R}Invalid option${NC}"
        fi
    done
}

# ====================== TRANSFERS ======================
manage_transfer() {
    local type="$1" user="$2" host="$3" port="$4" dest_path="$5"

    print_color_n "${B}Files to transfer (space-separated): ${NC}"
    read -r -t 300 -ra files

    [[ ${#files[@]} -eq 0 ]] && {
        print_color "${R}No files selected${NC}"
        return 1
    }

    validate_transfer_files "${files[@]}" || return 1

    print_color_n "${Y}$type: send ${files[*]} to $user@$host${port:+:$port}:$dest_path/? (y/N): ${NC}"
    read -r -t 60 confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { print_color "Transfer cancelled"; return 0; }

    log_security "$type → $user@$host:$port $dest_path"

    "$MODULES_DIR/transfer.sh" "$type" "$user" "$host" "$port" "$dest_path" "${files[@]}"
}

# ====================== LOGS ======================
show_system_logs() {
    clear
    print_color "${B}=== GENERAL LOG (last 100 lines) ===${NC}"
    tail -n 100 "${LOG_FILE:-$LOGS_DIR/sendorbit.log}" 2>/dev/null || echo "No logs yet"
    print_color "${B}=== SECURITY LOG (last 100 lines) ===${NC}"
    tail -n 100 "$LOGS_DIR/security.log" 2>/dev/null || echo "No security logs yet"
    read -r -t 120 -p "Press Enter to continue..."
}

# ====================== CLEANUP ======================
clean_resources() {
    log_info "Cleaning temporary resources..."
    rm -f "$LOCK_FILE" 2>/dev/null || true
}

# ====================== ACTION PROCESSING ======================
process_action() {
    local user="$1" host="$2" folder="$3" port="${4:-22}" action="$5"

    if ! validate_secure_host "$host" || ! validate_user "$user"; then
        print_color "${R}Invalid host or user for security reasons${NC}"
        return 1
    fi

    local dest_path
    dest_path=$(resolve_dest_path "$folder")

    case "$action" in
        1)
            print_color_n "${Y}Connect to $user@$host${port:+:$port}? (y/N): ${NC}"
            read -r -t 60 confirm
            [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { print_color "Connection cancelled"; return 0; }
            "$MODULES_DIR/connection.sh" "$user" "$host" "$port"
            ;;
        2) manage_transfer scp "$user" "$host" "$port" "$dest_path" ;;
        3) manage_transfer rsync "$user" "$host" "$port" "$dest_path" ;;
        4) show_system_logs ;;
        5) log_security "Program exit"; exit 0 ;;
        *) print_color "${R}Action not implemented${NC}" ;;
    esac
}

# ====================== NON-INTERACTIVE MODE ======================
usage() {
    cat <<EOF
sendorbit v${VERSION} — SSH connection and transfer manager

Usage:
  $0                                          Interactive TUI mode
  $0 --version                                Print version and exit
  $0 --help                                   Show this help and exit
  $0 --list                                   List configured hosts and exit
  $0 --connect <user> <host> [port]            Open SSH connection (non-interactive)
  $0 --transfer <scp|rsync> <user> <host> <port> <dest> [files...]
                                               Send files (non-interactive)
  $0 --dry-run --transfer <scp|rsync> <user> <host> <port> <dest> [files...]
                                               Show what would be transferred

Configuration: config/hosts.conf
All SSH options (timeout, keepalive, host-key verification, etc.) are
read from ~/.ssh/config. sendorbit does not inject any SSH options.

See README.md for details.
EOF
}

list_hosts() {
    local i
    for i in "${!configs[@]}"; do
        local -a c
        IFS=' ' read -ra c <<< "${configs[$i]}"
        (( ${#c[@]} < 3 )) && { printf '  [%d] (invalid format) %s\n' "$((i+1))" "${configs[$i]}"; continue; }
        local user="${c[0]}" host="${c[1]}" folder="${c[2]}" port="${c[3]:-22}"
        local dest_path
        dest_path=$(resolve_dest_path "$folder")
        printf '  [%d] %s@%s%s -> %s\n' "$((i+1))" "$user" "$host" "${port:+:$port}" "$dest_path"
    done
}

run_connect() {
    local user="$1" host="$2" port="${3:-22}"

    if ! validate_user "$user" || ! validate_secure_host "$host"; then
        print_color "${R}ERROR: Invalid user or host${NC}" >&2
        exit 1
    fi

    print_color "${B}Connecting to $user@$host${port:+:$port}...${NC}"
    log_security "Non-interactive connect to $user@$host:$port"
    "$MODULES_DIR/connection.sh" "$user" "$host" "$port"
}

run_transfer() {
    local dry_run="${1:-}"
    shift
    [[ "$dry_run" == "--dry-run" ]] && { DRY_RUN=1; shift; }

    if (( $# < 6 )); then
        print_color "${R}Usage: $0 --transfer <scp|rsync> <user> <host> <port> <dest> [files...]${NC}" >&2
        exit 1
    fi

    local type="$1" user="$2" host="$3" port="$4" dest="$5"
    shift 5

    if ! validate_user "$user" || ! validate_secure_host "$host"; then
        print_color "${R}ERROR: Invalid user or host${NC}" >&2
        exit 1
    fi

    if [[ -n "${DRY_RUN:-}" ]]; then
        print_color "${Y}[DRY-RUN] Would ${type}: $* → $user@$host:$port $dest/${NC}"
        return 0
    fi

    log_security "Non-interactive $type → $user@$host:$port $dest (${#} files)"
    "$MODULES_DIR/transfer.sh" "$type" "$user" "$host" "$port" "$dest" "$@"
}

# ====================== MAIN ======================
main() {
    case "${1:-}" in
        --version|-v)
            echo "sendorbit v${VERSION}"
            exit 0
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --list)
            init_system || exit 1
            load_configuration || exit 1
            list_hosts
            exit 0
            ;;
        --connect)
            shift
            init_system || exit 1
            run_connect "$@"
            exit $?
            ;;
        --transfer)
            shift
            init_system || exit 1
            run_transfer "$@"
            exit $?
            ;;
        --dry-run)
            shift
            init_system || exit 1
            run_transfer --dry-run "$@"
            exit $?
            ;;
    esac

    init_system || exit 1
    load_configuration || exit 1

    clear
    while true; do
        show_main_menu || exit 1
        get_user_selection
        local idx=$((HOST_SELECTION - 1))

        local user host folder port
        parse_config_entry "$idx" user host folder port

        echo ""
        print_color "${B}SELECTED HOST${NC}"
        print_color "User      : $user"
        print_color "Host      : $host${port:+:$port}"
        local dest_path
        dest_path=$(resolve_dest_path "$folder")
        print_color "Destination: $dest_path"

        echo ""
        show_actions_menu
        get_action_selection

        process_action "$user" "$host" "$folder" "$port" "$ACTION_SELECTION" || print_color "${R}Action finished with errors${NC}"

        echo ""
        read -r -t 120 -p "Press Enter to return to main menu..."
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
