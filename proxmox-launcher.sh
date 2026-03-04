#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Proxmox Launcher Menu
# ==============================
# Centraal startpunt voor alle Proxmox scripts.
# Plaats alle scripts in dezelfde map en start dit script.

# ==============================
# Source shared library (met fallback)
# ==============================
LIB_FILE="/opt/vmconfigs/lib.sh"
if [[ -f "$LIB_FILE" ]]; then
    source "$LIB_FILE"
else
    # Fallback: lokale definities als lib.sh nog niet bestaat
    MAGENTA_90='\033[38;2;255;0;124m'
    GREEN_90='\033[38;2;0;254;162m'
    PURPLE_90='\033[38;2;144;76;254m'
    YELLOW_90='\033[38;2;249;186;4m'
    RED_90='\033[38;2;255;0;54m'
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
        fi
    }
    info()    { local msg="$1"; stop_spinner; spinner "$msg" & SPINNER_PID=$!; tput civis 2>/dev/null || true; }
    success() { local msg="$1"; stop_spinner; printf "\r\033[K  ${GREEN_90}✓${NC} %s\n" "$msg"; tput cnorm 2>/dev/null || true; }
    fail()    { local msg="$1"; stop_spinner; printf "\r\033[K  ${RED_90}✗${NC} %s\n" "$msg"; tput cnorm 2>/dev/null || true; exit 1; }
    warn()    { local msg="$1"; stop_spinner; printf "\r\033[K  ${YELLOW_90}!${NC} %s\n" "$msg"; tput cnorm 2>/dev/null || true; }
    trap 'stop_spinner; tput cnorm 2>/dev/null' EXIT INT TERM
fi

# ==============================
# Script locaties (auto-detectie)
# ==============================
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

SCRIPT_PVE_INSTALL="$SCRIPT_DIR/proxmox-post-install.sh"
SCRIPT_DOCKER_STORAGE="$SCRIPT_DIR/proxmox-setup-storage.sh"
SCRIPT_SETUP="$SCRIPT_DIR/proxmox-setup-vms.sh"
SCRIPT_CLEANUP="$SCRIPT_DIR/proxmox-vm-cleanup.sh"
SCRIPT_TEST_DOCKER="$SCRIPT_DIR/proxmox-test-docker-vm.sh"
SCRIPT_SET_PASSWORD="$SCRIPT_DIR/proxmox-set-password.sh"
SCRIPT_BACKUP_DOCKER_FILES="$SCRIPT_DIR/proxmox-backup-docker-files.sh"
SCRIPT_RESTORE_DOCKER_FILES="$SCRIPT_DIR/proxmox-restore-docker-files.sh"

# ===============================
# Helper: check of script bestaat
# ===============================
run_script() {
    local script="$1"
    shift
    if [[ ! -f "$script" ]]; then
        warn "Script niet gevonden: $script"
        return 1
    fi
    echo ""
    bash "$script" "$@" || {
        local exit_code=$?
        echo ""
        warn "Script afgelopen met exit code $exit_code: $(basename "$script")"
        return 0
    }
}

# ==============================
# Menu tonen
# ==============================
show_menu() {
    clear
    echo ""
    echo -e "${MAGENTA_90}             ░░░░░█▀█░█▀▄░█▀█░█░█░█▄█░█▀█░█░█░░░░░░${NC}"
    echo -e "${MAGENTA_90}             ░░░░░█▀▀░█▀▄░█░█░▄▀▄░█░█░█░█░▄▀▄░░░░░░${NC}"
    echo -e "${MAGENTA_90}             ░░░░░▀░░░▀░▀░▀▀▀░▀░▀░▀░▀░▀▀▀░▀░▀░░░░░░${NC}"
    echo -e "${MAGENTA_90}             ░░░█░░░█▀█░█░█░█▀█░█▀▀░█░█░█▀▀░█▀▄░░░░${NC}"
    echo -e "${MAGENTA_90}             ░░░█░░░█▀█░█░█░█░█░█░░░█▀█░█▀▀░█▀▄░░░░${NC}"
    echo -e "${MAGENTA_90}             ░░░▀▀▀░▀░▀░▀▀▀░▀░▀░▀▀▀░▀░▀░▀▀▀░▀░▀░░░░${NC}"
    echo ""
    echo -e "  ${PURPLE_90}━━━ Installatie ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "    ${GREEN_90}1${NC})  Post-PVE Install"
    echo -e "         ${YELLOW_90}Repositories, nag fix, HA uitschakelen en update${NC}"
    echo ""
    echo -e "    ${GREEN_90}2${NC})  Setup Docker Storage  ${RED_90}⚠ eenmalig${NC}"
    echo -e "         ${YELLOW_90}Formatteert Samsung SSD als Docker storage${NC}"
    echo ""
    echo -e "    ${GREEN_90}3${NC})  Setup Proxmox VM automation"
    echo -e "         ${YELLOW_90}Installeert template, snippets en 'new' commando${NC}"
    echo ""
    echo -e "  ${PURPLE_90}━━━ Nieuwe VM ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "    ${GREEN_90}4${NC})  Nieuwe VM aanmaken"
    echo -e "         ${YELLOW_90}Kies uit: ubuntu, ubuntu-large, ubuntu-gui, docker${NC}"
    echo ""
    echo -e "  ${PURPLE_90}━━━ Maintenance ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "    ${GREEN_90}5${NC})  VM Cleanup"
    echo -e "         ${YELLOW_90}Beheer en verwijder eps-* VMs${NC}"
    echo ""
    echo -e "    ${GREEN_90}6${NC})  Test Docker VM"
    echo -e "         ${YELLOW_90}Volledige test suite voor een docker VM${NC}"
    echo ""
    echo -e "    ${GREEN_90}7${NC})  chmod +x scripts"
    echo -e "         ${YELLOW_90}Zet uitvoerrechten op alle .sh bestanden in deze map${NC}"
    echo ""
    echo -e "    ${GREEN_90}8${NC})  Set VM password"
    echo -e "         ${YELLOW_90}Set or change the user password on a running VM${NC}"
    echo ""
    echo -e "    ${GREEN_90}9${NC})  Backup Docker files"
    echo -e "         ${YELLOW_90}Backup compose/.env/traefik/wireguard naar ZIP voor scp download${NC}"
    echo ""
    echo -e "    ${GREEN_90}10${NC}) Restore Docker files"
    echo -e "         ${YELLOW_90}Zet een backup-ZIP terug naar de Docker VM${NC}"
    echo ""
    echo -e "  ${PURPLE_90}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "    ${RED_90}0${NC})  Afsluiten"
    echo ""
}

# ==============================
# Hoofdloop
# ==============================
while true; do
    show_menu
    read -p "  Keuze [0-10]: " choice

    case "$choice" in
        1)
            echo ""
            run_script "$SCRIPT_PVE_INSTALL"
            echo ""
            read -p "Druk op Enter om terug te gaan naar het menu..." _
            ;;
        2)
            echo ""
            warn "════════════════════════════════════════════════════"
            warn "  LET OP: Dit formatteert de Samsung SSD!"
            warn "  Alleen nodig bij eerste installatie."
            warn "  Alle bestaande data op de SSD gaat verloren!"
            warn "════════════════════════════════════════════════════"
            echo ""
            read -p "  Weet je zeker dat je wilt doorgaan? (ja/nee): " confirm
            case "${confirm,,}" in
                ja|j|yes|y)
                    run_script "$SCRIPT_DOCKER_STORAGE"
                    ;;
                *)
                    warn "Geannuleerd"
                    ;;
            esac
            echo ""
            read -p "Druk op Enter om terug te gaan naar het menu..." _
            ;;
        3)
            echo ""
            run_script "$SCRIPT_SETUP"
            echo ""
            read -p "Druk op Enter om terug te gaan naar het menu..." _
            ;;
        4)
            echo ""
            echo -e "  ${PURPLE_90}━━━ Kies VM type ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo -e "    ${GREEN_90}1${NC})  ubuntu          ${YELLOW_90}2C / 4GB / 10G${NC}"
            echo -e "    ${GREEN_90}2${NC})  ubuntu-large    ${YELLOW_90}2C / 32GB / 100G${NC}"
            echo -e "    ${GREEN_90}3${NC})  ubuntu-gui      ${YELLOW_90}4C / 12GB / 50G + desktop${NC}"
            echo -e "    ${GREEN_90}4${NC})  docker          ${YELLOW_90}2C / 20GB / 50G + SSD${NC}"
            echo ""
            echo -e "    ${RED_90}0${NC})  Terug"
            echo ""
            read -p "  Keuze [0-4]: " vm_choice

            case "$vm_choice" in
                1) VM_TYPE="ubuntu" ;;
                2) VM_TYPE="ubuntu-large" ;;
                3) VM_TYPE="ubuntu-gui" ;;
                4) VM_TYPE="docker" ;;
                0|"")
                    continue
                    ;;
                *)
                    warn "Ongeldige keuze: $vm_choice"
                    sleep 1
                    continue
                    ;;
            esac

            if ! command -v new >/dev/null 2>&1; then
                warn "'new' commando niet gevonden. Run eerst optie 3 (Setup Proxmox VM automation)."
            else
                echo ""
                new "$VM_TYPE"
            fi
            echo ""
            read -p "Druk op Enter om terug te gaan naar het menu..." _
            ;;
        5)
            echo ""
            run_script "$SCRIPT_CLEANUP"
            echo ""
            read -p "Druk op Enter om terug te gaan naar het menu..." _
            ;;
        6)
            echo ""
            read -p "  Voer VMID in van de docker VM: " vmid
            if [[ -z "$vmid" ]]; then
                warn "Geen VMID opgegeven"
            elif ! [[ "$vmid" =~ ^[0-9]+$ ]]; then
                warn "VMID moet een nummer zijn"
            else
                run_script "$SCRIPT_TEST_DOCKER" "$vmid"
            fi
            echo ""
            read -p "Druk op Enter om terug te gaan naar het menu..." _
            ;;
        7)
            echo ""
            info "chmod +x zetten op alle .sh scripts..."
            chmod +x "$SCRIPT_DIR"/*.sh
            success "Uitvoerrechten gezet op alle .sh bestanden in $SCRIPT_DIR"
            echo ""
            read -p "Druk op Enter om terug te gaan naar het menu..." _
            ;;
        8)
            echo ""
            run_script "$SCRIPT_SET_PASSWORD"
            echo ""
            read -p "Druk op Enter om terug te gaan naar het menu..." _
            ;;
        9)
            echo ""
            warn "Deze backup bevat secrets (.env / tokens / VPN configs). Bewaar de ZIP veilig!"
            echo ""
            run_script "$SCRIPT_BACKUP_DOCKER_FILES"
            echo ""
            read -p "Druk op Enter om terug te gaan naar het menu..." _
            ;;
        10)
            echo ""
            run_script "$SCRIPT_RESTORE_DOCKER_FILES"
            echo ""
            read -p "Druk op Enter om terug te gaan naar het menu..." _
            ;;
        0)
            echo ""
            success "Tot ziens!"
            echo ""
            exit 0
            ;;
        *)
            warn "Ongeldige keuze: $choice"
            sleep 1
            ;;
    esac
done