#!/bin/bash
# sendorbit.sh - Modular SSH connection + transfer manager
# Delegates all SSH behavior to ~/.ssh/config

set -euo pipefail

INVOCATION_DIR="$(pwd)"  # user's cwd, preserved across the internal cd below
cd "$(dirname "${BASH_SOURCE[0]}")" || { echo "ERROR: Cannot change to project directory" >&2; exit 1; }
PROJECT_ROOT="$PWD"
export PROJECT_ROOT
CONFIG_DIR="$PROJECT_ROOT/config"
MODULES_DIR="$PROJECT_ROOT/modules"
LIB_DIR="$PROJECT_ROOT/lib"
LOGS_DIR="$PROJECT_ROOT/logs"
LOCK_FILE="$LOGS_DIR/sendorbit.lock"

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
    # Sanitize PATH FIRST — before any command (trap/date/whoami/flock) runs, so a
    # hostile directory cannot hijack binaries via self-env.
    PATH="/usr/local/bin:/usr/bin:/bin"
    export PATH

    trap clean_resources EXIT INT TERM HUP
    trap 'log_error "Unexpected error at line $LINENO: $BASH_COMMAND"' ERR

    umask 077
    mkdir -p "$LOGS_DIR" "$CONFIG_DIR"

    # FD 9 (the flock lock) has no close-on-exec, so every child (ssh/scp/rsync and
    # modules) inherits it and the lock lives on the shared open file description:
    # it stays held until the last holder exits, and nothing else can take it while
    # the session runs. This open fd is what makes single-instance exclusion atomic.
    exec 9>"$LOCK_FILE" || { echo "ERROR: Cannot create lock at $LOCK_FILE" >&2; exit 1; }
    if command -v flock >/dev/null 2>&1; then
        if ! flock -n 9; then
            echo "Another instance of sendorbit is already running"
            exit 1
        fi
    else
        print_color "${Y}WARNING: 'flock' not found — single-instance lock disabled${NC}"
    fi

    # Modules inherit fd 9 (same open file description), so re-locking there would
    # spuriously succeed; they rely on the SENDORBIT_SESSION guard and only take
    # their own lock when invoked directly (see module_session_init in utils.sh).
    export SENDORBIT_SESSION=1

    init_logging
    init_security_log

    log_info "Initializing sendorbit v${VERSION}"
    log_security "Session start - User: $(whoami) - Version: ${VERSION}"

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

    log_info "Loaded ${#configs[@]} hosts from hosts.conf"
}

# ====================== MAIN MENU ======================
show_main_menu() {
    print_color "${G}╔════════════════════════════════════════════╗${NC}"
    print_color "${G}║              sendorbit v${VERSION}              ║${NC}"
    print_color "${G}╚════════════════════════════════════════════╝${NC}"

    if (( ${#configs[@]} == 0 )); then
        print_color "${R}No hosts configured.${NC}"
        print_color "${Y}Edit config/hosts.conf and re-run.${NC}"
        read -r -t 120 -p "Press Enter to exit..." || true
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
    local sel rc
    while true; do
        print_color_n "${B}Host (1-$max) or 'q' to quit: ${NC}"
        rc=0
        safe_read 120 sel || rc=$?
        case $rc in
            124) continue ;;
            1) print_color ""; log_security "Input stream closed"; exit 0 ;;
        esac
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
    local acc rc
    while true; do
        print_color_n "${B}Select action (1-5): ${NC}"
        rc=0
        safe_read 120 acc || rc=$?
        case $rc in
            124) continue ;;
            1) print_color ""; log_security "Input stream closed"; exit 0 ;;
        esac
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
    local confirm

    print_color_n "${B}Files to transfer (space-separated): ${NC}"
    local files_input=""
    local fsrc_rc=0
    safe_read 300 files_input || fsrc_rc=$?
    if (( fsrc_rc != 0 )); then
        print_color "${R}No file list provided (timeout or input closed)${NC}" >&2
        return 1
    fi
    local -a files=()
    read -r -ra files <<< "$files_input"

    # TUI splits input on spaces; a filename with spaces would be silently
    # mis-transferred as its parts. Fail-safe: if the whole input
    # names a single existing file but contains spaces, reject with guidance.
    if [[ "$files_input" == *" "* && -e "$files_input" ]]; then
        print_color "${R}ERROR: TUI does not support filenames with spaces (ambiguous list). Use --transfer instead.${NC}"
        return 1
    fi

    [[ ${#files[@]} -eq 0 ]] && {
        print_color "${R}No files selected${NC}"
        return 1
    }

    validate_transfer_files "${files[@]}" || return 1

    print_color_n "${Y}$type: send ${files[*]} to $user@$host${port:+:$port}:$dest_path/? (y/N): ${NC}"
    confirm=""
    safe_read 60 confirm || true
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
    read -r -t 120 -p "Press Enter to continue..." || true
}

# ====================== CLEANUP ======================
clean_resources() {
    # Lock file is intentionally NOT unlinked: deleting it while another instance
    # may still hold its FD breaks mutual exclusion (classic flock-unlink race).
    log_info "Session finished"
    # Rotate at session close too: log_info runs first so the closing message is
    # never lost to rotation, and a session outliving a rotation interval still
    # leaves rotated files behind instead of one unbounded log.
    rotate_logs
    rotate_security_log
}

# ====================== ACTION PROCESSING ======================
process_action() {
    local user="$1" host="$2" folder="$3" port="${4:-22}" action="$5"
    local confirm

    if ! validate_secure_host "$host" || ! validate_user "$user"; then
        print_color "${R}Invalid host or user for security reasons${NC}"
        return 1
    fi

    local dest_path
    dest_path=$(resolve_dest_path "$folder")

    case "$action" in
        1)
            print_color_n "${Y}Connect to $user@$host${port:+:$port}? (y/N): ${NC}"
            confirm=""
            safe_read 60 confirm || true
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
  $0 --version|-v                             Print version and exit
  $0 --help|-h                                Show this help and exit
  $0 --list                                   List configured hosts and exit
  $0 --connect <user> <host> [port]            Open SSH connection (non-interactive)
  $0 --transfer <scp|rsync> <user> <host> <port> <dest> <file> [files...]
                                               Send files (non-interactive)
  $0 --dry-run --transfer <scp|rsync> <user> <host> <port> <dest> <file> [files...]
                                               Show what would be transferred
  $0 --push-dir --host <index> [--scp] [--dry-run]
                                               Send current directory ($PWD) to a
                                               configured host (rsync + backup by
                                               default; --scp forces SCP)

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

    # Reject a present-but-empty port instead of silently falling back to 22
    if (( $# >= 3 )) && [[ -z "$3" ]]; then
        print_color "${R}ERROR: Port argument is present but empty${NC}" >&2
        exit 1
    fi

    if ! validate_user "$user" || ! validate_secure_host "$host"; then
        print_color "${R}ERROR: Invalid user or host${NC}" >&2
        exit 1
    fi

    if ! validate_port "$port"; then
        print_color "${R}ERROR: Invalid port: $port${NC}" >&2
        exit 1
    fi

    print_color "${B}Connecting to $user@$host${port:+:$port}...${NC}"
    log_security "Non-interactive connect to $user@$host:$port"
    "$MODULES_DIR/connection.sh" "$user" "$host" "$port"
}

run_transfer() {
    if (( $# < 6 )); then
        print_color "${R}Usage: $0 [--dry-run] --transfer <scp|rsync> <user> <host> <port> <dest> <file> [files...]${NC}" >&2
        exit 1
    fi

    # Reject a present-but-empty port; $4 is guaranteed set by the arity check above
    if [[ -z "$4" ]]; then
        print_color "${R}ERROR: Port argument is present but empty${NC}" >&2
        exit 1
    fi

    local type="$1" user="$2" host="$3" port="$4" dest="$5"
    shift 5

    # Whitelist the transfer type before any branch (incl. DRY_RUN) prints it
    if [[ "$type" != "scp" && "$type" != "rsync" ]]; then
        print_color "${R}ERROR: Invalid transfer type: $type${NC}" >&2
        exit 1
    fi

    if ! validate_user "$user" || ! validate_secure_host "$host"; then
        print_color "${R}ERROR: Invalid user or host${NC}" >&2
        exit 1
    fi

    if ! validate_port "$port"; then
        print_color "${R}ERROR: Invalid port: $port${NC}" >&2
        exit 1
    fi

    if ! validate_folder_path "$dest"; then
        print_color "${R}ERROR: Invalid destination path: $dest${NC}" >&2
        exit 1
    fi

    if [[ -n "${DRY_RUN:-}" ]]; then
        print_color "${Y}[DRY-RUN] Would ${type}: $* → $user@$host:$port $dest/${NC}"
        return 0
    fi

    log_security "Non-interactive $type → $user@$host:$port $dest (${#} files)"
    "$MODULES_DIR/transfer.sh" "$type" "$user" "$host" "$port" "$dest" "$@"
}

run_push_dir() {
    local host_idx="" method="rsync"

    while (( $# > 0 )); do
        case "$1" in
            --host)
                [[ $# -lt 2 ]] && { print_color "${R}ERROR: --host requires an argument${NC}" >&2; exit 1; }
                host_idx="$2"
                shift 2
                ;;
            --scp) method="scp"; shift ;;
            --dry-run) DRY_RUN=1; shift ;;
            *) print_color "${R}ERROR: Unknown option for --push-dir: $1${NC}" >&2; exit 1 ;;
        esac
    done

    [[ -z "$host_idx" ]] && {
        print_color "${R}ERROR: --push-dir requires --host <index>${NC}" >&2
        exit 1
    }

    [[ ! "$host_idx" =~ ^[0-9]+$ ]] && {
        print_color "${R}ERROR: --host must be a numeric index (1..${#configs[@]})${NC}" >&2
        exit 1
    }

    (( host_idx < 1 || host_idx > ${#configs[@]} )) && {
        print_color "${R}ERROR: --host index out of range (1..${#configs[@]})${NC}" >&2
        exit 1
    }

    local idx=$((host_idx - 1))
    local user host folder port
    parse_config_entry "$idx" user host folder port

    if ! validate_user "$user" || ! validate_secure_host "$host"; then
        print_color "${R}ERROR: Invalid user or host${NC}" >&2
        exit 1
    fi

    local dest_path
    dest_path=$(resolve_dest_path "$folder")
    local dest_norm="${dest_path%/}/"

    if [[ -n "${DRY_RUN:-}" ]]; then
        print_color "${Y}[DRY-RUN] Would ${method}: $INVOCATION_DIR → $user@$host:$port $dest_norm${NC}"
        return 0
    fi

    log_security "push-dir ${method} → $user@$host:$port $dest_path (cwd: $INVOCATION_DIR)"
    "$MODULES_DIR/transfer.sh" "$method" "$user" "$host" "$port" "$dest_path" "$INVOCATION_DIR"
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
            if (( $# < 2 )); then
                print_color "${R}ERROR: Usage: $0 --connect <user> <host> [port]${NC}" >&2
                exit 1
            fi
            init_system || exit 1
            run_connect "$@"
            exit $?
            ;;
        --transfer)
            shift
            if (( $# < 6 )); then
                print_color "${R}ERROR: Usage: $0 [--dry-run] --transfer <scp|rsync> <user> <host> <port> <dest> <file> [files...]${NC}" >&2
                exit 1
            fi
            init_system || exit 1
            run_transfer "$@"
            exit $?
            ;;
        --dry-run)
            shift
            [[ "${1:-}" == "--transfer" ]] || {
                print_color "${R}ERROR: --dry-run must be followed by --transfer${NC}" >&2
                exit 1
            }
            shift
            init_system || exit 1
            DRY_RUN=1
            run_transfer "$@"
            exit $?
            ;;
        --push-dir)
            shift
            init_system || exit 1
            load_configuration || exit 1
            run_push_dir "$@"
            exit $?
            ;;
        --host)
            print_color "${R}ERROR: --host requires --push-dir${NC}" >&2
            exit 1
            ;;
        "")
            : # no args → interactive TUI (handled after the case)
            ;;
        *)
            print_color "${R}ERROR: Unknown option: ${1:-}${NC}" >&2
            usage
            exit 1
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
        read -r -t 120 -p "Press Enter to return to main menu..." || true
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
