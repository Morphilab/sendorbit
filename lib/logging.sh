# shellcheck shell=bash
# lib/logging.sh - Logging system - sendorbit v1.0.0

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$PROJECT_ROOT/lib/utils.sh"

LOGS_DIR="${LOGS_DIR:-$PROJECT_ROOT/logs}"
LOG_FILE="${LOG_FILE:-$LOGS_DIR/sendorbit.log}"
MAX_LOG_SIZE=10485760  # 10MB
MAX_LOG_FILES=5

LOG_ERROR=1
LOG_WARNING=2
LOG_INFO=3
LOG_DEBUG=4

LOG_LEVEL="${LOG_LEVEL:-$LOG_INFO}"

init_logging() {
    mkdir -p "$LOGS_DIR"
    rotate_logs
}

rotate_logs() {
    rotate_file "$LOG_FILE" "$MAX_LOG_SIZE" "$MAX_LOG_FILES"
}

write_log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    if [[ $level -le $LOG_LEVEL ]]; then
        local level_label=""
        case "$level" in
            "$LOG_ERROR")  level_label="ERROR"  ;;
            "$LOG_WARNING") level_label="WARNING" ;;
            "$LOG_INFO")   level_label="INFO"    ;;
            "$LOG_DEBUG")  level_label="DEBUG"   ;;
        esac

        echo "[$timestamp] [$level_label] $message" >> "$LOG_FILE"
    fi
}

log_error()   { write_log "$LOG_ERROR" "$1"; }
log_warning() { write_log "$LOG_WARNING" "$1"; }
log_info()    { write_log "$LOG_INFO" "$1"; }
log_debug()   { write_log "$LOG_DEBUG" "$1"; }

# init_logging removed — called explicitly from sendorbit.sh init_system