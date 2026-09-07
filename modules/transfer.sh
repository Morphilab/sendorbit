#!/bin/bash
# modules/transfer.sh - SCP and RSync transfers with automatic backup

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

    if [[ $# -lt 5 ]]; then
        printf '%b\n' "${Y}Usage: $0 <type> <user> <host> <port> <dest_path> [files...]${NC}"
        exit 1
    fi

    local type="$1" user="$2" host="$3" port="$4" dest_path="$5"
    shift 5

    if ! validate_secure_host "$host" || ! validate_user "$user" || ! validate_port "$port"; then
        printf '%b\n' "${R}ERROR: Invalid parameters for security reasons${NC}"
        exit 1
    fi

    if ! validate_folder_path "$dest_path"; then
        printf '%b\n' "${R}ERROR: Invalid destination path for security reasons${NC}"
        exit 1
    fi

    printf '%b\n' "${B}Type:${NC} $type"
    printf '%b\n' "${B}Destination:${NC} $user@$host:$port $dest_path/"
    printf '%b' "${B}Files:${NC}"
    local f
    for f; do printf ' %s' "$f"; done
    printf '\n'

    local remote_dest
    remote_dest="${dest_path%/}/"

    local result=0
    case "$type" in
        "scp")
            printf '%b\n' "${Y}Running SCP...${NC}"
            "${SCP_CMD:-scp}" -P "$port" -r -- "$@" "${user}@${host}:${remote_dest}" || result=$?
            ;;
        "rsync")
            printf '%b\n' "${Y}Running RSync with automatic backup...${NC}"
            local timestamp backup_dir ssh_cmd
            timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
            backup_dir="${dest_path%/}/backup/${timestamp}"

            local -a rsync_ssh=("${SSH_CMD:-ssh}" -p "$port")
            printf -v ssh_cmd '%s ' "${rsync_ssh[@]}"
            ssh_cmd="${ssh_cmd% }"

            # Backup dir must exist before rsync --backup-dir writes into it.
            # %q quoting keeps the remote shell from interpreting metacharacters.
            printf '%b\n' "${B}Creating remote backup directory...${NC}"
            if ! "${SSH_CMD:-ssh}" -p "$port" "$user@$host" \
                    "$(printf 'mkdir -p %q' "$backup_dir")"; then
                printf '%b\n' "${R}ERROR: Cannot create remote backup directory. Aborting to avoid data loss.${NC}"
                return 1
            fi

            # Native rsync backup: every file this sync would overwrite or delete
            # is moved into backup_dir (recursive; also covers directory pushes).
            printf '%b\n' "${B}Overwritten remote files will be kept in ${backup_dir}/${NC}"
            printf '%b\n' "${Y}Syncing files...${NC}"
            "${RSYNC_CMD:-rsync}" -avz --backup --backup-dir="${backup_dir}/" \
                --exclude=/backup/ \
                -e "$ssh_cmd" -- "$@" "${user}@${host}:${remote_dest}" || result=$?
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
