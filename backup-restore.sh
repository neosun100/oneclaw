#!/bin/bash
# ============================================================================
# OneClaw Backup & Restore
# ============================================================================
# Usage:
#   bash backup-restore.sh backup              # Create backup
#   bash backup-restore.sh backup /path/to     # Backup to specific dir
#   bash backup-restore.sh restore backup.tar.gz  # Restore from backup
#   bash backup-restore.sh list                # List available backups
# ============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

BACKUP_DIR="${HOME}/Documents/OneClaw/backups"
OPENCLAW_DIR="${HOME}/.openclaw"

# Directories/files to back up
BACKUP_SOURCES=(
    "$HOME/.aws"
    "$HOME/.claude/settings.json"
    "$HOME/.mcp.json"
    "$OPENCLAW_DIR/openclaw.json"
    "$OPENCLAW_DIR/workspace"
    "$OPENCLAW_DIR/scripts"
)

do_backup() {
    local dest_dir="${1:-$BACKUP_DIR}"
    mkdir -p "$dest_dir"

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${dest_dir}/oneclaw-backup-${timestamp}.tar.gz"

    info "Creating backup..."

    # Build list of existing sources
    local sources=()
    for src in "${BACKUP_SOURCES[@]}"; do
        if [ -e "$src" ]; then
            sources+=("$src")
        else
            warn "Skipping (not found): $src"
        fi
    done

    if [ ${#sources[@]} -eq 0 ]; then
        error "Nothing to back up. Is OneClaw installed?"
    fi

    tar -czf "$backup_file" "${sources[@]}" 2>/dev/null

    local size
    size=$(du -h "$backup_file" | cut -f1)
    success "Backup created: $backup_file ($size)"
    echo ""
    echo -e "  ${BOLD}Restore with:${NC}"
    echo -e "  ${CYAN}bash backup-restore.sh restore $backup_file${NC}"
}

do_restore() {
    local backup_file="$1"

    [ -f "$backup_file" ] || error "Backup file not found: $backup_file"

    info "Restoring from: $backup_file"

    # Safety: back up current config first
    local safety_backup="/tmp/oneclaw-pre-restore-$(date +%s).tar.gz"
    do_backup "/tmp" 2>/dev/null && info "Current config saved to $safety_backup" || true

    # Extract (paths are absolute in the tar)
    tar -xzf "$backup_file" -C / 2>/dev/null || tar -xzf "$backup_file" 2>/dev/null

    success "Restore complete from: $(basename "$backup_file")"
    echo ""
    echo -e "  ${YELLOW}Please restart OneClaw services:${NC}"
    if [ "$(uname)" = "Darwin" ]; then
        echo -e "  ${CYAN}bash ~/Documents/OneClaw/repair.command${NC}"
    else
        echo -e "  ${CYAN}systemctl --user restart openclaw-gateway openclaw-node${NC}"
    fi
}

do_list() {
    local search_dir="${1:-$BACKUP_DIR}"

    if [ ! -d "$search_dir" ]; then
        info "No backups found in $search_dir"
        return
    fi

    local count
    count=$(find "$search_dir" -name "oneclaw-backup-*.tar.gz" 2>/dev/null | wc -l)

    if [ "$count" -eq 0 ]; then
        info "No backups found in $search_dir"
        return
    fi

    echo -e "${BOLD}Available backups in $search_dir:${NC}"
    echo ""
    find "$search_dir" -name "oneclaw-backup-*.tar.gz" -exec ls -lh {} \; 2>/dev/null | \
        awk '{printf "  %s  %s\n", $5, $NF}'
    echo ""
    echo -e "  ${BOLD}Total:${NC} $count backup(s)"
}

show_usage() {
    echo "Usage: bash backup-restore.sh <command> [args]"
    echo ""
    echo "Commands:"
    echo "  backup [dir]          Create backup (default: ~/Documents/OneClaw/backups/)"
    echo "  restore <file>        Restore from a backup file"
    echo "  list [dir]            List available backups"
    echo ""
    echo "What gets backed up:"
    echo "  ~/.aws/               AWS credentials & config"
    echo "  ~/.claude/settings.json  Claude Code settings"
    echo "  ~/.mcp.json           MCP server config"
    echo "  ~/.openclaw/openclaw.json  OpenClaw config"
    echo "  ~/.openclaw/workspace/     Workspace files"
    echo "  ~/.openclaw/scripts/       Guardian & repair scripts"
}

# --- Main ---
case "${1:-}" in
    backup)  do_backup "${2:-}" ;;
    restore)
        [ -z "${2:-}" ] && error "Usage: bash backup-restore.sh restore <file>"
        do_restore "$2"
        ;;
    list)    do_list "${2:-}" ;;
    *)       show_usage ;;
esac
