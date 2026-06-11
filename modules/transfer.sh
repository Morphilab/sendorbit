#!/bin/bash
# modules/transfer.sh - SCP and RSync transfers with automatic backup
# sendorbit v1.0.0

set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

source "$PROJECT_ROOT/lib/utils.sh"
source "$PROJECT_ROOT/lib/validation.sh"
source "$PROJECT_ROOT/lib/security.sh"

main() {
    PATH="/usr/local/bin:/usr/bin:/bin"
    export PATH
    if [[ -z "$SSH_CMD" ]]; then
        check_dependencies || exit 1
    fi

    if [[ $# -lt 5 ]]; then
        printf '%b\n' "${Y}Usage: $0 <type> <user> <host> <port> <dest_path> [files...]${NC}"
        exit 1
    fi

    local type="$1" user="$2" host="$3" port="$4" dest_path="$5"
    shift 5

    if ! validate_secure_host "$host" || ! validate_user "$user"; then
        printf '%b\n' "${R}ERROR: Invalid parameters for security reasons${NC}"
        exit 1
    fi

    printf '%b\n' "${B}Type:${NC} $type"
    printf '%b\n' "${B}Destination:${NC} $user@$host:$port $dest_path/"
    printf '%b' "${B}Files:${NC}"
    local f
    for f; do printf ' %s' "$f"; done
    printf '\n'

    local remote_dest
    printf -v remote_dest '%q' "${dest_path}/"

    local result=0
    case "$type" in
        "scp")
            printf '%b\n' "${Y}Running SCP...${NC}"
            "${SCP_CMD:-scp}" -P "$port" -r -- "$@" "${user}@${host}:${remote_dest}" || result=$?
            ;;
        "rsync")
            printf '%b\n' "${Y}Running RSync with automatic backup...${NC}"
            local timestamp
            timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
            local backup_path="${dest_path}/backup/${timestamp}"

            # Explicitly backup existing remote files before rsync overwrites them
            local remote_backup_cmd=""
            local fname qfile qbackup
            for f in "$@"; do
                fname=$(basename "$f")
                printf -v qfile '%q' "${dest_path}/${fname}"
                printf -v qbackup '%q' "$backup_path"
                remote_backup_cmd+="[ -f $qfile ] && mkdir -p $qbackup && cp $qfile $qbackup; "
            done

            if [[ -n "$remote_backup_cmd" ]]; then
                printf '%b\n' "${B}Backing up existing files on remote...${NC}"
                "${SSH_CMD:-ssh}" -p "$port" "$user@$host" \
                    "$remote_backup_cmd" || printf '%b\n' "${Y}WARNING: Some backups may have failed${NC}"
            fi

            local -a rsync_ssh=("${SSH_CMD:-ssh}" -p "$port")
            local ssh_cmd
            printf -v ssh_cmd '%s ' "${rsync_ssh[@]}"
            ssh_cmd="${ssh_cmd% }"
            printf '%b\n' "${Y}Syncing files...${NC}"
            "${RSYNC_CMD:-rsync}" -avz -e "$ssh_cmd" -- "$@" "${user}@${host}:${remote_dest}" || result=$?
            ;;
        *)
            printf '%b\n' "${R}ERROR: Invalid type: $type${NC}"
            exit 1
            ;;
    esac

    if [[ $result -eq 0 ]]; then
        printf '%b\n' "${G}Transfer completed successfully${NC}"
    else
        printf '%b\n' "${R}ERROR: Transfer failed (code $result)${NC}"
    fi
    return $result
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
