#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Proxmox Setup — Backup Docker VM
# ==============================
# Purpose:
#   Creates a timestamped ZIP backup of important Docker VM files
#   (compose stacks, env files, traefik config, wireguard config, docker daemon.json)
#   and stores it on the Proxmox host in /root/backups for easy scp download.
#
# Run (on Proxmox host as root):
#   /opt/proxmox-setup/proxmox-backup-docker-files.sh
#
# Download:
#   scp root@<proxmox-ip>:/root/backups/<file>.zip .

# ============================================================================
# KLEUREN (90's palette)
# ============================================================================

MAGENTA_90='\033[38;2;255;0;124m'   # ff007c
GREEN_90='\033[38;2;0;254;162m'     # 00fea2
PURPLE_90='\033[38;2;144;76;254m'   # 904cfe
YELLOW_90='\033[38;2;249;186;4m'    # f9ba04
RED_90='\033[38;2;255;0;54m'        # ff0036
BLUE_90='\033[38;2;0;48;255m'       # 0030ff
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

msg_skip() {
  local msg="$1"
  _stop_spinner
  printf "\r\033[K  ${BLUE_90}⊘${NC} %s\n" "$msg"
}

warn() {
  local msg="$1"
  _stop_spinner
  printf "\r\033[K  ${YELLOW_90}!${NC} %s\n" "$msg"
}

# ==============================
# Banner
# ==============================
banner() {
  echo -e "${MAGENTA_90}"
  echo '░░░░░█▀█░█▀▄░█▀█░█░█░█▄█░█▀█░█░█░░░█▀▄░█▀█░█▀▀░█░█░█░█░█▀█░░░░░░'
  echo '░░░░░█▀▀░█▀▄░█░█░▄▀▄░█░█░█░█░▄▀▄░░░█▀▄░█▀█░█░░░█▀▄░█░█░█▀▀░░░░░░'
  echo '░░░░░▀░░░▀░▀░▀▀▀░▀░▀░▀░▀░▀▀▀░▀░▀░░░▀▀░░▀░▀░▀▀▀░▀░▀░▀▀▀░▀░░░░░░░░'
  echo '░░░░░░░░░█▀▄░█▀█░█▀▀░█░█░█▀▀░█▀▄░░░█▀▀░▀█▀░█░░░█▀▀░█▀▀░░░░░░░░░░'
  echo '░░░░░░░░░█░█░█░█░█░░░█▀▄░█▀▀░█▀▄░░░█▀▀░░█░░█░░░█▀▀░▀▀█░░░░░░░░░░'
  echo '░░░░░░░░░▀▀░░▀▀▀░▀▀▀░▀░▀░▀▀▀░▀░▀░░░▀░░░▀▀▀░▀▀▀░▀▀▀░▀▀▀░░░░░░░░░░'
  echo -e "${NC}"
}

# ==============================
# Config
# ==============================
DEFAULTS_FILE="/opt/vmconfigs/defaults.conf"

BACKUP_DIR="/root/backups"
DATE_STR="$(date +%Y%m%d-%H%M%S)"
OUT_NAME="docker-vm-backup-${DATE_STR}"
ZIP_PATH="${BACKUP_DIR}/${OUT_NAME}.zip"

VM_USER_FALLBACK="pasta"

# What to back up from Docker VM
REMOTE_PATHS=(
  "/mnt/docker-data/compose"
  "/etc/docker/daemon.json"
)

# ==============================
# Checks / deps
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

detect_proxmox_ip() {
  local ip
  ip="$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}' || true)"
  if [[ -n "${ip:-}" ]]; then
    echo "$ip"
    return 0
  fi
  ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  [[ -n "${ip:-}" ]] || return 1
  echo "$ip"
}

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
  local vmid status
  local running_match=""
  local stopped_match=""

  while read -r vmid _ status; do
    [[ -z "${vmid:-}" ]] && continue
    if qm config "$vmid" 2>/dev/null | grep -q "ubuntu-docker.yaml"; then
      if [[ "$status" == "running" ]]; then
        running_match="$vmid"
        break
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
    if [[ -n "${ip:-}" ]]; then
      echo "$ip"
      return 0
    fi
  fi

  return 1
}

remote_tar() {
  local user="$1" ip="$2" remote_file="$3"
  shift 3

  local rel_paths=()
  local p
  for p in "$@"; do
    rel_paths+=("${p#/}")
  done

  ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
    "${user}@${ip}" "sudo tar -C / -czf '${remote_file}' \
      --warning=no-file-changed \
      --warning=no-file-removed \
      --warning=no-xdev \
      --exclude='**/ipc-socket' \
      --exclude='**/*.sock' \
      ${rel_paths[*]} >/dev/null 2>&1"
}

remote_rm() {
  local user="$1" ip="$2" remote_file="$3"
  ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
    "${user}@${ip}" "sudo rm -f '${remote_file}'" >/dev/null 2>&1 || true
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
ensure_cmd zip zip

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

load_defaults

DOCKER_IP="$(detect_docker_ip || true)"
[[ -n "${DOCKER_IP:-}" ]] || fail "Kon Docker VM IP niet detecteren (defaults.conf leeg én guest agent lookup faalde)."

PROXMOX_IP="$(detect_proxmox_ip || true)"
[[ -n "${PROXMOX_IP:-}" ]] || PROXMOX_IP="<proxmox-ip>"

success "Docker VM: ${VM_USER}@${DOCKER_IP}"
success "Backup output: ${ZIP_PATH}"
warn "Let op: deze backup bevat waarschijnlijk secrets (.env / tokens / VPN configs). Bewaar veilig!"

TMP="$(mktemp -d)"
REMOTE_TAR="/tmp/${OUT_NAME}.tar.gz"
LOCAL_TAR="${TMP}/${OUT_NAME}.tar.gz"

# Combine cleanup + spinner restore in one trap (prevents overwriting)
trap 'rm -rf "$TMP"; _stop_spinner' EXIT INT TERM

info "Tar maken op Docker VM..."
remote_tar "$VM_USER" "$DOCKER_IP" "$REMOTE_TAR" "${REMOTE_PATHS[@]}"
success "Tar gemaakt op Docker VM"

info "Tar downloaden naar Proxmox..."
scp -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
  "${VM_USER}@${DOCKER_IP}:${REMOTE_TAR}" "$LOCAL_TAR" >/dev/null
success "Tar gedownload"

remote_rm "$VM_USER" "$DOCKER_IP" "$REMOTE_TAR"

info "ZIP maken..."
zip -q -j "$ZIP_PATH" "$LOCAL_TAR"
success "ZIP klaar"

# ==============================
# Backup rotatie (max 3 bewaren, met bevestiging)
# ==============================
info "Backup rotatie controleren (max 3 bewaren)..."

mapfile -t ALL_BACKUPS < <(ls -1t "${BACKUP_DIR}"/docker-vm-backup-*.zip 2>/dev/null || true)
mapfile -t OLD_BACKUPS < <(printf '%s\n' "${ALL_BACKUPS[@]}" | tail -n +4)

if [[ ${#OLD_BACKUPS[@]} -gt 0 ]]; then
  warn "De volgende backups worden verwijderd:"
  echo ""
  for file in "${OLD_BACKUPS[@]}"; do
    size=$(du -h "$file" | awk '{print $1}')
    echo -e "  ${RED_90}✗${NC} $(basename "$file") ${BLUE_90}(${size})${NC}"
  done

  echo ""
  echo -e "  ${PURPLE_90}Tip: eerst downloaden:${NC}"
  for file in "${OLD_BACKUPS[@]}"; do
    echo -e "  ${GREEN_90}scp root@${PROXMOX_IP}:${file} .${NC}"
  done

  echo ""
  read -rp "  Verwijderen? (y/N) — kies N om eerst te downloaden: " confirm

  if [[ "${confirm,,}" == "y" ]]; then
    rm -f "${OLD_BACKUPS[@]}"
    success "Oude backups verwijderd"
  else
    msg_skip "Rotatie overgeslagen — je kunt backups eerst downloaden"
  fi
else
  msg_skip "Geen oude backups om te verwijderen (<= 3 aanwezig)"
fi

echo ""
echo -e "  ${PURPLE_90}Beschikbare backups:${NC}"
if ls "${BACKUP_DIR}"/docker-vm-backup-*.zip >/dev/null 2>&1; then
  while IFS= read -r file; do
    size=$(du -h "$file" | awk '{print $1}')
    echo -e "  ${GREEN_90}•${NC} $(basename "$file") ${BLUE_90}(${size})${NC}"
  done < <(ls -1t "${BACKUP_DIR}"/docker-vm-backup-*.zip)
else
  echo -e "  ${YELLOW_90}Geen backups gevonden${NC}"
fi
echo ""

echo -e "  ${PURPLE_90}Downloaden vanaf je laptop/mac:${NC}"
echo -e "  ${GREEN_90}scp root@${PROXMOX_IP}:${ZIP_PATH} .${NC}"
echo ""
echo -e "  ${PURPLE_90}Uitpakken:${NC}"
echo -e "  ${GREEN_90}unzip $(basename "$ZIP_PATH")${NC}"
echo ""