#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Installation instructions
# ==============================
# ssh root@<proxmox-ip>
# nano /root/setup-proxmox-newvm.sh
# paste content into script → Ctrl+O → Enter (save) → Ctrl+X (exit)
# chmod +x /root/setup-proxmox-newvm.sh
# /root/setup-proxmox-newvm.sh
#
# Post-run checks:
# cloud-init status
# sudo tail -100 /var/log/cloud-init-output.log


# ==============================
# Colors (90's palette)
# ==============================

BLUE_90='\033[38;2;0;162;255m'      # 00A2FF
GREEN_90='\033[38;2;0;254;162m'     # 00FEA2
MAGENTA_90='\033[38;2;255;0;124m'   # FF007C
PURPLE_90='\033[38;2;144;76;254m'   # 904CFE
RED_90='\033[38;2;255;0;54m'        # FF0036
YELLOW_90='\033[38;2;255;211;0m'    # FFD300

NC='\033[0m'

# ==============================
# Spinner & status functions
# ==============================
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
    fi
}

info() {
    local msg="$1"
    stop_spinner
    spinner "$msg" &
    SPINNER_PID=$!
    tput civis 2>/dev/null || true
}

success() {
    local msg="$1"
    stop_spinner
    printf "\r\033[K  ${GREEN_90}✓${NC} %s\n" "$msg"
    tput cnorm 2>/dev/null || true
}

fail() {
    local msg="$1"
    stop_spinner
    printf "\r\033[K  ${RED_90}✗${NC} %s\n" "$msg"
    tput cnorm 2>/dev/null || true
    exit 1
}

warn() {
    local msg="$1"
    stop_spinner
    printf "\r\033[K  ${YELLOW_90}!${NC} %s\n" "$msg"
    tput cnorm 2>/dev/null || true
}

skip() {
 local msg="$1"
 stop_spinner
 printf "\r\033[K ${PURPLE_90}↷${NC} %s\n" "$msg"
 tput cnorm 2>/dev/null || true
}

downloading() {
 local msg="$1"
 stop_spinner
 printf "\r\033[K ${BLUE_90}⟳${NC} %s\n" "$msg"
 tput cnorm 2>/dev/null || true
}

progress_bar() {
 local percent=$1
 local desc="${2:-}"
 local width=30
 local filled=$((percent * width / 100))
 local empty=$((width - filled))
 local bar=""

 for ((j=0; j<filled; j++)); do bar+="█"; done
 for ((j=0; j<empty; j++)); do bar+="░"; done

 printf "\r ${GREEN_90}[${bar}]${NC} %3d%% - %-40s" "$percent" "$desc"

 if [[ $percent -eq 100 ]]; then
 echo ""
 fi
}

trap 'stop_spinner; tput cnorm 2>/dev/null' EXIT INT TERM
# ==============================
# Helper: install package if command is missing
# ==============================
ensure_package() {
    local cmd="$1"
    local pkg="$2"
    info "Controleren $cmd..."
    if ! command -v "$cmd" >/dev/null 2>&1; then
        if apt update >/dev/null 2>&1 && apt install -y "$pkg" >/dev/null 2>&1; then
            success "$cmd geïnstalleerd"
        else
            fail "$cmd installatie mislukt"
        fi
    else
        skip "$cmd is al aanwezig"
    fi
}

# Install jq — try apt first, fall back to downloading binary from GitHub
install_jq() {
    info "Checking jq..."
    if command -v jq >/dev/null 2>&1; then
        skip "jq is already installed"
        return
    fi
    # Try apt first
    if apt-get install -y jq >/dev/null 2>&1; then
        success "jq installed via apt"
        return
    fi
    # Fallback: download static binary from GitHub releases
    warn "apt install failed, downloading jq binary from GitHub..."
    local jq_url="https://github.com/jqlang/jq/releases/latest/download/jq-linux-amd64"
    if wget -qO /usr/local/bin/jq "$jq_url" && chmod +x /usr/local/bin/jq; then
        success "jq installed via wget"
    else
        fail "jq installation failed — install manually: apt install -y jq"
    fi
}

# ==============================
# Variables
# ==============================
TEMPLATE_ID=9000
TEMPLATE_NAME="ubuntu-noble-template"
IMAGE_NAME="noble-server-cloudimg-amd64.img"
IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/${IMAGE_NAME}"
STORAGE="local-lvm"

CONFIG_DIR="/opt/vmconfigs"
TEMPLATE_DIR="/opt/templates"
NEW_SCRIPT="/usr/local/bin/new"
IMAGE_DIR="/root"
IMAGE_PATH="$IMAGE_DIR/$IMAGE_NAME"
JSON_NAMES="$CONFIG_DIR/names.json"
LIB_FILE="$CONFIG_DIR/lib.sh"

# ==============================
# Banner
# ==============================
echo -e "${MAGENTA_90}░░░█▀▀░█▀█░█▀█░█▀▀░▀█▀░█▀▀░█░█░█▀▄░█▀▀░░░${NC}"
echo -e "${MAGENTA_90}░░░█░░░█░█░█░█░█▀▀░░█░░█░█░█░█░█▀▄░█▀▀░░░${NC}"
echo -e "${MAGENTA_90}░░░▀▀▀░▀▀▀░▀░▀░▀░░░▀▀▀░▀▀▀░▀▀▀░▀░▀░▀▀▀░░░${NC}"
echo -e "${MAGENTA_90}░░░░░░░█▀█░█▀▄░█▀█░█░█░█▄█░█▀█░█░█░░░░░░░${NC}"
echo -e "${MAGENTA_90}░░░░░░░█▀▀░█▀▄░█░█░▄▀▄░█░█░█░█░▄▀▄░░░░░░░${NC}"
echo -e "${MAGENTA_90}░░░░░░░▀░░░▀░▀░▀▀▀░▀░▀░▀░▀░▀▀▀░▀░▀░░░░░░░${NC}"
echo ""

# ==============================
# Default user configuration
# ==============================
DEFAULTS_FILE="$CONFIG_DIR/defaults.conf"

NEEDS_SAVE=false

if [[ -f "$DEFAULTS_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$DEFAULTS_FILE"
fi

# VM_USER — always present after first run, but check just in case
VM_USER="${VM_USER:-}"
if [[ -z "$VM_USER" ]]; then
    echo -e "\n  ${MAGENTA_90}Welke username moet er in de VMs aangemaakt worden?${NC}"
    echo -e "  ${YELLOW_90}(standaard: pasta — druk Enter om te bevestigen)${NC}\n"
    read -rp "  Username: " INPUT_USER
    VM_USER="${INPUT_USER:-pasta}"
    NEEDS_SAVE=true
fi
skip "VM gebruiker: ${VM_USER}"

# DOCKER_VM_IP — new field, may be missing in existing defaults.conf
DOCKER_VM_IP="${DOCKER_VM_IP:-}"
DOCKER_VM_GW="${DOCKER_VM_GW:-}"
if ! grep -q "DOCKER_VM_IP" "$DEFAULTS_FILE" 2>/dev/null; then
    echo -e "\n  ${MAGENTA_90}Wil je een vast IP instellen voor de Docker VM?${NC}"
    echo -e "  ${YELLOW_90}(druk Enter om DHCP te gebruiken)${NC}\n"
    read -rp "  Docker VM IP (bijv. 192.168.1.50): " INPUT_IP
    if [[ -n "$INPUT_IP" ]]; then
        read -rp "  Subnet mask (bijv. 24): " INPUT_MASK
        read -rp "  Gateway (bijv. 192.168.1.1): " INPUT_GW
        DOCKER_VM_IP="${INPUT_IP}/${INPUT_MASK:-24}"
        DOCKER_VM_GW="${INPUT_GW}"
    else
        DOCKER_VM_IP=""
        DOCKER_VM_GW=""
    fi
    NEEDS_SAVE=true
fi

if [[ -n "$DOCKER_VM_IP" ]]; then
    skip "Docker VM IP: ${DOCKER_VM_IP} (gw: ${DOCKER_VM_GW})"
else
    skip "Docker VM IP: DHCP"
fi

# WG_VARIANT — WireGuard variant voor de arrstack
WG_VARIANT="${WG_VARIANT:-}"
if ! grep -q "WG_VARIANT" "$DEFAULTS_FILE" 2>/dev/null; then
    echo -e "\n  ${MAGENTA_90}Welke WireGuard variant wil je gebruiken voor de arrstack?${NC}"
    echo -e "  ${YELLOW_90}[1] PIA  (thrnz/docker-wireguard-pia) — automatisch via Private Internet Access${NC}"
    echo -e "  ${YELLOW_90}[2] Default  (linuxserver/wireguard) — gebruik eigen nl-ams-wg-001.conf bestand${NC}"
    echo -e "  ${YELLOW_90}(standaard: 1 — druk Enter om te bevestigen)${NC}\n"
    read -rp "  Keuze [1-2]: " INPUT_WG
    WG_VARIANT="${INPUT_WG:-1}"
    NEEDS_SAVE=true
fi
skip "WireGuard variant: $([ "$WG_VARIANT" == "2" ] && echo "Default (linuxserver/wireguard)" || echo "PIA (thrnz/docker-wireguard-pia)")"

# Save if anything new was entered
if [[ "$NEEDS_SAVE" == true ]]; then
    mkdir -p "$CONFIG_DIR"
    # Bewaar bestaande waarden (bijv. DISK_DEVICE van storage setup)
    {
        echo "VM_USER=\"${VM_USER}\""
        echo "DOCKER_VM_IP=\"${DOCKER_VM_IP}\""
        echo "DOCKER_VM_GW=\"${DOCKER_VM_GW}\""
        echo "WG_VARIANT=\"${WG_VARIANT}\""
        [[ -n "${DISK_DEVICE:-}" ]] && echo "DISK_DEVICE=\"${DISK_DEVICE}\""
    } > "$DEFAULTS_FILE"
    success "Configuratie opgeslagen in $DEFAULTS_FILE"
fi

# ==============================
# Snippet storage detection
# ==============================
info "Searching for snippet storage..."

# Always use the 'local' storage for snippets.
# Proxmox cicustom requires a subdirectory in the reference: "storage:subdir/file.yaml"
# local storage has path /var/lib/vz, so snippets live at /var/lib/vz/snippets/
# and cicustom "local:snippets/ubuntu-docker.yaml" resolves correctly.
SNIPPET_STORAGE="local"
SNIPPET_DIR="/var/lib/vz/snippets"

# Ensure 'local' storage has snippets in its content types
if ! pvesm status -content snippets 2>/dev/null | grep -q "^local"; then
    pvesm set local --content "backup,import,vztmpl,iso,snippets" >/dev/null 2>&1
    success "Snippet support added to 'local' storage"
else
    success "Snippet storage ready: local (${SNIPPET_DIR})"
fi

# ==============================
# Dependencies
# ==============================
install_jq

# ==============================
# Directories
# ==============================
info "Creating directories..."
mkdir -p "$CONFIG_DIR" "$TEMPLATE_DIR" "$SNIPPET_DIR" || fail "Failed to create directories"
success "Directories ready"

# ==============================
# Generate shared library (lib.sh)
# ==============================
info "Creating shared library..."
cat > "$LIB_FILE" << 'ENDLIB'
#!/usr/bin/env bash
# ==============================
# Proxmox VM Shared Library
# Generated by proxmox-setup-vms.sh
# ==============================

# ==============================
# Colors (90's palette)
# ==============================

BLUE_90='\033[38;2;0;162;255m'      # 00A2FF
GREEN_90='\033[38;2;0;254;162m'     # 00FEA2
MAGENTA_90='\033[38;2;255;0;124m'   # FF007C
PURPLE_90='\033[38;2;144;76;254m'   # 904CFE
RED_90='\033[38;2;255;0;54m'        # FF0036
YELLOW_90='\033[38;2;255;211;0m'    # FFD300

NC='\033[0m'

# Spinner & status functions
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
    fi
}

info() {
    local msg="$1"
    stop_spinner
    spinner "$msg" &
    SPINNER_PID=$!
    tput civis 2>/dev/null || true
}

success() {
    local msg="$1"
    stop_spinner
    printf "\r\033[K  ${GREEN_90}✓${NC} %s\n" "$msg"
    tput cnorm 2>/dev/null || true
}

fail() {
    local msg="$1"
    stop_spinner
    printf "\r\033[K  ${RED_90}✗${NC} %s\n" "$msg"
    tput cnorm 2>/dev/null || true
    exit 1
}

warn() {
    local msg="$1"
    stop_spinner
    printf "\r\033[K  ${YELLOW_90}!${NC} %s\n" "$msg"
    tput cnorm 2>/dev/null || true
}

skip() {
 local msg="$1"
 stop_spinner
 printf "\r\033[K ${PURPLE_90}↷${NC} %s\n" "$msg"
 tput cnorm 2>/dev/null || true
}

downloading() {
 local msg="$1"
 stop_spinner
 printf "\r\033[K ${BLUE_90}⟳${NC} %s\n" "$msg"
 tput cnorm 2>/dev/null || true
}

# Progress bar: progress_bar <percentage> <description>
progress_bar() {
    local percent=$1
    local desc="${2:-}"
    local width=30
    local filled=$((percent * width / 100))
    local empty=$((width - filled))
    local bar=""

    for ((j=0; j<filled; j++)); do bar+="█"; done
    for ((j=0; j<empty; j++)); do bar+="░"; done

    printf "\r  ${GREEN_90}[${bar}]${NC} %3d%% - %-40s" "$percent" "$desc"

    if [[ $percent -eq 100 ]]; then
        echo ""
    fi
}

# Graceful stop for docker VM: first stop docker inside the guest (if agent responds),
# then qm shutdown with timeout, and only as last resort qm stop.
graceful_stop_docker_vm() {
    local vmid="$1"
    local name="${2:-$vmid}"
    local timeout="${3:-180}"

    info "Docker netjes stoppen in VM $vmid ($name) via guest agent..."

    if qm guest cmd "$vmid" ping >/dev/null 2>&1; then
        qm guest exec "$vmid" -- bash -lc '
            if command -v docker >/dev/null 2>&1; then
                docker ps -q 2>/dev/null | xargs -r docker stop 2>/dev/null || true
            fi
            if command -v systemctl >/dev/null 2>&1; then
                systemctl stop docker docker.socket 2>/dev/null || true
            fi
            sync || true
        ' >/dev/null 2>&1 || true
        success "Docker containers + service gestopt (agent OK)"
    else
        warn "Guest agent niet bereikbaar, ga door met shutdown..."
    fi

    info "Graceful shutdown VM $vmid ($name) (timeout ${timeout}s)..."
    qm shutdown "$vmid" --timeout "$timeout" >/dev/null 2>&1 || true

    local waited=0
    while [[ "$(qm status "$vmid" 2>/dev/null | awk '{print $2}')" != "stopped" ]]; do
        sleep 2
        waited=$((waited + 2))
        if (( waited >= timeout )); then
            break
        fi
    done

    if [[ "$(qm status "$vmid" 2>/dev/null | awk '{print $2}')" == "stopped" ]]; then
        success "VM $vmid netjes gestopt"
        return 0
    fi

    warn "VM $vmid stopt niet netjes → force stop..."
    qm stop "$vmid" >/dev/null 2>&1 || true

    waited=0
    while [[ "$(qm status "$vmid" 2>/dev/null | awk '{print $2}')" != "stopped" ]]; do
        sleep 2
        waited=$((waited + 2))
        if (( waited > 60 )); then
            warn "Kon VM $vmid niet stoppen na force stop"
            return 1
        fi
    done

    success "VM $vmid geforceerd gestopt"
}

# Docker VM detection
is_docker_vm() {
    local vmid="$1"
    local config
    config=$(qm config "$vmid" 2>/dev/null || echo "")
    echo "$config" | grep -q "ubuntu-docker.yaml"
}

# Safe stop: automatically picks the right method
safe_stop_vm() {
    local vmid="$1"
    local name="${2:-$vmid}"
    local status
    status=$(qm status "$vmid" 2>/dev/null | awk '{print $2}')

    if [[ "$status" != "running" ]]; then
        success "VM $vmid staat al stil"
        return 0
    fi

    if is_docker_vm "$vmid"; then
        warn "Docker VM gedetecteerd → graceful stop (SSD bescherming)"
        graceful_stop_docker_vm "$vmid" "$name" 180
    else
        info "Stoppen VM $vmid ($name)..."
        qm stop "$vmid" >/dev/null 2>&1 || true
        sleep 2
        success "VM $vmid gestopt"
    fi
}

trap 'stop_spinner; tput cnorm 2>/dev/null' EXIT INT TERM
ENDLIB

chmod +x "$LIB_FILE"
success "Shared library aangemaakt: $LIB_FILE"

# ==============================
# Config files
# ==============================
info "Creating config files..."
cat > "$CONFIG_DIR/ubuntu.conf" << 'EOF'
CORES=2
MEMORY=4096
DISK1=10G
BRIDGE=vmbr0
EOF

cat > "$CONFIG_DIR/ubuntu-large.conf" << 'EOF'
CORES=2
MEMORY=32768
DISK1=100G
BRIDGE=vmbr0
EOF

cat > "$CONFIG_DIR/docker.conf" << 'EOF'
CORES=2
MEMORY=20480
DISK1=50G
BRIDGE=vmbr0
EOF

cat > "$CONFIG_DIR/ubuntu-gui.conf" << 'EOF'
CORES=4
MEMORY=12288
DISK1=50G
BRIDGE=vmbr0
EOF

success "Conf bestanden aangemaakt: $CONFIG_DIR"

# ==============================
# JSON names
# ==============================
cat > "$JSON_NAMES" << 'EOF'
{
  "adjectives": ["mov","mpeg","mkv","mp4","wmv","asf","flv","m4v","qt","avi","tc","ksd","asec","hc","aes","sme","p12","fve","axx","p7z","h","gz","so","par2","r00","inc","chk","ko","torrent"],
  "names": ["h3ll0fr13nd","0nes-and-zer0es","d3bug","da3m0ns","3xpl0its","br4ve-trave1er","v1ew-s0urce","wh1ter0se","m1rr0r1ng","zer0-day","unm4sk-pt1","unm4sk-pt2","k3rnel-pan1c","init_1","logic-b0mb","m4ster-s1ave","h4ndshake","succ3ss0r","init_5","h1dden-pr0cess","pyth0n-pt1","pyth0n-pt2","p0w3r-s4v3r-m0d3","und0","l3g4cy","m3t4d4t4","runt1m3-3rr0r","k1ll-pr0c3ss","fr3dr1ck+t4ny4","d0nt-d3l3t3-m3","st4g3","shutd0wn-r","401-Unauthorized","402-Payment-Required","403-Forbidden","404-Not-Found","405-Method-Not-Allowed","406-Not-Acceptable","407-Proxy-Authentication-Required","408-Request-Timeout","409-Conflict","410-Gone","eXit","whoami"]
}
EOF
success "JSON namen klaar"

# ==============================
# Template mapping (all 4 use the same template)
# ==============================
for tpl in ubuntu ubuntu-large docker ubuntu-gui; do
    echo "TEMPLATE_ID=9000" > "$TEMPLATE_DIR/$tpl.template"
done
success "Template bestanden aangemaakt"

# ==============================
# SSH key detection
# ==============================
info "Searching for SSH public key..."
SSH_PUB_KEY=""
for keyfile in /root/.ssh/id_ed25519.pub /root/.ssh/id_rsa.pub /root/.ssh/id_ecdsa.pub; do
    if [[ -f "$keyfile" ]]; then
        SSH_PUB_KEY=$(cat "$keyfile")
        success "SSH key gevonden: $keyfile"
        break
    fi
done

if [[ -z "$SSH_PUB_KEY" ]]; then
    info "SSH key aanmaken..."
    ssh-keygen -t ed25519 -C "root@$(hostname)" -N "" -f /root/.ssh/id_ed25519 >/dev/null 2>&1
    SSH_PUB_KEY=$(cat /root/.ssh/id_ed25519.pub)
    success "SSH key aangemaakt"
fi

# ==============================
# Cloud-init snippets
# ==============================
info "Creating cloud-init snippets..."

# Helper: generate the shared cloud-init header
generate_cloudinit_header() {
    cat << HEADER
#cloud-config
manage_etc_hosts: true
timezone: Europe/Amsterdam
locale: en_US.UTF-8
package_update: true
package_upgrade: true

users:
  - name: ${VM_USER}
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    groups: sudo
    lock_passwd: false
    ssh_authorized_keys:
      - $SSH_PUB_KEY

ssh_pwauth: true
HEADER
}

# --- ubuntu-day1.yaml ---
generate_cloudinit_header > "$SNIPPET_DIR/ubuntu-day1.yaml"
cat >> "$SNIPPET_DIR/ubuntu-day1.yaml" << 'EOF'

packages:
  - qemu-guest-agent
  - curl
  - ca-certificates
  - vim
  - htop

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
EOF

# --- ubuntu-docker.yaml (part 1: header + extra packages) ---
generate_cloudinit_header > "$SNIPPET_DIR/ubuntu-docker.yaml"
cat >> "$SNIPPET_DIR/ubuntu-docker.yaml" << 'EOF'

packages:
  - qemu-guest-agent
  - curl
  - ca-certificates
  - vim
  - htop
  - apt-transport-https
  - gnupg
  - lsb-release
EOF

# --- ubuntu-docker.yaml (part 2: write_files + runcmd, literal) ---
cat >> "$SNIPPET_DIR/ubuntu-docker.yaml" << 'ENDSNIPPET'

write_files:
  - path: /root/setup-persistent-docker.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -e

      echo "=== Setup Persistent Docker Storage ==="

      # --- Step 1: Wait for /dev/sdb ---
      echo "Waiting for /dev/sdb..."
      for i in $(seq 1 30); do
        if [ -b /dev/sdb ]; then
          echo "Disk /dev/sdb gevonden"
          break
        fi
        echo "Poging $i/30..."
        sleep 2
      done

      if [ ! -b /dev/sdb ]; then
        echo "FOUT: /dev/sdb niet gevonden na 60 seconden!"
        exit 1
      fi

      # --- Step 2: Check filesystem (NEVER format existing data) ---
      if blkid /dev/sdb | grep -q "TYPE="; then
        echo "Bestaand filesystem gevonden, hergebruiken..."
      elif blkid /dev/sdb1 | grep -q "TYPE="; then
        echo "Bestaand filesystem gevonden op /dev/sdb1, hergebruiken..."
      else
        echo "WAARSCHUWING: Geen filesystem gevonden op /dev/sdb!"
        echo "Formatteren met ext4..."
        mkfs.ext4 -L docker-data /dev/sdb
      fi

      # --- Step 3: Determine correct device (partition or whole disk) ---
      if [ -b /dev/sdb1 ]; then
        MOUNT_DEV="/dev/sdb1"
      else
        MOUNT_DEV="/dev/sdb"
      fi
      echo "Mount device: $MOUNT_DEV"

      # --- Step 4: Mount ---
      mkdir -p /mnt/docker-data
      if mount | grep -q "/mnt/docker-data"; then
        echo "/mnt/docker-data is al gemount"
      else
        mount "$MOUNT_DEV" /mnt/docker-data
        echo "Gemount: $MOUNT_DEV -> /mnt/docker-data"
      fi

      # --- Step 5: Fstab (with nofail) ---
      if ! grep -q "/mnt/docker-data" /etc/fstab; then
        # Use LABEL if available, otherwise device path
        DISK_LABEL=$(blkid -s LABEL -o value "$MOUNT_DEV" 2>/dev/null || echo "")
        if [ -n "$DISK_LABEL" ]; then
          echo "LABEL=$DISK_LABEL /mnt/docker-data ext4 defaults,nofail 0 2" >> /etc/fstab
        else
          echo "$MOUNT_DEV /mnt/docker-data ext4 defaults,nofail 0 2" >> /etc/fstab
        fi
        echo "Fstab entry toegevoegd"
      fi

      # --- Step 6: Directory structure (only create if not already present) ---
      mkdir -p /mnt/docker-data/docker
      mkdir -p /mnt/docker-data/compose/traefik
      mkdir -p /mnt/docker-data/compose/mylar/config
      mkdir -p /mnt/docker-data/compose/suwayomi
      mkdir -p /mnt/docker-data/compose/dockge/data
      mkdir -p /mnt/docker-data/compose/audiobookshelf/config
      mkdir -p /mnt/docker-data/compose/audiobookshelf/metadata
      mkdir -p /mnt/docker-data/compose/komga/config
      mkdir -p /mnt/docker-data/compose/homepage/config
      mkdir -p /mnt/docker-data/compose/tailscale

      mkdir -p /mnt/docker-data/compose/arrstack/wireguard/pia
      mkdir -p /mnt/docker-data/compose/arrstack/sabnzbd/config
      mkdir -p /mnt/docker-data/compose/arrstack/radarr/config
      mkdir -p /mnt/docker-data/compose/arrstack/sonarr/config
      mkdir -p /mnt/docker-data/compose/arrstack/bazarr/config
      mkdir -p /mnt/docker-data/compose/arrstack/qbittorrent/config
      mkdir -p /mnt/docker-data/media/audiobooks
      mkdir -p /mnt/docker-data/media/ebooks
      mkdir -p /mnt/docker-data/media/comics
      mkdir -p /mnt/docker-data/media/mangas
      mkdir -p /mnt/docker-data/media/movies
      mkdir -p /mnt/docker-data/media/tvshows
      mkdir -p /mnt/docker-data/media/downloads/incomplete
      mkdir -p /mnt/docker-data/media/torrents/incomplete
      mkdir -p /mnt/docker-data/media/nzb
      mkdir -p /mnt/docker-data/media/other
      mkdir -p /mnt/docker-data/media/watch
      mkdir -p /mnt/docker-data/backups
      chown -R 1000:1000 /mnt/docker-data/compose/suwayomi
      chown -R 1000:1000 /mnt/docker-data/media/mangas
      chown -R 1000:1000 /mnt/docker-data/compose/mylar
      chown -R 1000:1000 /mnt/docker-data/media/comics
      chown -R 1000:1000 /mnt/docker-data/media/downloads
      echo "Directory structuur klaar"

      # --- Step 7: Configure Docker daemon ---
      mkdir -p /etc/docker
      cat > /etc/docker/daemon.json <<'ENDJSON'
      {
        "data-root": "/mnt/docker-data/docker",
        "log-driver": "json-file",
        "log-opts": {
          "max-size": "10m",
          "max-file": "3"
        }
      }
      ENDJSON
      echo "Docker daemon geconfigureerd"

      # --- Step 8: Symlinks for Dockge + /opt/docker ---
      # Dockge expects: /opt/stacks/<stack-name>/docker-compose.yml
      # /opt/stacks -> /mnt/docker-data/compose (so homelab/ subdir is visible)
      mkdir -p /mnt/docker-data/compose/homelab

      if [ -L /opt/stacks ] || [ -d /opt/stacks ]; then
        rm -rf /opt/stacks
      fi
      ln -sf /mnt/docker-data/compose /opt/stacks
      echo "Symlink: /opt/stacks -> /mnt/docker-data/compose"

      if [ -L /opt/docker ]; then
        rm /opt/docker
      elif [ -d /opt/docker ]; then
        rm -rf /opt/docker
      fi
      ln -sf /mnt/docker-data/compose /opt/docker
      echo "Symlink: /opt/docker -> /mnt/docker-data/compose"

      # --- Step 8b: .env with project name + secrets ---
      mkdir -p /mnt/docker-data/compose/homelab
      if [ ! -f /mnt/docker-data/compose/homelab/.env ]; then
        echo "COMPOSE_PROJECT_NAME=homelab" > /mnt/docker-data/compose/homelab/.env
        echo "BASE_DOMAIN=local.yourdomain.com" >> /mnt/docker-data/compose/homelab/.env
        echo "LE_EMAIL=me@example.com" >> /mnt/docker-data/compose/homelab/.env
        echo "CF_DNS_API_TOKEN=change-me" >> /mnt/docker-data/compose/homelab/.env
        echo "TRAEFIK_DASHBOARD_AUTH=" >> /mnt/docker-data/compose/homelab/.env
        echo "# Tailscale auth key (vul in voor komga via Tailscale)" >> /mnt/docker-data/compose/homelab/.env
        echo "# Genereer op: https://login.tailscale.com/admin/settings/keys" >> /mnt/docker-data/compose/homelab/.env
        echo "TS_AUTHKEY=tskey-auth-CHANGE-ME" >> /mnt/docker-data/compose/homelab/.env
        chmod 600 /mnt/docker-data/compose/homelab/.env
        echo ".env aangemaakt (pas BASE_DOMAIN, LE_EMAIL, CF_DNS_API_TOKEN, TS_AUTHKEY aan!)"
      else
        grep -q "^BASE_DOMAIN=" /mnt/docker-data/compose/homelab/.env || echo "BASE_DOMAIN=local.yourdomain.com" >> /mnt/docker-data/compose/homelab/.env
        grep -q "^LE_EMAIL=" /mnt/docker-data/compose/homelab/.env || echo "LE_EMAIL=me@example.com" >> /mnt/docker-data/compose/homelab/.env
        grep -q "^CF_DNS_API_TOKEN=" /mnt/docker-data/compose/homelab/.env || echo "CF_DNS_API_TOKEN=change-me" >> /mnt/docker-data/compose/homelab/.env
        grep -q "^TRAEFIK_DASHBOARD_AUTH=" /mnt/docker-data/compose/homelab/.env || echo "TRAEFIK_DASHBOARD_AUTH=" >> /mnt/docker-data/compose/homelab/.env
        echo ".env bijgewerkt met wildcard/TLS vars"
      fi

      # --- Step 9: Default configs (only create if they do not exist) ---
      if [ ! -f /mnt/docker-data/compose/homelab/docker-compose.yml ]; then
        mkdir -p /mnt/docker-data/compose/homelab
        cat > /mnt/docker-data/compose/homelab/docker-compose.yml <<'ENDCOMPOSE'
      services:
        traefik:
          image: traefik:v3.6.2
          container_name: traefik
          restart: unless-stopped
          security_opt:
            - no-new-privileges:true
          networks:
            - proxy
          ports:
            - 80:80
            - 443:443
          environment:
            - TZ=Europe/Amsterdam
            - CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}
            - TRAEFIK_CERTIFICATESRESOLVERS_LE_ACME_EMAIL=${LE_EMAIL}
          volumes:
            - /etc/localtime:/etc/localtime:ro
            - /var/run/docker.sock:/var/run/docker.sock:ro
            - /mnt/docker-data/compose/traefik/traefik.yml:/traefik.yml:ro
            - /mnt/docker-data/compose/traefik/acme.json:/acme.json
            - /mnt/docker-data/compose/traefik/config.yml:/config.yml:ro
          labels:
            - "traefik.enable=true"
            - "traefik.http.routers.traefik.rule=Host(`traefik.${BASE_DOMAIN}`)"
            - "traefik.http.routers.traefik.entrypoints=websecure"
            - "traefik.http.routers.traefik.tls=true"
            - "traefik.http.routers.traefik.tls.certresolver=le"
            - "traefik.http.routers.traefik.tls.domains[0].main=*.${BASE_DOMAIN}"
            - "traefik.http.routers.traefik.tls.domains[0].sans=${BASE_DOMAIN}"
            - "traefik.http.routers.traefik.service=api@internal"

        mylar:
          image: lscr.io/linuxserver/mylar3:latest
          container_name: mylar
          restart: unless-stopped
          security_opt:
            - no-new-privileges:true
          networks:
            - proxy
          ports:
            - 8304:8090
          environment:
            - PUID=1000
            - PGID=1000
            - TZ=Europe/Amsterdam
            - UMASK=002
          volumes:
            - /mnt/docker-data/compose/mylar/config:/config
            - /mnt/docker-data/media/watch:/watch
            - /mnt/docker-data/media/comics:/comics
            - /mnt/docker-data/media/downloads:/downloads
          labels:
            - "traefik.enable=true"
            - "traefik.http.routers.mylar.rule=Host(`mylar.${BASE_DOMAIN}`)"
            - "traefik.http.routers.mylar.entrypoints=websecure"
            - "traefik.http.routers.mylar.tls=true"
            - "traefik.http.routers.mylar.tls.certresolver=le"
            - "traefik.http.routers.mylar.tls.domains[0].main=*.${BASE_DOMAIN}"
            - "traefik.http.services.mylar.loadbalancer.server.port=8090"

        suwayomi:
          image: ghcr.io/suwayomi/tachidesk:stable
          container_name: suwayomi
          restart: unless-stopped
          user: "1000:1000"
          networks:
            - proxy
          ports:
            - 8316:4567
          environment:
            - TZ=Europe/Amsterdam
          volumes:
            - /mnt/docker-data/compose/suwayomi:/home/suwayomi/.local/share/Tachidesk
            - /mnt/docker-data/media/mangas:/home/suwayomi/.local/share/Tachidesk/downloads
          labels:
            - "traefik.enable=true"
            - "traefik.http.routers.suwayomi.rule=Host(`suwayomi.${BASE_DOMAIN}`)"
            - "traefik.http.routers.suwayomi.entrypoints=websecure"
            - "traefik.http.routers.suwayomi.tls=true"
            - "traefik.http.routers.suwayomi.tls.certresolver=le"
            - "traefik.http.routers.suwayomi.tls.domains[0].main=*.${BASE_DOMAIN}"
            - "traefik.http.services.suwayomi.loadbalancer.server.port=4567"

        dockge:
          image: louislam/dockge:1
          container_name: dockge
          restart: unless-stopped
          networks:
            - proxy
          ports:
            - 5001:5001
          volumes:
            - /var/run/docker.sock:/var/run/docker.sock
            - /mnt/docker-data/compose/dockge/data:/app/data
            - /mnt/docker-data/compose:/opt/stacks
          environment:
            - DOCKGE_STACKS_DIR=/opt/stacks
          labels:
            - "traefik.enable=true"
            - "traefik.http.routers.dockge.rule=Host(`dockge.${BASE_DOMAIN}`)"
            - "traefik.http.routers.dockge.entrypoints=websecure"
            - "traefik.http.routers.dockge.tls=true"
            - "traefik.http.routers.dockge.tls.certresolver=le"
            - "traefik.http.routers.dockge.tls.domains[0].main=*.${BASE_DOMAIN}"
            - "traefik.http.services.dockge.loadbalancer.server.port=5001"

        audiobookshelf:
          image: ghcr.io/advplyr/audiobookshelf:latest
          container_name: audiobookshelf
          restart: unless-stopped
          security_opt:
            - no-new-privileges:true
          networks:
            - proxy
          ports:
            - 8309:80
          environment:
            - TZ=Europe/Amsterdam
          volumes:
            - /mnt/docker-data/media/audiobooks:/audiobooks
            - /mnt/docker-data/media/ebooks:/ebooks
            - /mnt/docker-data/compose/audiobookshelf/config:/config
            - /mnt/docker-data/compose/audiobookshelf/metadata:/metadata
          labels:
            - "traefik.enable=true"
            - "traefik.http.routers.audiobookshelf.rule=Host(`audiobookshelf.${BASE_DOMAIN}`)"
            - "traefik.http.routers.audiobookshelf.entrypoints=websecure"
            - "traefik.http.routers.audiobookshelf.tls=true"
            - "traefik.http.routers.audiobookshelf.tls.certresolver=le"
            - "traefik.http.routers.audiobookshelf.tls.domains[0].main=*.${BASE_DOMAIN}"
            - "traefik.http.services.audiobookshelf.loadbalancer.server.port=80"

        tailscale:
          image: tailscale/tailscale:latest
          container_name: tailscale
          hostname: komga-ts
          restart: unless-stopped
          network_mode: host
          cap_add:
            - NET_ADMIN
            - SYS_MODULE
          volumes:
            - /mnt/docker-data/compose/tailscale:/var/lib/tailscale
            - /dev/net/tun:/dev/net/tun
          environment:
            - TS_AUTHKEY=${TS_AUTHKEY}
            - TS_STATE_DIR=/var/lib/tailscale

        komga:
          image: gotson/komga
          container_name: komga
          restart: unless-stopped
          networks:
            - proxy
          ports:
            - 8306:25600
          environment:
            - TZ=Europe/Amsterdam
          volumes:
            - /mnt/docker-data/compose/komga/config:/config
            - /mnt/docker-data/media/comics:/data
          labels:
            - "traefik.enable=true"
            - "traefik.http.routers.komga.rule=Host(`komga.${BASE_DOMAIN}`)"
            - "traefik.http.routers.komga.entrypoints=websecure"
            - "traefik.http.routers.komga.tls=true"
            - "traefik.http.routers.komga.tls.certresolver=le"
            - "traefik.http.routers.komga.tls.domains[0].main=*.${BASE_DOMAIN}"
            - "traefik.http.services.komga.loadbalancer.server.port=25600"

        it-tools:
          image: ghcr.io/sharevb/it-tools:latest
          container_name: it-tools
          restart: unless-stopped
          networks:
            - proxy
          ports:
            - 8399:8080
          security_opt:
            - no-new-privileges:true
          labels:
            - "traefik.enable=true"
            - "traefik.http.routers.it-tools.rule=Host(`it-tools.${BASE_DOMAIN}`)"
            - "traefik.http.routers.it-tools.entrypoints=websecure"
            - "traefik.http.routers.it-tools.tls=true"
            - "traefik.http.routers.it-tools.tls.certresolver=le"
            - "traefik.http.routers.it-tools.tls.domains[0].main=*.${BASE_DOMAIN}"
            - "traefik.http.services.it-tools.loadbalancer.server.port=8080"

      networks:
        proxy:
          name: proxy
          driver: bridge
      ENDCOMPOSE
        echo "docker-compose.yml aangemaakt in homelab/"
      else
        echo "docker-compose.yml bestaat al, overslaan"
      fi

ENDSNIPPET

cat >> "$SNIPPET_DIR/ubuntu-docker.yaml" << 'ENDHOMEPAGE'
      # --- Homepage stack ---
      mkdir -p /mnt/docker-data/compose/homepage/config
      if [ ! -f /mnt/docker-data/compose/homepage/docker-compose.yml ]; then
        cat > /mnt/docker-data/compose/homepage/docker-compose.yml <<'EOCOMPOSE'
      services:
        homepage:
          image: ghcr.io/gethomepage/homepage:latest
          container_name: homepage
          restart: unless-stopped
          networks:
            - proxy
          ports:
            - 8320:3000
          security_opt:
            - no-new-privileges:true
          volumes:
            - /mnt/docker-data/compose/homepage/config:/app/config
          labels:
            - "traefik.enable=true"
            - "traefik.http.routers.homepage.rule=Host(`home.${BASE_DOMAIN}`)"
            - "traefik.http.routers.homepage.entrypoints=websecure"
            - "traefik.http.routers.homepage.tls=true"
            - "traefik.http.routers.homepage.tls.certresolver=le"
            - "traefik.http.routers.homepage.tls.domains[0].main=*.${BASE_DOMAIN}"
            - "traefik.http.services.homepage.loadbalancer.server.port=3000"

      networks:
        proxy:
          external: true
      EOCOMPOSE
        echo "docker-compose.yml aangemaakt in homepage/"
      else
        echo "docker-compose.yml bestaat al in homepage/, overslaan"
      fi
ENDHOMEPAGE

# --- WireGuard variant keuze voor arrstack ---
if [[ "$WG_VARIANT" == "2" ]]; then
cat >> "$SNIPPET_DIR/ubuntu-docker.yaml" << 'ENDARRSTACK_DEFAULT'
      # --- Arrstack: wireguard (default) + arr services + qbittorrent ---
      mkdir -p /mnt/docker-data/compose/arrstack
      mkdir -p /mnt/docker-data/compose/arrstack/wireguard/config/wg_confs
      if [ ! -f /mnt/docker-data/compose/arrstack/docker-compose.yml ]; then
        cat > /mnt/docker-data/compose/arrstack/docker-compose.yml <<'ENDARRSTACK'
      services:
        wireguard:
          image: lscr.io/linuxserver/wireguard:latest
          container_name: wireguard
          cap_add:
            - NET_ADMIN
            - SYS_MODULE
          environment:
            - PUID=1000
            - PGID=1000
            - TZ=Europe/Amsterdam
          volumes:
            - /etc/localtime:/etc/localtime:ro
            - /mnt/docker-data/compose/arrstack/wireguard/config:/config
            - /lib/modules:/lib/modules:ro
          networks:
            - proxy
          ports:
            - 8301:8080  # sabnzbd
            - 8302:7878  # radarr
            - 8303:8989  # sonarr
            - 6767:6767  # bazarr
            - 8311:8311  # qbittorrent webui
            - 43398:43398
            - 43398:43398/udp
          sysctls:
            - net.ipv4.conf.all.src_valid_mark=1
          restart: unless-stopped
          healthcheck:
            test: ["CMD-SHELL", "wg show 2>/dev/null | grep -q 'interface' || exit 1"]
            interval: 30s
            timeout: 10s
            retries: 3
            start_period: 60s
          labels:
            - "traefik.enable=true"
            - "traefik.http.routers.sabnzbd.rule=Host(`sabnzbd.${BASE_DOMAIN}`)"
            - "traefik.http.routers.sabnzbd.entrypoints=websecure"
            - "traefik.http.routers.sabnzbd.tls=true"
            - "traefik.http.routers.sabnzbd.tls.certresolver=le"
            - "traefik.http.services.sabnzbd.loadbalancer.server.port=8080"
            - "traefik.http.routers.sabnzbd.service=sabnzbd"
            - "traefik.http.routers.sabnzbd.tls.domains[0].main=*.${BASE_DOMAIN}"
            - "traefik.http.routers.radarr.rule=Host(`radarr.${BASE_DOMAIN}`)"
            - "traefik.http.routers.radarr.entrypoints=websecure"
            - "traefik.http.routers.radarr.tls=true"
            - "traefik.http.routers.radarr.tls.certresolver=le"
            - "traefik.http.services.radarr.loadbalancer.server.port=7878"
            - "traefik.http.routers.radarr.service=radarr"
            - "traefik.http.routers.radarr.tls.domains[0].main=*.${BASE_DOMAIN}"
            - "traefik.http.routers.sonarr.rule=Host(`sonarr.${BASE_DOMAIN}`)"
            - "traefik.http.routers.sonarr.entrypoints=websecure"
            - "traefik.http.routers.sonarr.tls=true"
            - "traefik.http.routers.sonarr.tls.certresolver=le"
            - "traefik.http.services.sonarr.loadbalancer.server.port=8989"
            - "traefik.http.routers.sonarr.service=sonarr"
            - "traefik.http.routers.sonarr.tls.domains[0].main=*.${BASE_DOMAIN}"
            - "traefik.http.routers.bazarr.rule=Host(`bazarr.${BASE_DOMAIN}`)"
            - "traefik.http.routers.bazarr.entrypoints=websecure"
            - "traefik.http.routers.bazarr.tls=true"
            - "traefik.http.routers.bazarr.tls.certresolver=le"
            - "traefik.http.services.bazarr.loadbalancer.server.port=6767"
            - "traefik.http.routers.bazarr.service=bazarr"
            - "traefik.http.routers.bazarr.tls.domains[0].main=*.${BASE_DOMAIN}"
            - "traefik.http.routers.qbittorrent.rule=Host(`qb.${BASE_DOMAIN}`)"
            - "traefik.http.routers.qbittorrent.entrypoints=websecure"
            - "traefik.http.routers.qbittorrent.tls=true"
            - "traefik.http.routers.qbittorrent.tls.certresolver=le"
            - "traefik.http.services.qbittorrent.loadbalancer.server.port=8311"
            - "traefik.http.routers.qbittorrent.service=qbittorrent"
            - "traefik.http.routers.qbittorrent.tls.domains[0].main=*.${BASE_DOMAIN}"

        sabnzbd:
          image: lscr.io/linuxserver/sabnzbd:latest
          container_name: sabnzbd
          environment:
            - PUID=1000
            - PGID=1000
            - TZ=Europe/Amsterdam
          volumes:
            - /etc/localtime:/etc/localtime:ro
            - /mnt/docker-data/compose/arrstack/sabnzbd/config:/config
            - /mnt/docker-data/media/downloads:/downloads
            - /mnt/docker-data/media/downloads/incomplete:/incomplete-downloads
            - /mnt/docker-data/media/nzb:/NZB
          network_mode: service:wireguard
          depends_on:
            wireguard:
              condition: service_healthy
          restart: unless-stopped

        radarr:
          image: lscr.io/linuxserver/radarr:latest
          container_name: radarr
          environment:
            - PUID=1000
            - PGID=1000
            - TZ=Europe/Amsterdam
          volumes:
            - /etc/localtime:/etc/localtime:ro
            - /mnt/docker-data/compose/arrstack/radarr/config:/config
            - /mnt/docker-data/media/downloads:/downloads
            - /mnt/docker-data/media/downloads/incomplete:/incomplete-downloads
            - /mnt/docker-data/media/nzb:/NZB
            - /mnt/docker-data/media/movies:/movies
          network_mode: service:wireguard
          depends_on:
            wireguard:
              condition: service_healthy
          restart: unless-stopped

        sonarr:
          image: lscr.io/linuxserver/sonarr:latest
          container_name: sonarr
          environment:
            - PUID=1000
            - PGID=1000
            - TZ=Europe/Amsterdam
          volumes:
            - /etc/localtime:/etc/localtime:ro
            - /mnt/docker-data/compose/arrstack/sonarr/config:/config
            - /mnt/docker-data/media/downloads:/downloads
            - /mnt/docker-data/media/downloads/incomplete:/incomplete-downloads
            - /mnt/docker-data/media/nzb:/NZB
            - /mnt/docker-data/media/tvshows:/tvshows
          network_mode: service:wireguard
          depends_on:
            wireguard:
              condition: service_healthy
          restart: unless-stopped

        bazarr:
          image: lscr.io/linuxserver/bazarr:latest
          container_name: bazarr
          environment:
            - PUID=1000
            - PGID=1000
            - TZ=Europe/Amsterdam
          volumes:
            - /etc/localtime:/etc/localtime:ro
            - /mnt/docker-data/compose/arrstack/bazarr/config:/config
            - /mnt/docker-data/media:/media
          network_mode: service:wireguard
          depends_on:
            wireguard:
              condition: service_healthy
          restart: unless-stopped

        qbittorrent:
          image: lscr.io/linuxserver/qbittorrent:libtorrentv1-version-release-5.0.1_v1.2.19
          container_name: qbittorrent
          environment:
            - PUID=1000
            - PGID=1000
            - TZ=Europe/Amsterdam
            - WEBUI_PORT=8311
          volumes:
            - /etc/localtime:/etc/localtime:ro
            - /mnt/docker-data/compose/arrstack/qbittorrent/config:/config
            - /mnt/docker-data/media:/media
          network_mode: service:wireguard
          depends_on:
            wireguard:
              condition: service_healthy
          restart: unless-stopped

      networks:
        proxy:
          name: proxy
          external: true
      ENDARRSTACK
        echo "docker-compose.yml aangemaakt in arrstack/ (default WireGuard)"
      else
        echo "arrstack docker-compose.yml bestaat al, overslaan"
      fi

      if [ ! -f /mnt/docker-data/compose/arrstack/.env ]; then
        printf '%s\n' \
          'BASE_DOMAIN=local.yourdomain.com' \
          '# WireGuard (default) configuratie' \
          '# Zet je .conf bestand in: /mnt/docker-data/compose/arrstack/wireguard/config/wg_confs/' \
          '# Voorbeeld bestandsnaam: nl-ams-wg-001.conf' \
          '#' \
          '# Voeg deze PostUp/PostDown toe aan het [Interface] blok van je .conf voor LAN toegang:' \
          '# PostUp = ip rule add from 192.168.0.0/16 table main priority 99; ip route add 192.168.0.0/16 via 172.18.0.1 dev eth0' \
          '# PostDown = ip rule del from 192.168.0.0/16 table main priority 99; ip route del 192.168.0.0/16 via 172.18.0.1 dev eth0' \
          '# (vervang 172.18.0.1 door je Docker bridge gateway — zie: ip route | grep default)' \
          > /mnt/docker-data/compose/arrstack/.env
        chmod 600 /mnt/docker-data/compose/arrstack/.env
        echo "WireGuard .env aangemaakt"
        echo "  Zet je .conf in: /mnt/docker-data/compose/arrstack/wireguard/config/wg_confs/"
        echo "  Voeg PostUp/PostDown toe aan [Interface] voor LAN toegang (zie .env voor details)"
      else
        grep -q "^BASE_DOMAIN=" /mnt/docker-data/compose/arrstack/.env || echo "BASE_DOMAIN=local.yourdomain.com" >> /mnt/docker-data/compose/arrstack/.env
      fi
ENDARRSTACK_DEFAULT
else
cat >> "$SNIPPET_DIR/ubuntu-docker.yaml" << 'ENDARRSTACK_PIA'
      # --- Arrstack: wireguard (PIA) + arr services + qbittorrent ---
      mkdir -p /mnt/docker-data/compose/arrstack
      if [ ! -f /mnt/docker-data/compose/arrstack/docker-compose.yml ]; then
        cat > /mnt/docker-data/compose/arrstack/docker-compose.yml <<'ENDARRSTACK'
      services:
        wireguard:
          image: thrnz/docker-wireguard-pia:latest
          container_name: wireguard
          cap_add:
            - NET_ADMIN
          devices:
            - /dev/net/tun:/dev/net/tun
          environment:
            - LOC=nl_amsterdam
            - USER=${PIA_USER}
            - PASS=${PIA_PASS}
            - LOCAL_NETWORK=192.168.0.0/16
            - FIREWALL=1
            - KEEPALIVE=25
            - PORT_FORWARDING=0
          volumes:
            - /mnt/docker-data/compose/arrstack/wireguard/pia:/pia
          networks:
            - proxy
          ports:
            - 8301:8080  # sabnzbd
            - 8302:7878  # radarr
            - 8303:8989  # sonarr
            - 6767:6767  # bazarr
            - 8311:8311  # qbittorrent webui
            - 43398:43398
            - 43398:43398/udp
          sysctls:
            - net.ipv4.conf.all.src_valid_mark=1
          restart: unless-stopped
          healthcheck:
            test: ping -c 1 www.privateinternetaccess.com || exit 1
            interval: 30s
            timeout: 10s
            retries: 3
            start_period: 30s
          labels:
            - "traefik.enable=true"
            - "traefik.http.routers.sabnzbd.rule=Host(`sabnzbd.${BASE_DOMAIN}`)"
            - "traefik.http.routers.sabnzbd.entrypoints=websecure"
            - "traefik.http.routers.sabnzbd.tls=true"
            - "traefik.http.routers.sabnzbd.tls.certresolver=le"
            - "traefik.http.services.sabnzbd.loadbalancer.server.port=8080"
            - "traefik.http.routers.sabnzbd.service=sabnzbd"
            - "traefik.http.routers.sabnzbd.tls.domains[0].main=*.${BASE_DOMAIN}"
            - "traefik.http.routers.radarr.rule=Host(`radarr.${BASE_DOMAIN}`)"
            - "traefik.http.routers.radarr.entrypoints=websecure"
            - "traefik.http.routers.radarr.tls=true"
            - "traefik.http.routers.radarr.tls.certresolver=le"
            - "traefik.http.services.radarr.loadbalancer.server.port=7878"
            - "traefik.http.routers.radarr.service=radarr"
            - "traefik.http.routers.radarr.tls.domains[0].main=*.${BASE_DOMAIN}"
            - "traefik.http.routers.sonarr.rule=Host(`sonarr.${BASE_DOMAIN}`)"
            - "traefik.http.routers.sonarr.entrypoints=websecure"
            - "traefik.http.routers.sonarr.tls=true"
            - "traefik.http.routers.sonarr.tls.certresolver=le"
            - "traefik.http.services.sonarr.loadbalancer.server.port=8989"
            - "traefik.http.routers.sonarr.service=sonarr"
            - "traefik.http.routers.sonarr.tls.domains[0].main=*.${BASE_DOMAIN}"
            - "traefik.http.routers.bazarr.rule=Host(`bazarr.${BASE_DOMAIN}`)"
            - "traefik.http.routers.bazarr.entrypoints=websecure"
            - "traefik.http.routers.bazarr.tls=true"
            - "traefik.http.routers.bazarr.tls.certresolver=le"
            - "traefik.http.services.bazarr.loadbalancer.server.port=6767"
            - "traefik.http.routers.bazarr.service=bazarr"
            - "traefik.http.routers.bazarr.tls.domains[0].main=*.${BASE_DOMAIN}"
            - "traefik.http.routers.qbittorrent.rule=Host(`qb.${BASE_DOMAIN}`)"
            - "traefik.http.routers.qbittorrent.entrypoints=websecure"
            - "traefik.http.routers.qbittorrent.tls=true"
            - "traefik.http.routers.qbittorrent.tls.certresolver=le"
            - "traefik.http.services.qbittorrent.loadbalancer.server.port=8311"
            - "traefik.http.routers.qbittorrent.service=qbittorrent"
            - "traefik.http.routers.qbittorrent.tls.domains[0].main=*.${BASE_DOMAIN}"

        sabnzbd:
          image: lscr.io/linuxserver/sabnzbd:latest
          container_name: sabnzbd
          environment:
            - PUID=1000
            - PGID=1000
            - TZ=Europe/Amsterdam
          volumes:
            - /etc/localtime:/etc/localtime:ro
            - /mnt/docker-data/compose/arrstack/sabnzbd/config:/config
            - /mnt/docker-data/media/downloads:/downloads
            - /mnt/docker-data/media/downloads/incomplete:/incomplete-downloads
            - /mnt/docker-data/media/nzb:/NZB
          network_mode: service:wireguard
          depends_on:
            wireguard:
              condition: service_healthy
          restart: unless-stopped

        radarr:
          image: lscr.io/linuxserver/radarr:latest
          container_name: radarr
          environment:
            - PUID=1000
            - PGID=1000
            - TZ=Europe/Amsterdam
          volumes:
            - /etc/localtime:/etc/localtime:ro
            - /mnt/docker-data/compose/arrstack/radarr/config:/config
            - /mnt/docker-data/media/downloads:/downloads
            - /mnt/docker-data/media/downloads/incomplete:/incomplete-downloads
            - /mnt/docker-data/media/nzb:/NZB
            - /mnt/docker-data/media/movies:/movies
          network_mode: service:wireguard
          depends_on:
            wireguard:
              condition: service_healthy
          restart: unless-stopped

        sonarr:
          image: lscr.io/linuxserver/sonarr:latest
          container_name: sonarr
          environment:
            - PUID=1000
            - PGID=1000
            - TZ=Europe/Amsterdam
          volumes:
            - /etc/localtime:/etc/localtime:ro
            - /mnt/docker-data/compose/arrstack/sonarr/config:/config
            - /mnt/docker-data/media/downloads:/downloads
            - /mnt/docker-data/media/downloads/incomplete:/incomplete-downloads
            - /mnt/docker-data/media/nzb:/NZB
            - /mnt/docker-data/media/tvshows:/tvshows
          network_mode: service:wireguard
          depends_on:
            wireguard:
              condition: service_healthy
          restart: unless-stopped

        bazarr:
          image: lscr.io/linuxserver/bazarr:latest
          container_name: bazarr
          environment:
            - PUID=1000
            - PGID=1000
            - TZ=Europe/Amsterdam
          volumes:
            - /etc/localtime:/etc/localtime:ro
            - /mnt/docker-data/compose/arrstack/bazarr/config:/config
            - /mnt/docker-data/media:/media
          network_mode: service:wireguard
          depends_on:
            wireguard:
              condition: service_healthy
          restart: unless-stopped

        qbittorrent:
          image: lscr.io/linuxserver/qbittorrent:libtorrentv1-version-release-5.0.1_v1.2.19
          container_name: qbittorrent
          environment:
            - PUID=1000
            - PGID=1000
            - TZ=Europe/Amsterdam
            - WEBUI_PORT=8311
          volumes:
            - /etc/localtime:/etc/localtime:ro
            - /mnt/docker-data/compose/arrstack/qbittorrent/config:/config
            - /mnt/docker-data/media:/media
          network_mode: service:wireguard
          depends_on:
            wireguard:
              condition: service_healthy
          restart: unless-stopped

      networks:
        proxy:
          name: proxy
          external: true
      ENDARRSTACK
        echo "docker-compose.yml aangemaakt in arrstack/ (PIA variant)"
      else
        echo "arrstack docker-compose.yml bestaat al, overslaan"
      fi

      if [ ! -f /mnt/docker-data/compose/arrstack/.env ]; then
        printf '%s\n' \
          'BASE_DOMAIN=local.yourdomain.com' \
          '# PIA VPN credentials for the arrstack WireGuard container' \
          '# Fill in your PIA username and password before starting the arrstack' \
          'PIA_USER=your-pia-username' \
          'PIA_PASS=your-pia-password' \
          > /mnt/docker-data/compose/arrstack/.env
        chmod 600 /mnt/docker-data/compose/arrstack/.env
        echo "PIA .env aangemaakt — vul je PIA credentials in voor je de arrstack start"
        echo "  nano /mnt/docker-data/compose/arrstack/.env"
      else
        grep -q "^BASE_DOMAIN=" /mnt/docker-data/compose/arrstack/.env || echo "BASE_DOMAIN=local.yourdomain.com" >> /mnt/docker-data/compose/arrstack/.env
      fi
ENDARRSTACK_PIA
fi

cat >> "$SNIPPET_DIR/ubuntu-docker.yaml" << 'ENDSNIPPET2'
      if [ -f /mnt/docker-data/compose/traefik/traefik.yml ]; then
        cp /mnt/docker-data/compose/traefik/traefik.yml \
           /mnt/docker-data/compose/traefik/traefik.yml.bak.$(date +%s)
      fi
      cat > /mnt/docker-data/compose/traefik/traefik.yml <<'ENDTRAEFIK'
      api:
        dashboard: true

      entryPoints:
        web:
          address: ":80"
          http:
            redirections:
              entryPoint:
                to: websecure
                scheme: https
                permanent: true
        websecure:
          address: ":443"

      providers:
        docker:
          endpoint: "unix:///var/run/docker.sock"
          exposedByDefault: false
        file:
          filename: /config.yml

      serversTransport:
        insecureSkipVerify: true

      # email is set via container env: TRAEFIK_CERTIFICATESRESOLVERS_LE_ACME_EMAIL
      certificatesResolvers:
        le:
          acme:
            email: "CHANGE-ME@example.com"
            storage: /acme.json
            caServer: "https://acme-staging-v02.api.letsencrypt.org/directory"
            #caServer: "https://acme-v02.api.letsencrypt.org/directory"
            dnsChallenge:
              provider: cloudflare
              propagation:
                delayBeforeChecks: 30
              resolvers:
                - "1.1.1.1:53"
                - "8.8.8.8:53"

      log:
        level: INFO
      ENDTRAEFIK
        echo "traefik.yml aangemaakt/bijgewerkt"

      if [ ! -f /mnt/docker-data/compose/traefik/config.yml ]; then
        cat > /mnt/docker-data/compose/traefik/config.yml <<'ENDCONFIG'
      http:
        routers:
          example-router:
            rule: "Host(`example.local.yourdomain.com`)"
            service: example-service
            entryPoints:
              - websecure
            tls:
              certResolver: le
        services:
          example-service:
            loadBalancer:
              servers:
                - url: "http://192.168.1.1:8080"
      ENDCONFIG
        echo "traefik config.yml aangemaakt"
      fi

      if [ ! -f /mnt/docker-data/compose/traefik/acme.json ]; then
        touch /mnt/docker-data/compose/traefik/acme.json
        chmod 600 /mnt/docker-data/compose/traefik/acme.json
        echo "acme.json aangemaakt"
      fi

      echo "=== Persistent Docker Storage setup compleet! ==="
ENDSNIPPET2

cat >> "$SNIPPET_DIR/ubuntu-docker.yaml" << ENDRUNCMD

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - curl -fsSL https://get.docker.com | sh
  - systemctl stop docker docker.socket
  - /root/setup-persistent-docker.sh
  - rm -rf /mnt/docker-data/docker/containers 2>/dev/null || true
  - rm -rf /mnt/docker-data/docker/network 2>/dev/null || true
  - rm -rf /var/lib/docker/containers 2>/dev/null || true
  - rm -rf /var/lib/docker/network 2>/dev/null || true
  - systemctl enable docker
  - systemctl start docker
  - usermod -aG docker ${VM_USER}
  - sleep 5
  - cd /mnt/docker-data/compose/homelab && docker compose up -d --remove-orphans
  - cd /mnt/docker-data/compose/arrstack && docker compose up -d
  - |
    log_info() { echo "[INFO] \$1"; }
    log_warn() { echo "[WARN] \$1"; }
    BASE_DOMAIN=\$(grep '^BASE_DOMAIN=' /mnt/docker-data/compose/arrstack/.env 2>/dev/null | cut -d= -f2 || echo "local.yourdomain.com")
    # Configure SABnzbd hostname whitelist for reverse proxy access
    log_info "Waiting for SABnzbd to initialize config..."
    SABNZBD_INI="/mnt/docker-data/compose/arrstack/sabnzbd/config/sabnzbd.ini"
    ATTEMPTS=0
    while [ ! -f "\$SABNZBD_INI" ] && [ \$ATTEMPTS -lt 30 ]; do
      sleep 2
      ATTEMPTS=\$((ATTEMPTS + 1))
    done
    if [ -f "\$SABNZBD_INI" ]; then
      cd /mnt/docker-data/compose/arrstack && docker compose stop sabnzbd
      if grep -q "^host_whitelist" "\$SABNZBD_INI"; then
        sed -i "s/^host_whitelist = .*/& sabnzbd.\${BASE_DOMAIN}/" "\$SABNZBD_INI"
      else
        sed -i "/^\[misc\]/a host_whitelist = sabnzbd.\${BASE_DOMAIN}" "\$SABNZBD_INI"
      fi
      cd /mnt/docker-data/compose/arrstack && docker compose start sabnzbd
      log_info "SABnzbd hostname whitelist configured"
    else
      log_warn "SABnzbd config not found after 60s — add sabnzbd.\${BASE_DOMAIN} to host_whitelist manually"
    fi
ENDRUNCMD

# --- ubuntu-gui.yaml ---
generate_cloudinit_header > "$SNIPPET_DIR/ubuntu-gui.yaml"
cat >> "$SNIPPET_DIR/ubuntu-gui.yaml" << 'EOF'

packages:
  - qemu-guest-agent
  - ubuntu-desktop
  - gnome-shell
  - gnome-terminal
  - gnome-tweaks
  - curl
  - vim
  - htop
  - firefox

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - systemctl set-default graphical.target
  - systemctl enable gdm
  - systemctl start gdm
EOF

success "Snippets aangemaakt in: $SNIPPET_DIR"

# Ensure correct permissions
chown -R root:root "$SNIPPET_DIR"
chmod -R 644 "$SNIPPET_DIR"/*.yaml

# ==============================
# Verify that Proxmox sees the snippets
# ==============================
info "Verifying Proxmox can see snippets..."
sleep 2

if pvesm list "$SNIPPET_STORAGE" -content snippets 2>/dev/null | grep -q "ubuntu-day1.yaml"; then
    success "Snippets zijn zichtbaar in Proxmox storage"
else
    success "Snippets not yet visible, restarting daemon..."
    info "Restarting storage daemon..."
    systemctl restart pvedaemon pveproxy >/dev/null 2>&1
    sleep 3

    if pvesm list "$SNIPPET_STORAGE" -content snippets 2>/dev/null | grep -q "ubuntu-day1.yaml"; then
        success "Snippets zijn nu zichtbaar"
    else
        fail "Snippets niet zichtbaar in Proxmox. Check handmatig: pvesm list $SNIPPET_STORAGE -content snippets"
    fi
fi

# ==============================
# Write config file for new script
# ==============================
info "Creating snippet storage config file..."
cat > "$CONFIG_DIR/snippet-storage.conf" << EOF
SNIPPET_STORAGE=local
EOF
success "Config saved: local"

# ==============================
# new vm script (sources lib.sh)
# ==============================
info "Creating new script..."

if [[ -f "$NEW_SCRIPT" ]]; then
    mv "$NEW_SCRIPT" "$NEW_SCRIPT.bak.$(date +%s)"
fi

cat > "$NEW_SCRIPT" << 'EOFSCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# Source shared library
LIB_FILE="/opt/vmconfigs/lib.sh"
if [[ ! -f "$LIB_FILE" ]]; then
    echo "FOUT: $LIB_FILE niet gevonden. Run eerst het setup script."
    exit 1
fi
source "$LIB_FILE"

OS="${1:-}"
[[ -n "$OS" ]] || fail "Gebruik: new <os>"

CONFIG_DIR="/opt/vmconfigs"
TEMPLATE_DIR="/opt/templates"
STORAGE="local-lvm"
JSON_NAMES="$CONFIG_DIR/names.json"

command -v jq >/dev/null 2>&1 || fail "jq not found. Run proxmox-setup-vms.sh first to install it."

# ==============================
# Load snippet storage from config
# ==============================
if [[ -f "$CONFIG_DIR/snippet-storage.conf" ]]; then
    source "$CONFIG_DIR/snippet-storage.conf"
else
    fail "Config not found. Run the setup script first."
fi

# ==============================
# Load default VM user and IP
# ==============================
if [[ -f "$CONFIG_DIR/defaults.conf" ]]; then
    source "$CONFIG_DIR/defaults.conf"
fi
VM_USER="${VM_USER:-pasta}"
DOCKER_VM_IP="${DOCKER_VM_IP:-}"
DOCKER_VM_GW="${DOCKER_VM_GW:-}"

# Verify snippets exist
if ! pvesm list "$SNIPPET_STORAGE" -content snippets 2>/dev/null | grep -q "ubuntu-day1.yaml"; then
    fail "Snippets not found in storage '$SNIPPET_STORAGE'. Run the setup script first."
fi

ADJECTIVES=( $(jq -r '.adjectives[]' "$JSON_NAMES") )
NAMES=( $(jq -r '.names[]' "$JSON_NAMES") )

# ==============================
# Pick a VM name in eps-x-y style (unique name)
# ==============================
MAX_MINOR=20
MAX_MAJOR=20

get_next_eps_name() {
    EXISTING=$(qm list | awk '{print $2}' | grep -E '^eps-[0-9]+-[0-9]+-' || true)

    HIGHEST_MAJOR=0
    HIGHEST_MINOR=0

    for vm in $EXISTING; do
        parts=$(echo "$vm" | cut -d- -f2-3)
        major=${parts%-*}
        minor=${parts#*-}
        if (( major > HIGHEST_MAJOR )) || { (( major == HIGHEST_MAJOR )) && (( minor > HIGHEST_MINOR )); }; then
            HIGHEST_MAJOR=$major
            HIGHEST_MINOR=$minor
        fi
    done

    if (( HIGHEST_MAJOR == 0 && HIGHEST_MINOR == 0 )); then
        NEXT_MAJOR=1
        NEXT_MINOR=1
    else
        NEXT_MINOR=$((HIGHEST_MINOR + 1))
        NEXT_MAJOR=$HIGHEST_MAJOR
    fi

    if (( NEXT_MINOR > MAX_MINOR )); then
        NEXT_MINOR=1
        NEXT_MAJOR=$((NEXT_MAJOR + 1))
        if (( NEXT_MAJOR > MAX_MAJOR )); then
            fail "No free eps numbering available"
        fi
    fi

    # Extract all already-used names
    USED_NAMES=()
    for vm in $EXISTING; do
        name_part=$(echo "$vm" | cut -d- -f4)
        USED_NAMES+=("$name_part")
    done

    # Pick a name that hasn't been used yet
    MAX_ATTEMPTS=100
    ATTEMPT=0
    while [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; do
        NAME_PICK=${NAMES[RANDOM % ${#NAMES[@]}]}

        # Check if this name already exists
        if [[ ! " ${USED_NAMES[@]} " =~ " ${NAME_PICK} " ]]; then
            break
        fi
        ATTEMPT=$((ATTEMPT + 1))
    done

    if [[ $ATTEMPT -eq $MAX_ATTEMPTS ]]; then
        fail "Could not find a unique name after $MAX_ATTEMPTS attempts"
    fi

    # Extension can be random (reuse allowed)
    EXT_PICK=${ADJECTIVES[RANDOM % ${#ADJECTIVES[@]}]}

    candidate="eps-${NEXT_MAJOR}-${NEXT_MINOR}-${NAME_PICK}-${EXT_PICK}"
    candidate_safe="${candidate//_/-}"

    echo "$candidate_safe"
}

# ==============================
# Banner
# ==============================
echo -e "${MAGENTA_90}░░░░░░░░░░░▀█▀░█▀█░█▀▀░▀█▀░█▀█░█░░░█░░░░░█▀█░█▀▀░█░█░░░░░░░░░░░░${NC}"
echo -e "${MAGENTA_90}░░░░░░░░░░░░█░░█░█░▀▀█░░█░░█▀█░█░░░█░░░░░█░█░█▀▀░█▄█░░░░░░░░░░░░${NC}"
echo -e "${MAGENTA_90}░░░░░░░░░░░▀▀▀░▀░▀░▀▀▀░░▀░░▀░▀░▀▀▀░▀▀▀░░░▀░▀░▀▀▀░▀░▀░░░░░░░░░░░░${NC}"
echo -e "${MAGENTA_90}░░░█░█░▀█▀░█▀▄░▀█▀░█░█░█▀█░█░░░░░█▄█░█▀█░█▀▀░█░█░▀█▀░█▀█░█▀▀░░░░${NC}"
echo -e "${MAGENTA_90}░░░▀▄▀░░█░░█▀▄░░█░░█░█░█▀█░█░░░░░█░█░█▀█░█░░░█▀█░░█░░█░█░█▀▀░░░░${NC}"
echo -e "${MAGENTA_90}░░░░▀░░▀▀▀░▀░▀░░▀░░▀▀▀░▀░▀░▀▀▀░░░▀░▀░▀░▀░▀▀▀░▀░▀░▀▀▀░▀░▀░▀▀▀░░░░${NC}"

VM_NAME=$(get_next_eps_name)
success "Geselecteerde VM naam: $VM_NAME"

# ==============================
# Docker VM protection
# ==============================
if [[ "$OS" == "docker" ]]; then
    # Find ALL existing docker VMs
    ALL_VMS=$(qm list | awk 'NR>1 {print $1, $2, $3}')
    DOCKER_VMS=()
    DOCKER_VMIDS=()
    DOCKER_STATUSES=()

    while IFS=' ' read -r vmid vmname vmstatus; do
        [[ -z "$vmid" ]] && continue
        if is_docker_vm "$vmid"; then
            DOCKER_VMS+=("$vmname")
            DOCKER_VMIDS+=("$vmid")
            DOCKER_STATUSES+=("$vmstatus")
        fi
    done <<< "$ALL_VMS"

    if [[ ${#DOCKER_VMS[@]} -gt 0 ]]; then
        echo ""
        echo "========================================"
        echo "  WAARSCHUWING: Docker VM(s) gevonden!"
        echo "========================================"
        echo ""

        for idx in "${!DOCKER_VMS[@]}"; do
            echo "  [$((idx+1))] Naam:   ${DOCKER_VMS[$idx]}"
            echo "      VMID:   ${DOCKER_VMIDS[$idx]}"
            echo "      Status: ${DOCKER_STATUSES[$idx]}"
            echo ""
        done

        read -p "${#DOCKER_VMS[@]} docker VM(s) already exist. Stop all running ones and create a new one? (yes/no): " CONFIRM
        if [[ "$CONFIRM" != "yes" ]]; then
            fail "Creation cancelled by user"
        fi

        # Stop all running docker VMs via graceful stop
        for idx in "${!DOCKER_VMS[@]}"; do
            if [[ "${DOCKER_STATUSES[$idx]}" == "running" ]]; then
                graceful_stop_docker_vm "${DOCKER_VMIDS[$idx]}" "${DOCKER_VMS[$idx]}" 300
                success "Docker VM ${DOCKER_VMS[$idx]} gestopt"
            else
                success "Docker VM ${DOCKER_VMS[$idx]} staat al stil"
            fi
        done

        echo ""
        echo -e "  ${YELLOW_90}Tip: verwijder oude VMs handmatig met: qm destroy <vmid>${NC}"
        echo ""
    else
        success "No existing docker VM found, creation allowed"
    fi
fi

CONFIG_FILE="$CONFIG_DIR/$OS.conf"
TEMPLATE_FILE="$TEMPLATE_DIR/$OS.template"
[[ -f "$CONFIG_FILE" ]] || fail "Unknown OS type: $OS"
[[ -f "$TEMPLATE_FILE" ]] || fail "Unknown OS template: $OS"

source "$CONFIG_FILE"
source "$TEMPLATE_FILE"

# ==============================
# Determine tags
# ==============================
if [[ "$OS" == "docker" ]]; then
  TAGS="docker,ubuntu"
elif [[ "$OS" == "ubuntu-gui" ]]; then
  TAGS="ubuntu,gui,server"
elif [[ "$OS" == "ubuntu-large" ]]; then
  TAGS="ubuntu,large,server"
else
  TAGS="$OS,server"
fi

VMID=$(pvesh get /cluster/nextid 2>/dev/null)
[[ "$VMID" =~ ^[0-9]+$ ]] || fail "Could not retrieve next VMID"

success "Nieuwe VMID = $VMID"

if ! qm status "$TEMPLATE_ID" &>/dev/null; then
    fail "Template $TEMPLATE_ID bestaat niet!"
fi

progress_bar 0 "Clonen naar $VM_NAME"

CLONE_OUTPUT=$(mktemp)
set +o pipefail
qm clone "$TEMPLATE_ID" "$VMID" --name "$VM_NAME" --full 2>&1 | tee "$CLONE_OUTPUT" | while IFS= read -r line; do
    if [[ "$line" =~ ([0-9]+\.[0-9]+)% ]]; then
        pct=${BASH_REMATCH[1]%.*}
        if (( pct < 100 )); then
            progress_bar "$pct" "Clonen naar $VM_NAME"
        fi
    fi
done
CLONE_EXIT=${PIPESTATUS[0]}
set -o pipefail

if [[ $CLONE_EXIT -ne 0 ]]; then
    echo ""
    CLONE_ERR=$(grep -v "^$\|%" "$CLONE_OUTPUT" 2>/dev/null || true)
    rm -f "$CLONE_OUTPUT"
    if [[ -n "$CLONE_ERR" ]]; then
        fail "Clone mislukt: $CLONE_ERR"
    else
        fail "Clone mislukt (exit code $CLONE_EXIT)"
    fi
fi
rm -f "$CLONE_OUTPUT"
progress_bar 100 "Clone voltooid"
success "Template succesvol gecloned naar VMID $VMID"

info "VM configureren..."
qm set "$VMID" --agent enabled=1 >/dev/null 2>&1
qm set "$VMID" --cores "$CORES" --memory "$MEMORY" >/dev/null 2>&1
qm set "$VMID" --tags "$TAGS" >/dev/null 2>&1

# Disk loop: for docker VMs extra disks start at scsi2 (scsi1 = persistent storage)
if [[ "$OS" == "docker" ]]; then
    SCSI_OFFSET=1
else
    SCSI_OFFSET=0
fi

i=1
while true; do
    VAR="DISK$i"
    VALUE=${!VAR:-}
    [[ -z "$VALUE" ]] && break

    if [[ $i -eq 1 ]]; then
        qm resize "$VMID" scsi0 "$VALUE" >/dev/null 2>&1
    else
        SIZE_NUM=${VALUE%G}
        SCSI_IDX=$((i + SCSI_OFFSET))
        qm set "$VMID" --scsi"$SCSI_IDX" $STORAGE:$SIZE_NUM >/dev/null 2>&1
    fi
    i=$((i+1))
done

qm set "$VMID" --net0 virtio,bridge="$BRIDGE" >/dev/null 2>&1
qm set "$VMID" --ciuser "$VM_USER" >/dev/null 2>&1
if [[ "$OS" == "docker" && -n "$DOCKER_VM_IP" && -n "$DOCKER_VM_GW" ]]; then
    qm set "$VMID" --ipconfig0 "ip=${DOCKER_VM_IP},gw=${DOCKER_VM_GW}" >/dev/null 2>&1
    success "Vast IP ingesteld: ${DOCKER_VM_IP} (gw: ${DOCKER_VM_GW})"
else
    qm set "$VMID" --ipconfig0 ip=dhcp >/dev/null 2>&1
fi

# cicustom selection + attach persistent storage for docker
if [[ "$OS" == "docker" ]]; then
    qm set "$VMID" --cicustom "user=local:snippets/ubuntu-docker.yaml" >/dev/null 2>&1

    # Attach persistent docker storage (uit defaults.conf)
    info "Attaching persistent docker storage..."

    # Gebruik DISK_DEVICE uit defaults.conf (gezet door proxmox-setup-storage.sh)
    STORAGE_PARTITION="${DISK_DEVICE:-}1"

    if [[ -n "${DISK_DEVICE:-}" ]] && [[ -b "$STORAGE_PARTITION" ]]; then
        qm set "$VMID" --scsi1 "$STORAGE_PARTITION" >/dev/null 2>&1
        success "Persistent storage gekoppeld: $STORAGE_PARTITION → scsi1"
    elif [[ -n "${DISK_DEVICE:-}" ]] && [[ -b "$DISK_DEVICE" ]]; then
        qm set "$VMID" --scsi1 "$DISK_DEVICE" >/dev/null 2>&1
        success "Persistent storage gekoppeld: $DISK_DEVICE (hele disk) → scsi1"
    else
        fail "Geen DISK_DEVICE gevonden in defaults.conf. Draai eerst proxmox-setup-storage.sh (optie 2)."
    fi

elif [[ "$OS" == "ubuntu-gui" ]]; then
    qm set "$VMID" --cicustom "user=local:snippets/ubuntu-gui.yaml" >/dev/null 2>&1
    qm set "$VMID" --vga std >/dev/null 2>&1
else
    qm set "$VMID" --cicustom "user=local:snippets/ubuntu-day1.yaml" >/dev/null 2>&1
fi
success "VM geconfigureerd"

info "VM starten..."
qm start "$VMID" >/dev/null 2>&1 || fail "VM starten mislukt"
success "VM gestart"

# GUI needs much more time (desktop + gnome installation takes 5-10 min)
if [[ "$OS" == "ubuntu-gui" ]]; then
    MAX_WAIT=300
    echo -e "  ${YELLOW_90}ubuntu-gui: wait time increased to ${MAX_WAIT}s${NC}"
else
    MAX_WAIT=60
fi

WAITED=0
IP_ADDRESS=""
progress_bar 0 "Wachten op IP (0/${MAX_WAIT}s)"

while [[ $WAITED -lt $MAX_WAIT ]]; do
    sleep 2
    WAITED=$((WAITED + 2))

    pct=$((WAITED * 100 / MAX_WAIT))
    progress_bar "$pct" "Wachten op IP (${WAITED}/${MAX_WAIT}s)"

    IP_ADDRESS=$(qm guest cmd "$VMID" network-get-interfaces 2>/dev/null | \
        jq -r '.[] | select(.name != "lo") | .["ip-addresses"][]? | select(.["ip-address-type"] == "ipv4") | .["ip-address"]' 2>/dev/null | head -n1 || echo "")

    if [[ -n "$IP_ADDRESS" && "$IP_ADDRESS" != "null" ]]; then
        progress_bar 100 "IP gevonden!"
        success "IP-adres gevonden: $IP_ADDRESS"
        break
    fi
done

if [[ -z "$IP_ADDRESS" || "$IP_ADDRESS" == "null" ]]; then
    echo ""
    warn "Geen IP-adres gevonden binnen ${MAX_WAIT}s (controleer later handmatig)"
    IP_ADDRESS=""
fi

DESCRIPTION="## $VM_NAME

**Config:** $OS | **Aangemaakt:** $(date '+%d-%m-%Y %H:%M')

## Hardware
- Cores: $CORES
- Memory: $MEMORY MB
- Disk: ${DISK1}"

i=2
while true; do
    VAR="DISK$i"
    VALUE=${!VAR:-}
    [[ -z "$VALUE" ]] && break
    DESCRIPTION="$DESCRIPTION
- Disk$i: $VALUE"
    i=$((i+1))
done

# Always add network section
if [[ -n "$IP_ADDRESS" ]]; then
    DESCRIPTION="$DESCRIPTION

## Netwerk
- IP: $IP_ADDRESS
- SSH: ssh ${VM_USER}@$IP_ADDRESS
- SSH: ssh -i ~/.ssh/proxmox_vm_key ${VM_USER}@$IP_ADDRESS"
else
    DESCRIPTION="$DESCRIPTION

## Netwerk
- IP: nog niet beschikbaar (cloud-init nog bezig)
- SSH: ssh ${VM_USER}@<ip> (check Proxmox na ~5 min)"
fi

qm set "$VMID" --description "$DESCRIPTION" >/dev/null 2>&1
success "VM beschrijving toegevoegd"

clear

echo
echo -e "${PURPLE_90}═══ VM Klaar ═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN_90}Config${NC}: $OS"
echo -e "${GREEN_90}Naam${NC}:   $VM_NAME"
echo -e "${GREEN_90}VMID${NC}:   $VMID"
if [[ -n "$IP_ADDRESS" ]]; then
    echo -e "${GREEN_90}IP${NC}:     $IP_ADDRESS"
    echo ""
    echo -e "${GREEN_90}SSH${NC}:    ssh ${VM_USER}@$IP_ADDRESS"
    echo -e "${GREEN_90}SSH${NC}:    ssh -i ~/.ssh/proxmox_vm_key ${VM_USER}@$IP_ADDRESS"
else
    echo -e "${YELLOW_90}IP:     nog niet beschikbaar${NC}"
    echo ""
    echo -e "${YELLOW_90}        Cloud-init is nog bezig.${NC}"
    echo -e "${YELLOW_90}        Check IP over ~5 min via:${NC}"
    echo -e "${YELLOW_90}        qm guest cmd $VMID network-get-interfaces${NC}"
fi
echo -e "${PURPLE_90}════════════════════════════════════════════════════════════════════${NC}"
EOFSCRIPT

chmod +x "$NEW_SCRIPT"
success "new script klaar"

# ==============================
# Download Ubuntu cloud image
# ==============================
info "Checking Ubuntu cloud image..."
mkdir -p "$IMAGE_DIR"
if [[ ! -f "$IMAGE_PATH" ]]; then
  downloading "Ubuntu cloud image niet gevonden..."

  TOTAL=$(curl -sI "$IMAGE_URL" | grep -i content-length | awk '{print $2}' | tr -d '\r')
  curl -L "$IMAGE_URL" -o "$IMAGE_PATH" --silent --show-error &
  CURL_PID=$!

  while kill -0 $CURL_PID 2>/dev/null; do
    sleep 1
    DONE=$(stat -c%s "$IMAGE_PATH" 2>/dev/null || echo 0)
    if [[ $TOTAL -gt 0 ]]; then
      PCT=$(( DONE * 100 / TOTAL ))
      progress_bar "$PCT" "Downloaden ubuntu cloud image"
    fi
  done

  wait $CURL_PID
  #progress_bar 100 "Downloading ubuntu cloud image"
  success "Cloud image gedownload"
else
  skip "Cloud image bestaat al"
fi

# ==============================
# Create Proxmox template
# ==============================
info "Creating Proxmox template..."
if qm status $TEMPLATE_ID &>/dev/null; then
    skip "Template $TEMPLATE_ID bestaat al"
else
    qm create $TEMPLATE_ID --name "$TEMPLATE_NAME" --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0 --agent enabled=1 >/dev/null 2>&1
    qm importdisk $TEMPLATE_ID "$IMAGE_PATH" $STORAGE >/dev/null 2>&1
    qm set $TEMPLATE_ID --scsihw virtio-scsi-pci --scsi0 $STORAGE:vm-${TEMPLATE_ID}-disk-0 >/dev/null 2>&1
    qm set $TEMPLATE_ID --ide2 $STORAGE:cloudinit >/dev/null 2>&1
    qm set $TEMPLATE_ID --boot c --bootdisk scsi0 >/dev/null 2>&1
    qm set $TEMPLATE_ID --serial0 socket --vga serial0 >/dev/null 2>&1
    qm template $TEMPLATE_ID >/dev/null 2>&1
    success "Template aangemaakt"
fi

success "Setup afgerond!"
