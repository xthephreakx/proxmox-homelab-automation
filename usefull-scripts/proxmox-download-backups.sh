#!/usr/bin/env bash
set -euo pipefail

# ==============================
# proxmox-download-backups.sh
# ==============================
# Download Docker VM backups van de Proxmox host naar je Mac.
# Backups worden aangemaakt door proxmox-backup-docker-files.sh (dagelijks 07:00).
#
# Gebruik:
#   ./proxmox-download-backups.sh           # download nieuwste backup
#   ./proxmox-download-backups.sh --all     # download alle backups die lokaal ontbreken
#   ./proxmox-download-backups.sh --list    # toon beschikbare backups (geen download)
# ==============================

PVE_HOST="192.168.187.48"
PVE_USER="root"
SSH_KEY="$HOME/.ssh/proxmox_vm_key"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10"
REMOTE_BACKUP_DIR="/root/backups"
LOCAL_BACKUP_DIR="$(cd "$(dirname "$0")/../backups" && pwd)"

# ==============================
# Kleuren
# ==============================
BLUE_90='\033[38;2;0;162;255m'
GREEN_90='\033[38;2;0;254;162m'
MAGENTA_90='\033[38;2;255;0;124m'
RED_90='\033[38;2;255;0;54m'
YELLOW_90='\033[38;2;255;211;0m'
NC='\033[0m'

SPINNER_PID=""

spinner() {
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while true; do
        printf "\r  ${YELLOW_90}${spin[$i]}${NC} %s" "$1"
        i=$(( (i + 1) % ${#spin[@]} ))
        sleep 0.1
    done
}

stop_spinner() {
    if [[ -n "${SPINNER_PID:-}" ]]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
        printf "\r\033[K"
    fi
}

info()    { stop_spinner; spinner "$1" & SPINNER_PID=$!; tput civis 2>/dev/null || true; }
success() { stop_spinner; printf "  ${GREEN_90}✓${NC} %s\n" "$1"; tput cnorm 2>/dev/null || true; }
fail()    { stop_spinner; printf "  ${RED_90}✗${NC} %s\n" "$1"; tput cnorm 2>/dev/null || true; exit 1; }
warn()    { stop_spinner; printf "  ${YELLOW_90}!${NC} %s\n" "$1"; tput cnorm 2>/dev/null || true; }
step()    { stop_spinner; printf "\n${MAGENTA_90}▶${NC} %s\n" "$1"; }

trap 'stop_spinner; tput cnorm 2>/dev/null || true' EXIT

# ==============================
# Args
# ==============================
MODE="newest"
[[ "${1:-}" == "--all" ]]  && MODE="all"
[[ "${1:-}" == "--list" ]] && MODE="list"

# ==============================
# Header
# ==============================
echo ""
echo -e "${MAGENTA_90}══════════════════════════════════${NC}"
echo -e "${MAGENTA_90}   Proxmox Backup Download        ${NC}"
echo -e "${MAGENTA_90}══════════════════════════════════${NC}"
echo ""

# ==============================
# Verbinding testen
# ==============================
info "Verbinding maken met Proxmox ($PVE_HOST)..."
if ! ssh $SSH_OPTS "${PVE_USER}@${PVE_HOST}" "echo OK" > /dev/null 2>&1; then
    fail "Geen verbinding met $PVE_HOST — is Proxmox online en staat de key goed?"
fi
success "Verbonden met $PVE_HOST"

# ==============================
# Beschikbare backups ophalen
# ==============================
info "Beschikbare backups ophalen..."
REMOTE_FILES=$(ssh $SSH_OPTS "${PVE_USER}@${PVE_HOST}" \
    "ls -1t ${REMOTE_BACKUP_DIR}/docker-vm-backup-*.zip 2>/dev/null || true")
stop_spinner

if [[ -z "$REMOTE_FILES" ]]; then
    warn "Geen backups gevonden op $PVE_HOST:$REMOTE_BACKUP_DIR"
    exit 0
fi

# ==============================
# List modus
# ==============================
if [[ "$MODE" == "list" ]]; then
    step "Beschikbare backups op $PVE_HOST"
    echo ""
    while IFS= read -r file; do
        size=$(ssh $SSH_OPTS "${PVE_USER}@${PVE_HOST}" "du -h '$file' | awk '{print \$1}'")
        local_name=$(basename "$file")
        if [[ -f "$LOCAL_BACKUP_DIR/$local_name" ]]; then
            printf "  ${GREEN_90}✓${NC}  %-45s ${BLUE_90}%s${NC}  (lokaal aanwezig)\n" "$local_name" "$size"
        else
            printf "  ${YELLOW_90}↓${NC}  %-45s ${BLUE_90}%s${NC}\n" "$local_name" "$size"
        fi
    done <<< "$REMOTE_FILES"
    echo ""
    echo -e "  Lokale map: ${BLUE_90}$LOCAL_BACKUP_DIR${NC}"
    echo ""
    exit 0
fi

# ==============================
# Bepaal welke backups te downloaden
# ==============================
TO_DOWNLOAD=()

if [[ "$MODE" == "newest" ]]; then
    NEWEST=$(echo "$REMOTE_FILES" | head -1)
    local_name=$(basename "$NEWEST")
    if [[ -f "$LOCAL_BACKUP_DIR/$local_name" ]]; then
        success "Nieuwste backup al lokaal aanwezig: $local_name"
        echo ""
        echo -e "  ${BLUE_90}Gebruik --all om alle ontbrekende backups te downloaden${NC}"
        echo -e "  ${BLUE_90}Gebruik --list om alle beschikbare backups te zien${NC}"
        echo ""
        exit 0
    fi
    TO_DOWNLOAD=("$NEWEST")
else
    # --all: download alle die lokaal ontbreken
    while IFS= read -r file; do
        local_name=$(basename "$file")
        if [[ ! -f "$LOCAL_BACKUP_DIR/$local_name" ]]; then
            TO_DOWNLOAD+=("$file")
        fi
    done <<< "$REMOTE_FILES"
fi

if [[ ${#TO_DOWNLOAD[@]} -eq 0 ]]; then
    success "Alle backups zijn al lokaal aanwezig"
    exit 0
fi

# ==============================
# Download
# ==============================
step "Downloaden naar $LOCAL_BACKUP_DIR"
echo ""
mkdir -p "$LOCAL_BACKUP_DIR"

DOWNLOADED=0
FAILED=0

for remote_file in "${TO_DOWNLOAD[@]}"; do
    local_name=$(basename "$remote_file")
    size=$(ssh $SSH_OPTS "${PVE_USER}@${PVE_HOST}" "du -h '$remote_file' | awk '{print \$1}'")

    info "Downloaden: $local_name ($size)..."
    if scp $SSH_OPTS "${PVE_USER}@${PVE_HOST}:${remote_file}" \
        "$LOCAL_BACKUP_DIR/$local_name" > /dev/null 2>&1; then
        success "$local_name  ($size)"
        DOWNLOADED=$((DOWNLOADED + 1))
    else
        warn "$local_name — download mislukt"
        FAILED=$((FAILED + 1))
    fi
done

# ==============================
# Samenvatting
# ==============================
echo ""
echo -e "${MAGENTA_90}══════════════════════════════════${NC}"
if [[ $FAILED -eq 0 ]]; then
    echo -e "  ${GREEN_90}✓ $DOWNLOADED backup(s) gedownload${NC}"
else
    echo -e "  ${YELLOW_90}! $DOWNLOADED gedownload, $FAILED mislukt${NC}"
fi
echo -e "${MAGENTA_90}══════════════════════════════════${NC}"
echo ""

# Toon lokale backups
echo -e "  Lokale backups in ${BLUE_90}$LOCAL_BACKUP_DIR${NC}:"
echo ""
if ls "$LOCAL_BACKUP_DIR"/docker-vm-backup-*.zip > /dev/null 2>&1; then
    while IFS= read -r file; do
        size=$(du -h "$file" | awk '{print $1}')
        date_str=$(basename "$file" | grep -oE '[0-9]{8}-[0-9]{6}' | \
            sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)-\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')
        printf "  ${GREEN_90}•${NC}  %-45s ${BLUE_90}%s${NC}  %s\n" \
            "$(basename "$file")" "$size" "$date_str"
    done < <(ls -1t "$LOCAL_BACKUP_DIR"/docker-vm-backup-*.zip)
fi
echo ""
