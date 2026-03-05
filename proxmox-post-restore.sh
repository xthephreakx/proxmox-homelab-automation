#!/usr/bin/env bash
set -euo pipefail

# ==============================
# proxmox-post-restore.sh
# ==============================
# Voert alle handmatige stappen uit na een restore van de Docker VM.
# Draai dit script NADAT proxmox-restore-docker-files.sh klaar is.
#
# Run (op Proxmox host als root):
#   bash /opt/proxmox-setup/proxmox-post-restore.sh
# ==============================

# ==============================
# Kleuren (zelfde palet als proxmox scripts)
# ==============================
BLUE_90='\033[38;2;0;162;255m'
GREEN_90='\033[38;2;0;254;162m'
MAGENTA_90='\033[38;2;255;0;124m'
PURPLE_90='\033[38;2;144;76;254m'
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
header()  { printf "\n${BLUE_90}══════════════════════════════════════${NC}\n  ${PURPLE_90}%s${NC}\n${BLUE_90}══════════════════════════════════════${NC}\n\n" "$1"; }
note()    { stop_spinner; printf "  ${BLUE_90}→${NC} %s\n" "$1"; tput cnorm 2>/dev/null || true; }

trap 'stop_spinner; tput cnorm 2>/dev/null || true' EXIT INT TERM

# ==============================
# Configuratie
# ==============================
DEFAULTS_FILE="/opt/vmconfigs/defaults.conf"
SSH_KEY="/root/.ssh/proxmox_vm_key"
VM_USER_FALLBACK="pasta"
MEDIA_DIR="/mnt/docker-data/media"
COMPOSE_DIR="/mnt/docker-data/compose"
CRON_JOB='0 7 * * * bash /opt/proxmox-setup/backup-docker-vm-compose.sh >> /var/log/proxmox-backup.log 2>&1 && ls -1t /root/backups/docker-vm-backup-*.zip 2>/dev/null | tail -n +11 | xargs -r rm -f'

# ==============================
# Helpers
# ==============================
load_defaults() {
    VM_USER="$VM_USER_FALLBACK"
    DOCKER_VM_IP=""
    [[ -f "$DEFAULTS_FILE" ]] && source "$DEFAULTS_FILE" || true
    VM_USER="${VM_USER:-$VM_USER_FALLBACK}"
}

detect_docker_vmid() {
    local vmid status running_match="" stopped_match=""
    while read -r vmid _ status; do
        [[ -z "${vmid:-}" ]] && continue
        if qm config "$vmid" 2>/dev/null | grep -q "ubuntu-docker.yaml"; then
            [[ "$status" == "running" ]] && { running_match="$vmid"; break; } || stopped_match="$vmid"
        fi
    done < <(qm list | awk 'NR>1 {print $1, $2, $3}')
    [[ -n "$running_match" ]] && { echo "$running_match"; return 0; }
    [[ -n "$stopped_match" ]] && { echo "$stopped_match"; return 0; }
    return 1
}

get_vm_ip() {
    local vmid="$1"
    qm guest cmd "$vmid" network-get-interfaces 2>/dev/null \
        | jq -r '.[] | select(.name != "lo") | .["ip-addresses"][]? | select(.["ip-address-type"]=="ipv4") | .["ip-address"]' \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | grep -vE '^(127\.|169\.254\.)' | head -1 || true
}

ssh_vm() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=15 \
        "${VM_USER}@${DOCKER_IP}" "$@"
}

# ==============================
# Start
# ==============================
[[ "$EUID" -eq 0 ]] || fail "Run dit script als root."
command -v qm > /dev/null 2>&1 || fail "qm niet gevonden — draai dit op een Proxmox host."

header "Post-Restore Setup"

load_defaults

# Docker VM IP detecteren
if [[ -n "${DOCKER_VM_IP:-}" ]]; then
    DOCKER_IP="${DOCKER_VM_IP%%/*}"
else
    info "Docker VM IP detecteren..."
    VMID=$(detect_docker_vmid || true)
    [[ -n "$VMID" ]] || fail "Docker VM niet gevonden. Is de VM aangemaakt en gestart?"
    DOCKER_IP=$(get_vm_ip "$VMID" || true)
    [[ -n "$DOCKER_IP" ]] || fail "Kon IP niet ophalen van VM $VMID. Is de guest agent actief?"
    stop_spinner
fi

success "Docker VM: ${VM_USER}@${DOCKER_IP}"

# SSH key check
if [[ ! -f "$SSH_KEY" ]]; then
    warn "SSH key niet gevonden: $SSH_KEY"
    warn "Herstel de key of genereer een nieuwe en voeg hem toe aan de VM."
    warn "Zie RESTORE.md voor instructies."
    echo ""
    read -rp "  Doorgaan zonder SSH key? (sommige stappen worden overgeslagen) (j/N): " skip_ssh
    [[ "$skip_ssh" =~ ^[jJyY]$ ]] || exit 1
    SKIP_VM=true
else
    SKIP_VM=false
    info "SSH verbinding testen..."
    ssh_vm "echo ok" > /dev/null 2>&1 || fail "SSH verbinding mislukt naar ${VM_USER}@${DOCKER_IP}"
    stop_spinner
    success "SSH verbinding OK"
fi

# ==============================
# Stap 1: Docker proxy netwerk
# ==============================
step "Docker proxy netwerk aanmaken"

if [[ "$SKIP_VM" == false ]]; then
    NETWORK_EXISTS=$(ssh_vm "sudo docker network ls --filter name=proxy --format '{{.Name}}'" 2>/dev/null || echo "")
    if [[ "$NETWORK_EXISTS" == "proxy" ]]; then
        success "Proxy netwerk bestaat al"
    else
        info "Proxy netwerk aanmaken..."
        ssh_vm "sudo docker network create proxy" > /dev/null 2>&1
        stop_spinner
        success "Proxy netwerk aangemaakt"
    fi
else
    warn "Overgeslagen (geen SSH key)"
fi

# ==============================
# Stap 2: Bestandsrechten media
# ==============================
step "Bestandsrechten herstellen op media"

if [[ "$SKIP_VM" == false ]]; then
    info "chown + chmod op $MEDIA_DIR..."
    ssh_vm "
        if [[ -d '$MEDIA_DIR' ]]; then
            sudo chown -R mediasync:pasta '$MEDIA_DIR' 2>/dev/null || true
            sudo chmod -R u+rwX '$MEDIA_DIR' 2>/dev/null || true
            echo OK
        else
            echo SKIP
        fi
    " > /dev/null 2>&1
    stop_spinner
    success "Rechten hersteld op $MEDIA_DIR"
else
    warn "Overgeslagen (geen SSH key)"
fi

# ==============================
# Stap 3: Compose stacks starten
# ==============================
step "Docker stacks starten"

if [[ "$SKIP_VM" == false ]]; then
    info "Alle compose stacks opstarten..."
    ssh_vm "
        for d in ${COMPOSE_DIR}/*/; do
            [[ -f \"\$d/docker-compose.yml\" ]] || continue
            name=\$(basename \"\$d\")
            (cd \"\$d\" && sudo docker compose up -d 2>/dev/null) || true
        done
        echo OK
    " > /dev/null 2>&1
    stop_spinner
    success "Stacks gestart"
else
    warn "Overgeslagen (geen SSH key) — start stacks handmatig via Dockge"
fi

# ==============================
# Stap 4: Proxmox .bashrc
# ==============================
step "Proxmox auto-launcher instellen (.bashrc)"

BASHRC_BLOCK='
# ==============================
# Auto-start proxmox launcher
# ==============================
if [[ $- == *i* ]] && [[ -d /opt/proxmox-setup ]]; then
    cd /opt/proxmox-setup || true
    bash proxmox-launcher.sh
fi'

if grep -q "Auto-start proxmox launcher" /root/.bashrc 2>/dev/null; then
    success "Auto-launcher staat al in .bashrc"
else
    echo "$BASHRC_BLOCK" >> /root/.bashrc
    success "Auto-launcher toegevoegd aan .bashrc"
fi

# ==============================
# Stap 5: Crontab backup job
# ==============================
step "Dagelijkse backup cron instellen (07:00)"

if crontab -l 2>/dev/null | grep -q "backup-docker-vm-compose"; then
    success "Backup cron staat al ingesteld"
else
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    success "Backup cron ingesteld (dagelijks 07:00, max 10 backups)"
fi

# ==============================
# Stap 6: Checklist resterende taken
# ==============================
printf "\n${YELLOW_90}══════════════════════════════════════${NC}\n"
printf "  ${YELLOW_90}! Handmatige stappen die nog nodig zijn:${NC}\n"
printf "${YELLOW_90}══════════════════════════════════════${NC}\n\n"

note "NAS rsync scripts kopiëren naar /volume1/scripts/ op de NAS"
note "NAS SSH key instellen → draai: bash /opt/proxmox-setup/../usefull-scripts/rsync/nas-keygen.sh"
note "Controleer of Cloudflare DNS records nog kloppen"
note "Test Traefik via https://traefik.local.spallitta.nl"
note "Test een service via https://dockge.local.spallitta.nl"

printf "\n${GREEN_90}══════════════════════════════════════${NC}\n"
printf "  ${GREEN_90}✓ Post-restore voltooid!${NC}\n"
printf "  ${BLUE_90}Zie RESTORE.md voor de volledige handleiding.${NC}\n"
printf "${GREEN_90}══════════════════════════════════════${NC}\n\n"
