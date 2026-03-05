#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Proxmox Setup — Restore Docker VM
# ==============================
# Purpose:
#   Restores a timestamped ZIP backup (created by proxmox-backup-docker-files.sh)
#   back to the Docker VM over SSH.
#
# Run (on Proxmox host as root):
#   /opt/proxmox-setup/proxmox-restore-docker-files.sh

# ============================================================================
# KLEUREN (90's palette)
# ============================================================================

MAGENTA_90='\033[38;2;255;0;124m'
GREEN_90='\033[38;2;0;254;162m'
PURPLE_90='\033[38;2;144;76;254m'
YELLOW_90='\033[38;2;249;186;4m'
RED_90='\033[38;2;255;0;54m'
BLUE_90='\033[38;2;0;48;255m'
NC='\033[0m'

# ============================================================================
# SPINNER & STATUS FUNCTIES
# ============================================================================

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

_stop_spinner() {
  if [[ -n "${SPINNER_PID:-}" ]]; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
  fi
  tput cnorm 2>/dev/null || true
}

info() {
  local msg="$1"
  _stop_spinner
  spinner "$msg" &
  SPINNER_PID=$!
  tput civis 2>/dev/null || true
}

success() {
  local msg="$1"
  _stop_spinner
  printf "\r\033[K  ${GREEN_90}✓${NC} %s\n" "$msg"
}

fail() {
  local msg="$1"
  _stop_spinner
  printf "\r\033[K  ${RED_90}✗${NC} %s\n" "$msg"
  exit 1
}

warn() {
  local msg="$1"
  _stop_spinner
  printf "\r\033[K  ${YELLOW_90}!${NC} %s\n" "$msg"
}

msg_skip() {
  local msg="$1"
  _stop_spinner
  printf "\r\033[K  ${BLUE_90}⊘${NC} %s\n" "$msg"
}

# ==============================
# Banner
# ==============================
banner() {
  echo -e "${MAGENTA_90}"
  echo '░░░░░█▀█░█▀▄░█▀█░█░█░█▄█░█▀█░█░█░░░█▀▄░█▀▀░█▀▀░▀█▀░█▀█░█▀▄░█▀▀░░░░'
  echo '░░░░░█▀▀░█▀▄░█░█░▄▀▄░█░█░█░█░▄▀▄░░░█▀▄░█▀▀░▀▀█░░█░░█░█░█▀▄░█▀▀░░░░'
  echo '░░░░░▀░░░▀░▀░▀▀▀░▀░▀░▀░▀░▀▀▀░▀░▀░░░▀▀░░▀▀▀░▀▀▀░░▀░░▀▀▀░▀░▀░▀▀▀░░░░'
  echo '░░░░░░░░░░░░░░░░░░░░█▀▄░█▀█░█▀▀░█░█░█▀▀░█▀▄░░░░░░░░░░░░░░░░░░░░░░░░'
  echo '░░░░░░░░░░░░░░░░░░░░█░█░█░█░█░░░█▀▄░█▀▀░█▀▄░░░░░░░░░░░░░░░░░░░░░░░░'
  echo '░░░░░░░░░░░░░░░░░░░░▀▀░░▀▀▀░▀▀▀░▀░▀░▀▀▀░▀░▀░░░░░░░░░░░░░░░░░░░░░░░░'
  echo -e "${NC}"
}

# ==============================
# Config
# ==============================
DEFAULTS_FILE="/opt/vmconfigs/defaults.conf"
BACKUP_DIR="/root/backups"
VM_USER_FALLBACK="pasta"

# ==============================
# Helpers
# ==============================
need_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_cmd() {
  local cmd="$1" pkg="${2:-$1}"
  if need_cmd "$cmd"; then return 0; fi
  info "$cmd ontbreekt → installeren ($pkg)..."
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y "$pkg" >/dev/null 2>&1 || fail "Installatie mislukt: $pkg"
  need_cmd "$cmd" || fail "$cmd nog steeds niet beschikbaar na installatie"
}

strip_cidr() { echo "${1%%/*}"; }

load_defaults() {
  VM_USER="$VM_USER_FALLBACK"
  DOCKER_VM_IP=""
  if [[ -f "$DEFAULTS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$DEFAULTS_FILE"
  fi
  VM_USER="${VM_USER:-$VM_USER_FALLBACK}"
  DOCKER_VM_IP="${DOCKER_VM_IP:-}"
}

detect_docker_vmid() {
  local vmid status running_match="" stopped_match=""
  while read -r vmid _ status; do
    [[ -z "${vmid:-}" ]] && continue
    if qm config "$vmid" 2>/dev/null | grep -q "ubuntu-docker.yaml"; then
      if [[ "$status" == "running" ]]; then
        running_match="$vmid"; break
      else
        stopped_match="$vmid"
      fi
    fi
  done < <(qm list | awk 'NR>1 {print $1, $2, $3}')
  [[ -n "$running_match" ]] && { echo "$running_match"; return 0; }
  [[ -n "$stopped_match" ]] && { echo "$stopped_match"; return 0; }
  return 1
}

get_vm_ip_from_guest_agent() {
  local vmid="$1"
  local st
  st="$(qm status "$vmid" 2>/dev/null | awk '{print $2}' || true)"
  [[ "$st" == "running" ]] || return 1
  local ip
  ip="$(qm guest cmd "$vmid" network-get-interfaces 2>/dev/null \
    | jq -r '.[] | select(.name != "lo") | .["ip-addresses"][]? | select(.["ip-address-type"]=="ipv4") | .["ip-address"]' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
    | grep -vE '^(127\.|169\.254\.)' \
    | head -n1 || true)"
  [[ -n "${ip:-}" && "$ip" != "null" ]] || return 1
  echo "$ip"
}

detect_docker_ip() {
  if [[ -n "${DOCKER_VM_IP:-}" ]]; then
    strip_cidr "$DOCKER_VM_IP"
    return 0
  fi
  local vmid ip
  vmid="$(detect_docker_vmid || true)"
  if [[ -n "${vmid:-}" ]]; then
    ip="$(get_vm_ip_from_guest_agent "$vmid" || true)"
    if [[ -n "${ip:-}" ]]; then echo "$ip"; return 0; fi
  fi
  return 1
}

ssh_run() {
  ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
    "${VM_USER}@${DOCKER_IP}" "$@"
}

# ==============================
# Backup kiezen
# ==============================
choose_backup() {
  mapfile -t BACKUPS < <(ls -1t "${BACKUP_DIR}"/docker-vm-backup-*.zip 2>/dev/null || true)

  if [[ ${#BACKUPS[@]} -eq 0 ]]; then
    fail "Geen backups gevonden in ${BACKUP_DIR}. Maak eerst een backup met proxmox-backup-docker-files.sh."
  fi

  echo -e "  ${PURPLE_90}━━━ Beschikbare backups ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  local i=1
  for f in "${BACKUPS[@]}"; do
    local size; size=$(du -h "$f" | awk '{print $1}')
    local ts; ts=$(basename "$f" | grep -oE '[0-9]{8}-[0-9]{6}' || echo "onbekend")
    echo -e "    ${GREEN_90}${i}${NC})  $(basename "$f")  ${BLUE_90}(${size})${NC}"
    (( i++ ))
  done

  echo ""
  read -rp "  Kies backup [1-${#BACKUPS[@]}]: " choice

  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#BACKUPS[@]} )); then
    fail "Ongeldige keuze: $choice"
  fi

  CHOSEN_ZIP="${BACKUPS[$((choice-1))]}"
}

# ==============================
# Main
# ==============================
banner

[[ "$EUID" -eq 0 ]] || fail "Run this script as root."
need_cmd qm || fail "qm not found — run on a Proxmox host."

ensure_cmd ssh openssh-client
ensure_cmd scp openssh-client
ensure_cmd jq jq
ensure_cmd unzip unzip

load_defaults

DOCKER_IP="$(detect_docker_ip || true)"
[[ -n "${DOCKER_IP:-}" ]] || fail "Kon Docker VM IP niet detecteren (defaults.conf leeg én guest agent lookup faalde)."

success "Docker VM: ${VM_USER}@${DOCKER_IP}"
echo ""

choose_backup
ZIP_PATH="$CHOSEN_ZIP"
ZIP_NAME="$(basename "$ZIP_PATH")"

echo ""
warn "════════════════════════════════════════════════════════════"
warn "  LET OP: Dit overschrijft de bestanden op de Docker VM!"
warn "  Backup: ${ZIP_NAME}"
warn "  Target: ${VM_USER}@${DOCKER_IP}"
warn "════════════════════════════════════════════════════════════"
echo ""
read -rp "  Weet je zeker dat je wilt doorgaan? (ja/nee): " confirm
case "${confirm,,}" in
  ja|j|yes|y) ;;
  *) msg_skip "Geannuleerd"; exit 0 ;;
esac

echo ""

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; _stop_spinner' EXIT INT TERM

# ZIP uitpakken naar tar.gz
info "ZIP uitpakken..."
unzip -q "$ZIP_PATH" -d "$TMP"
TAR_FILE="$(find "$TMP" -name "*.tar.gz" | head -1)"
[[ -n "$TAR_FILE" ]] || fail "Geen .tar.gz gevonden in ZIP"
success "ZIP uitgepakt"

# SSH key herstellen indien aanwezig in backup
if unzip -l "$ZIP_PATH" 2>/dev/null | grep -q "proxmox_vm_key$"; then
  info "SSH key herstellen..."
  unzip -q -j "$ZIP_PATH" "proxmox_vm_key" "proxmox_vm_key.pub" -d /root/.ssh/ 2>/dev/null || true
  chmod 600 /root/.ssh/proxmox_vm_key
  chmod 644 /root/.ssh/proxmox_vm_key.pub 2>/dev/null || true
  success "SSH key hersteld → /root/.ssh/proxmox_vm_key"
else
  warn "Geen SSH key gevonden in backup — herstel handmatig of genereer een nieuwe"
fi

# Stacks stoppen op VM
info "Stacks stoppen op ${VM_USER}@${DOCKER_IP}..."
ssh_run "
  BASE=/mnt/docker-data/compose
  if [[ -d \"\$BASE\" ]]; then
    for d in \"\$BASE\"/*/; do
      [[ -f \"\$d/docker-compose.yml\" ]] || continue
      name=\$(basename \"\$d\")
      (cd \"\$d\" && docker compose down 2>/dev/null && echo \"  gestopt: \$name\") || true
    done
  fi
" 2>/dev/null || true
success "Stacks gestopt"

# tar.gz uploaden naar VM
REMOTE_TAR="/tmp/${ZIP_NAME%.zip}.tar.gz"
info "Backup uploaden naar VM..."
scp -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
  "$TAR_FILE" "${VM_USER}@${DOCKER_IP}:${REMOTE_TAR}" >/dev/null
success "Backup geüpload"

# Uitpakken op VM (overschrijft bestaande bestanden)
info "Backup terugzetten op VM..."
ssh_run "sudo tar -xzf '${REMOTE_TAR}' -C / \
  --warning=no-file-changed \
  --warning=no-file-removed \
  2>/dev/null; \
  sudo rm -f '${REMOTE_TAR}'"
success "Backup teruggezet"

# Stacks herstarten?
echo ""
read -rp "  Stacks herstarten? (ja/nee): " restart
case "${restart,,}" in
  ja|j|yes|y)
    info "Stacks herstarten op VM..."
    ssh_run "
      BASE=/mnt/docker-data/compose
      for d in \"\$BASE\"/*/; do
        [[ -f \"\$d/docker-compose.yml\" ]] || continue
        name=\$(basename \"\$d\")
        (cd \"\$d\" && docker compose up -d 2>/dev/null && echo \"  gestart: \$name\") || true
      done
    " 2>/dev/null || true
    success "Stacks herstart"
    ;;
  *)
    msg_skip "Stacks niet herstart — start ze handmatig via Dockge"
    ;;
esac

echo ""
success "Restore voltooid!"
echo ""
