# shellcheck shell=bash
# lib/utils.sh - Utilities

VERSION="1.0.4"  # single source of truth for the project version

# Command paths may be pre-set in the environment (wrapper scripts / tests);
# modules re-resolve them via check_dependencies only when empty.
SSH_CMD="${SSH_CMD-}"
SCP_CMD="${SCP_CMD-}"
RSYNC_CMD="${RSYNC_CMD-}"

R="${R:-$'\033[1;31m'}"
G="${G:-$'\033[1;32m'}"
Y="${Y:-$'\033[1;33m'}"
B="${B:-$'\033[1;34m'}"
NC="${NC:-$'\033[0m'}"

print_color()  { printf '%b\n' "$@"; }
print_color_n() { printf '%b'   "$@"; }

# Read one line with a timeout. Contract: returns 0 on success, 124 on timeout
# (after printing a notice), 1 on EOF/read error; the output variable is always
# reset to "" first, so callers never see stale data on failure. Under set -e,
# callers must capture the return code (`safe_read ... || rc=$?`) — a bare call
# aborts the script on timeout/EOF.
safe_read() {
    local timeout="$1"
    local -n _out="$2"
    _out=""
    local rc=0
    read -r -t "$timeout" _out || rc=$?
    (( rc > 128 )) && { print_color "${Y}Input timed out${NC}"; return 124; }
    (( rc != 0 )) && return 1
    return 0
}

show_message() {
    local message="$1"
    local type="${2:-INFO}"

    case "$type" in
        "ERROR") print_color "${R}ERROR: $message${NC}" >&2 ;;
        "WARNING") print_color "${Y}WARNING: $message${NC}" ;;
        "SUCCESS") print_color "${G}SUCCESS: $message${NC}" ;;
        "INFO") print_color "${B}INFO: $message${NC}" ;;
        *) print_color "$message" ;;
    esac
}

check_dependencies() {
    local deps=("ssh" "scp" "rsync")
    local missing=()
    local cmd_path

    for dep in "${deps[@]}"; do
        if cmd_path=$(command -v "$dep" 2>/dev/null); then
            case "$dep" in
                ssh) SSH_CMD="$cmd_path" ;;
                scp) SCP_CMD="$cmd_path" ;;
                rsync) RSYNC_CMD="$cmd_path" ;;
            esac
        else
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        show_message "Missing dependencies: ${missing[*]}" "ERROR"
        return 1
    fi

    return 0
}

parse_config_entry() {
    local idx=$1
    local -n _user=$2 _host=$3 _folder=$4 _port=$5
    local -a _c
    IFS=' ' read -ra _c <<< "${configs[$idx]}"
    _user="${_c[0]}"
    _host="${_c[1]}"
    _folder="${_c[2]}"
    _port="${_c[3]:-22}"
}

resolve_dest_path() {
    local folder=$1
    if [[ "$folder" == /* ]]; then
        echo "$folder"
    else
        echo "${HOME:-/root}/$folder"
    fi
}

rotate_file() {
    local file_path="$1"
    local max_size="$2"
    local max_files="$3"

    if [[ ! -f "$file_path" ]]; then
        return 0
    fi

    local size=0
    if command -v stat &>/dev/null; then
        size=$(stat -c%s "$file_path" 2>/dev/null || true)
        [[ -z "$size" ]] && size=$(stat -f%z "$file_path" 2>/dev/null || true)
    fi
    [[ -z "$size" ]] && size=$(wc -c < "$file_path" 2>/dev/null || echo 0)

    if [[ $size -le $max_size ]]; then
        return 0
    fi

    local i old_log new_log
    for ((i=max_files-1; i>0; i--)); do
        old_log="${file_path}.${i}"
        new_log="${file_path}.$((i+1))"
        if [[ -f "$old_log" ]]; then
            mv "$old_log" "$new_log" 2>/dev/null || echo "Warning: could not rotate $old_log" >&2
        fi
    done
    mv "$file_path" "${file_path}.1" 2>/dev/null || echo "Warning: could not rotate $file_path" >&2
}

module_session_init() {
    # sendorbit.sh exports SENDORBIT_SESSION=1 when it already holds the lock;
    # a module invoked directly must protect itself. The env guard is load-bearing:
    # a child inherits the parent's fd 9 (same open file description), so a plain
    # flock -n there would spuriously succeed under sendorbit.sh.
    if [[ -z "${SENDORBIT_SESSION:-}" ]]; then
        local lock_dir="${LOGS_DIR:-$PROJECT_ROOT/logs}"
        mkdir -p "$lock_dir"
        exec 9>"$lock_dir/sendorbit.lock"
        if command -v flock >/dev/null 2>&1; then
            flock -n 9 || {
                printf '%b\n' "${R}ERROR: another sendorbit instance holds the lock${NC}" >&2
                exit 1
            }
        fi
    fi
}

