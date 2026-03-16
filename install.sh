#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Proxmox Setup — Bootstrap Installer
# ==============================
# Usage (run on your Proxmox host as root):
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/xthephreakx/proxmox-homelab-automation/main/install.sh)"

REPO="xthephreakx/proxmox-homelab-automation"
BRANCH="main"
INSTALL_DIR="/opt/proxmox-setup"

RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

SCRIPTS=(
    "proxmox-launcher.sh"
    "proxmox-post-install.sh"
    "proxmox-setup-storage.sh"
    "proxmox-setup-vms.sh"
    "proxmox-vm-cleanup.sh"
    "proxmox-test-docker-vm.sh"
    "proxmox-set-password.sh"
    "proxmox-backup-docker-files.sh"
    "proxmox-restore-docker-files.sh"
)

# ==============================
# Colors
# ==============================
MAGENTA='\033[38;2;255;0;124m'
GREEN='\033[38;2;0;254;162m'
YELLOW='\033[38;2;249;186;4m'
RED='\033[38;2;255;0;54m'
NC='\033[0m'

info()    { echo -e "  ${GREEN}✔${NC}  $*"; }
warn()    { echo -e "  ${YELLOW}!${NC}  $*"; }
error()   { echo -e "  ${RED}✘${NC}  $*"; exit 1; }
header()  { echo -e "\n${MAGENTA}$*${NC}\n"; }

# ==============================
# Checks
# ==============================
[[ "$EUID" -ne 0 ]] && error "Run this script as root."

if ! command -v curl &>/dev/null; then
    error "curl is required but not installed."
fi

if ! command -v pvesh &>/dev/null; then
    warn "pvesh not found — are you running this on a Proxmox host?"
    read -rp "  Continue anyway? [y/N] " confirm
    [[ "${confirm,,}" == "y" ]] || exit 1
fi

# ==============================
# Install
# ==============================
echo -e "${MAGENTA}"
echo '░░░░░░░░░░░░░░░░░█▀█░█▀▄░█▀█░█░█░█▄█░█▀█░█░█░░░█▀▀░█▀▀░▀█▀░█░█░█▀█░░░░░░░░░░░░░░'
echo '░░░░░░░░░░░░░░░░░█▀▀░█▀▄░█░█░▄▀▄░█░█░█░█░▄▀▄░░░▀▀█░█▀▀░░█░░█░█░█▀▀░░░░░░░░░░░░░░'
echo '░░░░░░░░░░░░░░░░░▀░░░▀░▀░▀▀▀░▀░▀░▀░▀░▀▀▀░▀░▀░░░▀▀▀░▀▀▀░░▀░░▀▀▀░▀░░░░░░░░░░░░░░░░'
echo '░░░█▀▄░█▀█░█▀█░▀█▀░█▀▀░▀█▀░█▀▄░█▀█░█▀█░░░▀█▀░█▀█░█▀▀░▀█▀░█▀█░█░░░█░░░█▀▀░█▀▄░░░░'
echo '░░░█▀▄░█░█░█░█░░█░░▀▀█░░█░░█▀▄░█▀█░█▀▀░░░░█░░█░█░▀▀█░░█░░█▀█░█░░░█░░░█▀▀░█▀▄░░░░'
echo '░░░▀▀░░▀▀▀░▀▀▀░░▀░░▀▀▀░░▀░░▀░▀░▀░▀░▀░░░░░▀▀▀░▀░▀░▀▀▀░░▀░░▀░▀░▀▀▀░▀▀▀░▀▀▀░▀░▀░░░░'
echo -e "${NC}"

info "Installing to: ${INSTALL_DIR}"
mkdir -p "$INSTALL_DIR"

for script in "${SCRIPTS[@]}"; do
    url="${RAW_BASE}/${script}"
    dest="${INSTALL_DIR}/${script}"

    if curl -fsSL "$url" -o "$dest"; then
        chmod +x "$dest"
        info "Downloaded: ${script}"
    else
        error "Failed to download: ${url}"
    fi
done

# ==============================
# Done
# ==============================
echo ""
info "All scripts installed in ${INSTALL_DIR}"
echo ""
echo -e "  ${MAGENTA}Start the launcher:${NC}"
echo -e "  ${GREEN}${INSTALL_DIR}/proxmox-launcher.sh${NC}"
echo ""

if [[ "${FROM_LAUNCHER:-0}" == "1" ]]; then
    info "Scripts bijgewerkt — terug naar launcher menu"
else
    read -rp "  Launch now? [Y/n] " launch
    if [[ "${launch,,}" != "n" ]]; then
        exec bash "${INSTALL_DIR}/proxmox-launcher.sh"
    fi
fi
