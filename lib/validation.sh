# shellcheck shell=bash
# lib/validation.sh - Centralized validations - sendorbit v1.0.0

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$PROJECT_ROOT/lib/utils.sh"

# ====================== CONFIGURATION VALIDATION ======================
validate_configuration() {
    local config_file="$1"
    local entry_re='[[:space:]]*"([^"]*)"[[:space:]]*'
    local line rest

    if [[ ! -f "$config_file" ]]; then
        show_message "Configuration file not found" "ERROR"
        return 1
    fi

    if [[ ! -r "$config_file" ]]; then
        show_message "No read permissions" "ERROR"
        return 1
    fi

    # Parse config entries text-only — no source/exec (prevents code injection)
    configs=()
    local in_array=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        [[ -z "$line" ]] && continue

        # Detect start of configs array (multi-line or single-line)
        if [[ "$line" == "configs=("* ]]; then
            in_array=1
            # Extract entries from same-line: configs=("a" "b")
            rest="${line#configs=(}"
            while [[ "$rest" =~ $entry_re ]]; do
                configs+=("${BASH_REMATCH[1]}")
                rest="${rest#*\"${BASH_REMATCH[1]}\"}"
            done
            [[ "$line" == *")" ]] && in_array=0
            continue
        fi

        [[ "$in_array" -eq 0 ]] && continue
        if [[ "$rest" =~ ^[[:space:]]*\)[[:space:]]*$ ]]; then
            in_array=0
            continue
        fi

        rest="$line"
        while [[ "$rest" =~ $entry_re ]]; do
            configs+=("${BASH_REMATCH[1]}")
            rest="${rest#*\"${BASH_REMATCH[1]}\"}"
        done
    done < "$config_file"

    if (( ${#configs[@]} == 0 )); then
        show_message "No hosts defined in configuration" "ERROR"
        return 1
    fi

    for i in "${!configs[@]}"; do
        if ! validate_config_entry "${configs[$i]}"; then
            show_message "Invalid entry at index $i" "ERROR"
            return 1
        fi
    done

    return 0
}

# ====================== CENTRALIZED VALIDATIONS ======================
validate_user() {
    local user="$1"
    [[ -z "$user" || ${#user} -lt 1 || ${#user} -gt 32 ]] && return 1
    [[ ! "$user" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]] && return 1
    [[ "$user" =~ -$ ]] && return 1
    return 0
}

validate_ip() {
    local ip="$1"
    [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && return 1
    local IFS='.' octets
    read -ra octets <<< "$ip"
    [[ ${#octets[@]} -ne 4 ]] && return 1
    for octet in "${octets[@]}"; do
        [[ "$octet" =~ ^0[0-9] ]] && return 1
        (( 10#$octet < 0 || 10#$octet > 255 )) 2>/dev/null && return 1
    done
    return 0
}

validate_hostname() {
    local hostname="$1"
    [[ "$hostname" =~ ^[a-zA-Z0-9_]([a-zA-Z0-9_-]{0,61}[a-zA-Z0-9_])?(\.[a-zA-Z0-9_]([a-zA-Z0-9_-]{0,61}[a-zA-Z0-9_])?)*$ ]]
}

validate_config_entry() {
    local entry="$1"
    local -a elements
    IFS=' ' read -ra elements <<< "$entry"

    (( ${#elements[@]} < 3 )) && return 1

    local user="${elements[0]}"
    local host="${elements[1]}"
    local folder="${elements[2]}"

    validate_user "$user" || return 1
    (validate_ip "$host" || validate_hostname "$host") || return 1

    [[ "$folder" =~ (^|/)\.\.(/|$) ]] && { show_message "Path traversal detected in folder: $folder" "ERROR"; return 1; }
    [[ "$folder" =~ [\;\`\$\&\|\<\>\(\)\{\}] ]] && { show_message "Dangerous characters in folder: $folder" "ERROR"; return 1; }

    if (( ${#elements[@]} >= 4 )); then
        local port="${elements[3]}"
        [[ ! "$port" =~ ^[0-9]+$ ]] && return 1
        (( port < 1 || port > 65535 )) && return 1
    fi

    return 0
}

validate_transfer_files() {
    local files=("$@")
    (( ${#files[@]} == 0 )) && { show_message "No files specified" "ERROR"; return 1; }

    for file in "${files[@]}"; do
        [[ ! -e "$file" ]] && { show_message "File not found: $file" "ERROR"; return 1; }
        [[ ! -r "$file" ]] && { show_message "No read permissions: $file" "ERROR"; return 1; }
    done
    return 0
}

