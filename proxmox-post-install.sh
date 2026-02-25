#!/usr/bin/env bash

set -euo pipefail
shopt -s inherit_errexit nullglob

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

info() {
    local msg="$1"
    spinner "$msg" &
    SPINNER_PID=$!
    tput civis 2>/dev/null || true
}

success() {
    local msg="$1"
    if [[ -n "${SPINNER_PID:-}" ]]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
    fi
    printf "\r\033[K  ${GREEN_90}✓${NC} %s\n" "$msg"
    tput cnorm 2>/dev/null || true
    SPINNER_PID=""
}

fail() {
    local msg="$1"
    if [[ -n "${SPINNER_PID:-}" ]]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
    fi
    printf "\r\033[K  ${RED_90}✗${NC} %s\n" "$msg"
    tput cnorm 2>/dev/null || true
    exit 1
}

msg_skip() {
    local msg="$1"
    if [[ -n "${SPINNER_PID:-}" ]]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
    fi
    printf "\r\033[K  ${BLUE_90}⊘${NC} %s\n" "$msg"
    tput cnorm 2>/dev/null || true
    SPINNER_PID=""
}

warn() {
    local msg="$1"
    if [[ -n "${SPINNER_PID:-}" ]]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
    fi
    printf "\r\033[K  ${YELLOW_90}!${NC} %s\n" "$msg"
    tput cnorm 2>/dev/null || true
    SPINNER_PID=""
}

trap 'kill "$SPINNER_PID" 2>/dev/null; tput cnorm 2>/dev/null' EXIT INT TERM

# ============================================================================
# HELPER FUNCTIES
# ============================================================================

header_info() {
    clear
    echo ""
    echo -e "${MAGENTA_90}  ░░░░░░░░░░░░░░░░░░█▀█░█░█░█▀▀░░░░░░░░░░░░░░░░░░░░${NC}"
    echo -e "${MAGENTA_90}  ░░░░░░░░░░░░░░░░░░█▀▀░▀▄▀░█▀▀░░░░░░░░░░░░░░░░░░░░${NC}"
    echo -e "${MAGENTA_90}  ░░░░░░░░░░░░░░░░░░▀░░░░▀░░▀▀▀░░░░░░░░░░░░░░░░░░░░${NC}"
    echo -e "${MAGENTA_90}  ░░░░█▀█░█▀█░█▀▀░▀█▀░░░▀█▀░█▀█░█▀▀░▀█▀░█▀█░█░░░░░░${NC}"
    echo -e "${MAGENTA_90}  ░░░░█▀▀░█░█░▀▀█░░█░░░░░█░░█░█░▀▀█░░█░░█▀█░█░░░░░░${NC}"
    echo -e "${MAGENTA_90}  ░░░░▀░░░▀▀▀░▀▀▀░░▀░░░░▀▀▀░▀░▀░▀▀▀░░▀░░▀░▀░▀▀▀░░░░${NC}"
    echo ""
}

get_pve_version() {
    local pve_ver
    pve_ver="$(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}')"
    echo "$pve_ver"
}

get_pve_major_minor() {
    local ver="$1"
    local major minor
    IFS='.' read -r major minor _ <<<"$ver"
    echo "$major $minor"
}

component_exists_in_sources() {
    local component="$1"
    grep -h -E "^[^#]*Components:[^#]*\b${component}\b" /etc/apt/sources.list.d/*.sources 2>/dev/null | grep -q .
}

# Variable to track if running in automatic mode
AUTO_MODE=false

# ============================================================================
# MAIN FUNCTIE
# ============================================================================

main() {
    header_info
    echo -e "  ${PURPLE_90}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${PURPLE_90}  Proxmox VE 9.x Post Install Script met Auto Mode           ${NC}"
    echo -e "  ${PURPLE_90}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Check Proxmox version
    local PVE_VERSION PVE_MAJOR PVE_MINOR
    PVE_VERSION="$(get_pve_version)"
    read -r PVE_MAJOR PVE_MINOR <<<"$(get_pve_major_minor "$PVE_VERSION")"

    if [[ "$PVE_MAJOR" != "9" ]]; then
        printf "  ${RED_90}✗${NC} Dit script ondersteunt alleen Proxmox VE 9.x\n"
        printf "  ${YELLOW_90}!${NC} Gedetecteerde versie: %s\n" "$PVE_VERSION"
        exit 1
    fi

    if ((PVE_MINOR < 0 || PVE_MINOR > 1)); then
        printf "  ${RED_90}✗${NC} Alleen Proxmox 9.0-9.1.x wordt ondersteund\n"
        printf "  ${YELLOW_90}!${NC} Gedetecteerde versie: %s\n" "$PVE_VERSION"
        exit 1
    fi

    printf "  ${GREEN_90}✓${NC} Proxmox VE %s gedetecteerd\n\n" "$PVE_VERSION"

    # Ask for automatic or manual mode
    while true; do
        echo -e "  ${PURPLE_90}━━━ Uitvoermodus ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "    ${GREEN_90}a${NC})  Automatisch  ${YELLOW_90}gebruik vooraf ingestelde instellingen${NC}"
        echo -e "    ${BLUE_90}m${NC})  Handmatig    ${YELLOW_90}bevestig elke stap${NC}"
        echo ""
        read -p "  Maak uw keuze [a/m]: " mode
        case $mode in
        [Aa]*)
            AUTO_MODE=true
            echo ""
            echo -e "  ${PURPLE_90}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "  ${GREEN_90}  AUTOMATISCHE MODUS - Standaard instellingen${NC}"
            echo -e "  ${PURPLE_90}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            printf "    ${GREEN_90}✓${NC} Migreer naar deb822 sources format\n"
            printf "    ${GREEN_90}✓${NC} Schakel legacy sources uit\n"
            printf "    ${RED_90}✗${NC} Verwijder pve-enterprise repository\n"
            printf "    ${RED_90}✗${NC} Verwijder ceph-enterprise repository\n"
            printf "    ${GREEN_90}✓${NC} Voeg pve-no-subscription repository toe\n"
            printf "    ${GREEN_90}✓${NC} Voeg ceph package repositories toe\n"
            printf "    ${BLUE_90}⊘${NC} Voeg NIET pvetest repository toe\n"
            printf "    ${GREEN_90}✓${NC} Schakel subscription nag uit\n"
            printf "    ${GREEN_90}✓${NC} Schakel High Availability uit\n"
            printf "    ${GREEN_90}✓${NC} Schakel Corosync uit\n"
            printf "    ${GREEN_90}✓${NC} Update Proxmox VE\n"
            printf "    ${GREEN_90}✓${NC} Herstart systeem\n"
            echo ""
            sleep 3
            break
            ;;
        [Mm]*)
            AUTO_MODE=false
            echo ""
            echo -e "  ${PURPLE_90}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "  ${YELLOW_90}  HANDMATIGE MODUS - Interactief${NC}"
            echo -e "  ${PURPLE_90}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            printf "  ${YELLOW_90}!${NC} Je wordt gevraagd om elke stap te bevestigen\n"
            echo ""
            sleep 2
            break
            ;;
        *)
            warn "Ongeldige keuze. Kies 'a' voor automatisch of 'm' voor handmatig."
            ;;
        esac
    done

    while true; do
        read -p "  Start het Proxmox VE Post Install Script? [y/n]: " yn
        case $yn in
        [Yy]*) break ;;
        [Nn]*)
            clear
            exit
            ;;
        *) warn "Antwoord met yes of no." ;;
        esac
    done

    echo ""
    start_routines_9
}

# ============================================================================
# PROXMOX VE 9.x ROUTINES
# ============================================================================

start_routines_9() {
    header_info

    # ──────────────────────────────────────────────────────────────────────
    # STAP 1: Check deb822 Sources
    # ──────────────────────────────────────────────────────────────────────
    if find /etc/apt/sources.list.d/ -maxdepth 1 -name '*.sources' | grep -q .; then
        if [[ "$AUTO_MODE" == false ]]; then
            whiptail --backtitle "Proxmox VE Helper Scripts" --title "Deb822 sources detected" \
                --msgbox "Modern deb822 sources (*.sources) already exist.\n\nNo changes to sources format required.\n\nYou may still have legacy sources.list or .list files, which you can disable in the next step." 12 65 || true
        else
            success "Modern deb822 sources aanwezig (geen actie vereist)"
        fi
    else
        # ──────────────────────────────────────────────────────────────────────
        # SUBSTAP: Disable legacy sources indien aanwezig
        # ──────────────────────────────────────────────────────────────────────
        check_and_disable_legacy_sources() {
            local LEGACY_COUNT=0
            local listfile="/etc/apt/sources.list"

            if [[ -f "$listfile" ]] && grep -qE '^\s*deb ' "$listfile"; then
                ((++LEGACY_COUNT))
            fi

            local list_files
            list_files=$(find /etc/apt/sources.list.d/ -type f -name "*.list" 2>/dev/null)
            if [[ -n "$list_files" ]]; then
                LEGACY_COUNT=$((LEGACY_COUNT + $(echo "$list_files" | wc -l)))
            fi

            if ((LEGACY_COUNT > 0)); then
                if [[ "$AUTO_MODE" == true ]]; then
                    info "Legacy sources uitschakelen..."
                    if [[ -f "$listfile" ]] && grep -qE '^\s*deb ' "$listfile"; then
                        cp "$listfile" "$listfile.bak" 2>/dev/null
                        sed -i '/^\s*deb /s/^/# Disabled by Proxmox Helper Script /' "$listfile" 2>/dev/null
                    fi
                    if [[ -n "$list_files" ]]; then
                        while IFS= read -r f; do
                            mv "$f" "$f.bak" 2>/dev/null
                        done <<<"$list_files"
                    fi
                    success "Legacy sources uitgeschakeld (backup: *.bak)"
                else
                    local MSG="Legacy APT sources found:\n"
                    [[ -f "$listfile" ]] && MSG+=" - /etc/apt/sources.list\n"
                    [[ -n "$list_files" ]] && MSG+="$(echo "$list_files" | sed 's|^| - |')\n"
                    MSG+="\nDo you want to disable (comment out/rename) all legacy sources and use ONLY deb822 .sources format?\n\nRecommended for Proxmox VE 9."

                    whiptail --backtitle "Proxmox VE Helper Scripts" --title "Disable legacy sources?" \
                        --yesno "$MSG" 18 80
                    if [[ $? -eq 0 ]]; then
                        info "Legacy sources uitschakelen..."
                        if [[ -f "$listfile" ]] && grep -qE '^\s*deb ' "$listfile"; then
                            cp "$listfile" "$listfile.bak" 2>/dev/null
                            sed -i '/^\s*deb /s/^/# Disabled by Proxmox Helper Script /' "$listfile" 2>/dev/null
                        fi
                        if [[ -n "$list_files" ]]; then
                            while IFS= read -r f; do
                                mv "$f" "$f.bak" 2>/dev/null
                            done <<<"$list_files"
                        fi
                        success "Legacy sources uitgeschakeld (backup: *.bak)"
                    else
                        msg_skip "Legacy sources behouden (kan APT warnings geven)"
                    fi
                fi
            fi
        }

        check_and_disable_legacy_sources

        # ──────────────────────────────────────────────────────────────────────
        # SUBSTAP: Migreer naar deb822 sources
        # ──────────────────────────────────────────────────────────────────────
        if [[ "$AUTO_MODE" == true ]]; then
            CHOICE="yes"
        else
            CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "SOURCES" --menu \
                "The package manager will use the correct sources to update and install packages on your Proxmox VE 9 server.\n\nMigrate to deb822 sources format?" 14 58 2 \
                "yes" " " \
                "no" " " 3>&2 2>&1 1>&3)
        fi

        case $CHOICE in
        yes)
            info "Proxmox VE Sources corrigeren (deb822)..."
            rm -f /etc/apt/sources.list.d/*.list 2>/dev/null || true
            sed -i '/proxmox/d;/bookworm/d' /etc/apt/sources.list 2>/dev/null || true

            cat >/etc/apt/sources.list.d/debian.sources <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie
Components: main contrib
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: trixie-security
Components: main contrib
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie-updates
Components: main contrib
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
            success "Proxmox VE 9 (Trixie) Sources gecorrigeerd"
            ;;
        no)
            msg_skip "Proxmox VE Sources niet gecorrigeerd"
            ;;
        esac
    fi

    # ──────────────────────────────────────────────────────────────────────
    # STAP 2: PVE-ENTERPRISE Repository
    # ──────────────────────────────────────────────────────────────────────
    if component_exists_in_sources "pve-enterprise"; then
        if [[ "$AUTO_MODE" == true ]]; then
            CHOICE="delete"
        else
            CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
                --title "PVE-ENTERPRISE" \
                --menu "'pve-enterprise' repository already exists.\n\nWhat do you want to do?" 14 58 3 \
                "keep" "Keep as is" \
                "disable" "Comment out (disable) this repo" \
                "delete" "Delete this repo file" \
                3>&2 2>&1 1>&3)
        fi

        case $CHOICE in
        keep)
            success "'pve-enterprise' repository behouden"
            ;;
        disable)
            info "'pve-enterprise' repository uitschakelen..."
            for file in /etc/apt/sources.list.d/*.sources; do
                if grep -q "Components:.*pve-enterprise" "$file" 2>/dev/null; then
                    if grep -q "^Enabled:" "$file"; then
                        sed -i 's/^Enabled:.*/Enabled: false/' "$file"
                    else
                        echo "Enabled: false" >>"$file"
                    fi
                fi
            done
            success "'pve-enterprise' repository uitgeschakeld"
            ;;
        delete)
            info "'pve-enterprise' repository verwijderen..."
            for file in /etc/apt/sources.list.d/*.sources; do
                if grep -q "Components:.*pve-enterprise" "$file" 2>/dev/null; then
                    rm -f "$file"
                fi
            done
            success "'pve-enterprise' repository verwijderd"
            ;;
        esac
    else
        if [[ "$AUTO_MODE" == true ]]; then
            msg_skip "'pve-enterprise' repository niet toegevoegd"
        else
            CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
                --title "PVE-ENTERPRISE" \
                --menu "The 'pve-enterprise' repository is only available to users who have purchased a Proxmox VE subscription.\n\nAdd 'pve-enterprise' repository (deb822)?" 14 58 2 \
                "no" " " \
                "yes" " " \
                --default-item "no" \
                3>&2 2>&1 1>&3)

            case $CHOICE in
            yes)
                info "'pve-enterprise' repository toevoegen..."
                cat >/etc/apt/sources.list.d/pve-enterprise.sources <<EOF
Types: deb
URIs: https://enterprise.proxmox.com/debian/pve
Suites: trixie
Components: pve-enterprise
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
                success "'pve-enterprise' repository toegevoegd"
                ;;
            no)
                msg_skip "'pve-enterprise' repository niet toegevoegd"
                ;;
            esac
        fi
    fi

    # ──────────────────────────────────────────────────────────────────────
    # STAP 3: CEPH-ENTERPRISE Repository
    # ──────────────────────────────────────────────────────────────────────
    if grep -q "enterprise.proxmox.com.*ceph" /etc/apt/sources.list.d/*.sources 2>/dev/null; then
        if [[ "$AUTO_MODE" == true ]]; then
            CHOICE="delete"
        else
            CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
                --title "CEPH-ENTERPRISE" \
                --menu "'ceph enterprise' repository already exists.\n\nWhat do you want to do?" 14 58 3 \
                "keep" "Keep as is" \
                "disable" "Comment out (disable) this repo" \
                "delete" "Delete this repo file" \
                3>&2 2>&1 1>&3)
        fi

        case $CHOICE in
        keep)
            success "'ceph enterprise' repository behouden"
            ;;
        disable)
            info "'ceph enterprise' repository uitschakelen..."
            for file in /etc/apt/sources.list.d/*.sources; do
                if grep -q "enterprise.proxmox.com.*ceph" "$file" 2>/dev/null; then
                    if grep -q "^Enabled:" "$file"; then
                        sed -i 's/^Enabled:.*/Enabled: false/' "$file"
                    else
                        echo "Enabled: false" >>"$file"
                    fi
                fi
            done
            success "'ceph enterprise' repository uitgeschakeld"
            ;;
        delete)
            info "'ceph enterprise' repository verwijderen..."
            for file in /etc/apt/sources.list.d/*.sources; do
                if grep -q "enterprise.proxmox.com.*ceph" "$file" 2>/dev/null; then
                    rm -f "$file"
                fi
            done
            success "'ceph enterprise' repository verwijderd"
            ;;
        esac
    fi

    # ──────────────────────────────────────────────────────────────────────
    # STAP 4: PVE-NO-SUBSCRIPTION Repository
    # ──────────────────────────────────────────────────────────────────────
    REPO_FILE=""
    REPO_ACTIVE=0
    REPO_COMMENTED=0
    for file in /etc/apt/sources.list.d/*.sources; do
        if grep -q "Components:.*pve-no-subscription" "$file" 2>/dev/null; then
            REPO_FILE="$file"
            if grep -E '^[^#]*Components:.*pve-no-subscription' "$file" >/dev/null 2>&1; then
                REPO_ACTIVE=1
            elif grep -E '^#.*Components:.*pve-no-subscription' "$file" >/dev/null 2>&1; then
                REPO_COMMENTED=1
            fi
            break
        fi
    done

    if [[ "$REPO_ACTIVE" -eq 1 ]]; then
        if [[ "$AUTO_MODE" == true ]]; then
            success "'pve-no-subscription' repository al actief"
        else
            CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
                --title "PVE-NO-SUBSCRIPTION" \
                --menu "'pve-no-subscription' repository is currently ENABLED.\n\nWhat do you want to do?" 14 58 3 \
                "keep" "Keep as is" \
                "disable" "Comment out (disable)" \
                "delete" "Delete repo file" \
                3>&2 2>&1 1>&3)

            case $CHOICE in
            keep)
                success "'pve-no-subscription' repository behouden"
                ;;
            disable)
                info "'pve-no-subscription' repository uitschakelen..."
                sed -i '/^\s*Types:/,/^$/s/^\([^#].*\)$/# \1/' "$REPO_FILE"
                success "'pve-no-subscription' repository uitgeschakeld"
                ;;
            delete)
                info "'pve-no-subscription' repository verwijderen..."
                rm -f "$REPO_FILE"
                success "'pve-no-subscription' repository verwijderd"
                ;;
            esac
        fi

    elif [[ "$REPO_COMMENTED" -eq 1 ]]; then
        if [[ "$AUTO_MODE" == true ]]; then
            info "'pve-no-subscription' repository activeren..."
            sed -i '/^#\s*Types:/,/^$/s/^#\s*//' "$REPO_FILE"
            success "'pve-no-subscription' repository geactiveerd"
        else
            CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
                --title "PVE-NO-SUBSCRIPTION" \
                --menu "'pve-no-subscription' repository is currently DISABLED (commented out).\n\nWhat do you want to do?" 14 58 3 \
                "enable" "Uncomment (enable)" \
                "keep" "Keep disabled" \
                "delete" "Delete repo file" \
                3>&2 2>&1 1>&3)

            case $CHOICE in
            enable)
                info "'pve-no-subscription' repository activeren..."
                sed -i '/^#\s*Types:/,/^$/s/^#\s*//' "$REPO_FILE"
                success "'pve-no-subscription' repository geactiveerd"
                ;;
            keep)
                msg_skip "'pve-no-subscription' repository uitgeschakeld gehouden"
                ;;
            delete)
                info "'pve-no-subscription' repository verwijderen..."
                rm -f "$REPO_FILE"
                success "'pve-no-subscription' repository verwijderd"
                ;;
            esac
        fi
    else
        if [[ "$AUTO_MODE" == true ]]; then
            CHOICE="yes"
        else
            CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "PVE-NO-SUBSCRIPTION" \
                --menu "The 'pve-no-subscription' repository provides access to all of the open-source components of Proxmox VE.\n\nAdd 'pve-no-subscription' repository (deb822)?" 14 58 2 \
                "yes" " " \
                "no" " " 3>&2 2>&1 1>&3)
        fi

        case $CHOICE in
        yes)
            info "'pve-no-subscription' repository toevoegen..."
            cat >/etc/apt/sources.list.d/proxmox.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
            success "'pve-no-subscription' repository toegevoegd"
            ;;
        no)
            msg_skip "'pve-no-subscription' repository niet toegevoegd"
            ;;
        esac
    fi

    # ──────────────────────────────────────────────────────────────────────
    # STAP 5: CEPH Package Repositories
    # ──────────────────────────────────────────────────────────────────────
    if component_exists_in_sources "no-subscription"; then
        success "'ceph' package repository (no-subscription) al aanwezig"
    else
        if [[ "$AUTO_MODE" == true ]]; then
            CHOICE="yes"
        else
            CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CEPH PACKAGE REPOSITORIES" \
                --menu "The 'Ceph Package Repositories' provides access to both the 'no-subscription' and 'enterprise' repositories (deb822).\n\nAdd 'ceph package sources?" 14 58 2 \
                "yes" " " \
                "no" " " 3>&2 2>&1 1>&3)
        fi

        case $CHOICE in
        yes)
            info "'ceph package repositories' toevoegen..."
            cat >/etc/apt/sources.list.d/ceph.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/ceph-squid
Suites: trixie
Components: no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
            success "'ceph package repositories' toegevoegd"
            ;;
        no)
            msg_skip "'ceph package repositories' niet toegevoegd"
            for file in /etc/apt/sources.list.d/*.sources; do
                if grep -q "enterprise.proxmox.com.*ceph" "$file" 2>/dev/null; then
                    if grep -q "^Enabled:" "$file"; then
                        sed -i 's/^Enabled:.*/Enabled: false/' "$file" 2>/dev/null
                    else
                        echo "Enabled: false" >>"$file" 2>/dev/null
                    fi
                fi
            done
            find /etc/apt/sources.list.d/ -type f -name "*.list" \
                -exec sed -i '/enterprise.proxmox.com.*ceph/s/^/# /' {} \; 2>/dev/null || true
            ;;
        esac
    fi

    # ──────────────────────────────────────────────────────────────────────
    # STAP 6: PVETEST Repository
    # ──────────────────────────────────────────────────────────────────────
    if component_exists_in_sources "pve-test"; then
        success "'pve-test' repository al aanwezig"
    else
        if [[ "$AUTO_MODE" == true ]]; then
            msg_skip "'pve-test' repository niet toegevoegd (niet aanbevolen voor productie)"
        else
            CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "PVETEST" \
                --menu "The 'pve-test' repository can give advanced users access to new features and updates before they are officially released.\n\nAdd (Disabled) 'pvetest' repository (deb822)?" 14 58 2 \
                "yes" " " \
                "no" " " 3>&2 2>&1 1>&3)

            case $CHOICE in
            yes)
                info "'pve-test' repository toevoegen (uitgeschakeld)..."
                cat >/etc/apt/sources.list.d/pve-test.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-test
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
Enabled: false
EOF
                success "'pve-test' repository toegevoegd (uitgeschakeld)"
                ;;
            no)
                msg_skip "'pve-test' repository niet toegevoegd"
                ;;
            esac
        fi
    fi

    post_routines_common
}

# ============================================================================
# GEMEENSCHAPPELIJKE POST-INSTALL ROUTINES
# ============================================================================

post_routines_common() {
    echo ""
    echo -e "  ${PURPLE_90}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${PURPLE_90}  Post-Install Configuratie${NC}"
    echo -e "  ${PURPLE_90}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # ──────────────────────────────────────────────────────────────────────
    # STAP 7: Subscription Nag
    # ──────────────────────────────────────────────────────────────────────
    if [[ "$AUTO_MODE" == true ]]; then
        CHOICE="yes"
    else
        CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "SUBSCRIPTION NAG" --menu "This will disable the nag message reminding you to purchase a subscription every time you log in to the web interface.\n \nDisable subscription nag?" 14 58 2 \
            "yes" " " \
            "no" " " 3>&2 2>&1 1>&3)
    fi

    case $CHOICE in
    yes)
        if [[ "$AUTO_MODE" == false ]]; then
            whiptail --backtitle "Proxmox VE Helper Scripts" --msgbox --title "Support Subscriptions" "Supporting the software's development team is essential. Check their official website's Support Subscriptions for pricing. Without their dedicated work, we wouldn't have this exceptional software." 10 58
        fi

        info "Subscription nag uitschakelen..."
        mkdir -p /usr/local/bin
        cat >/usr/local/bin/pve-remove-nag.sh <<'EOF'
#!/bin/sh
WEB_JS=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
if [ -s "$WEB_JS" ] && ! grep -q NoMoreNagging "$WEB_JS"; then
    echo "Patching Web UI nag..."
    sed -i -e "/data\.status/ s/!//" -e "/data\.status/ s/active/NoMoreNagging/" "$WEB_JS"
fi

MOBILE_TPL=/usr/share/pve-yew-mobile-gui/index.html.tpl
MARKER="<!-- MANAGED BLOCK FOR MOBILE NAG -->"
if [ -f "$MOBILE_TPL" ] && ! grep -q "$MARKER" "$MOBILE_TPL"; then
    echo "Patching Mobile UI nag..."
    printf "%s\n" \
      "$MARKER" \
      "<script>" \
      "  function removeSubscriptionElements() {" \
      "    const dialogs = document.querySelectorAll('dialog.pwt-outer-dialog');" \
      "    dialogs.forEach(dialog => {" \
      "      const text = (dialog.textContent || '').toLowerCase();" \
      "      if (text.includes('subscription')) {" \
      "        dialog.remove();" \
      "        console.log('Removed subscription dialog');" \
      "      }" \
      "    });" \
      "    const cards = document.querySelectorAll('.pwt-card.pwt-p-2.pwt-d-flex.pwt-interactive.pwt-justify-content-center');" \
      "    cards.forEach(card => {" \
      "      const text = (card.textContent || '').toLowerCase();" \
      "      const hasButton = card.querySelector('button');" \
      "      if (!hasButton && text.includes('subscription')) {" \
      "        card.remove();" \
      "        console.log('Removed subscription card');" \
      "      }" \
      "    });" \
      "  }" \
      "  const observer = new MutationObserver(removeSubscriptionElements);" \
      "  observer.observe(document.body, { childList: true, subtree: true });" \
      "  removeSubscriptionElements();" \
      "  setInterval(removeSubscriptionElements, 300);" \
      "  setTimeout(() => {observer.disconnect();}, 10000);" \
      "</script>" \
      "" >> "$MOBILE_TPL"
fi
EOF
        chmod 755 /usr/local/bin/pve-remove-nag.sh

        cat >/etc/apt/apt.conf.d/no-nag-script <<'EOF'
DPkg::Post-Invoke { "/usr/local/bin/pve-remove-nag.sh"; };
EOF
        chmod 644 /etc/apt/apt.conf.d/no-nag-script
        success "Subscription nag uitgeschakeld (leeg browser cache)"
        ;;
    no)
        if [[ "$AUTO_MODE" == false ]]; then
            whiptail --backtitle "Proxmox VE Helper Scripts" --msgbox --title "Support Subscriptions" "Supporting the software's development team is essential. Check their official website's Support Subscriptions for pricing. Without their dedicated work, we wouldn't have this exceptional software." 10 58
        fi
        msg_skip "Subscription nag niet uitgeschakeld"
        [[ -f /etc/apt/apt.conf.d/no-nag-script ]] && rm /etc/apt/apt.conf.d/no-nag-script 2>/dev/null
        ;;
    esac

    apt --reinstall install proxmox-widget-toolkit &>/dev/null || msg_skip "Widget toolkit herinstallatie overgeslagen"

    # ──────────────────────────────────────────────────────────────────────
    # STAP 8 & 9: High Availability
    # ──────────────────────────────────────────────────────────────────────
    if ! systemctl is-active --quiet pve-ha-lrm; then
        if [[ "$AUTO_MODE" == true ]]; then
            msg_skip "High availability niet ingeschakeld (single node setup)"
        else
            CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "HIGH AVAILABILITY" --menu "Enable high availability?" 10 58 2 \
                "yes" " " \
                "no" " " 3>&2 2>&1 1>&3)

            case $CHOICE in
            yes)
                info "High availability inschakelen..."
                systemctl enable -q --now pve-ha-lrm 2>/dev/null
                systemctl enable -q --now pve-ha-crm 2>/dev/null
                systemctl enable -q --now corosync 2>/dev/null
                success "High availability ingeschakeld"
                ;;
            no)
                msg_skip "High availability niet ingeschakeld"
                ;;
            esac
        fi
    fi

    if systemctl is-active --quiet pve-ha-lrm; then
        if [[ "$AUTO_MODE" == true ]]; then
            CHOICE="yes"
        else
            CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "HIGH AVAILABILITY" --menu "If you plan to utilize a single node instead of a clustered environment, you can disable unnecessary high availability (HA) services, thus reclaiming system resources.\n\nIf HA becomes necessary at a later stage, the services can be re-enabled.\n\nDisable high availability?" 18 58 2 \
                "yes" " " \
                "no" " " 3>&2 2>&1 1>&3)
        fi

        case $CHOICE in
        yes)
            info "High availability uitschakelen..."
            systemctl disable -q --now pve-ha-lrm 2>/dev/null
            systemctl disable -q --now pve-ha-crm 2>/dev/null
            success "High availability uitgeschakeld"

            # STAP 10: Corosync
            if [[ "$AUTO_MODE" == true ]]; then
                CHOICE2="yes"
            else
                CHOICE2=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "COROSYNC" --menu "Disable Corosync for a Proxmox VE Cluster?" 10 58 2 \
                    "yes" " " \
                    "no" " " 3>&2 2>&1 1>&3)
            fi

            case $CHOICE2 in
            yes)
                info "Corosync uitschakelen..."
                systemctl disable -q --now corosync 2>/dev/null
                success "Corosync uitgeschakeld"
                ;;
            no)
                msg_skip "Corosync niet uitgeschakeld"
                ;;
            esac
            ;;
        no)
            msg_skip "High availability niet uitgeschakeld"
            ;;
        esac
    fi

    # ──────────────────────────────────────────────────────────────────────
    # STAP 11: Update Proxmox VE
    # ──────────────────────────────────────────────────────────────────────
    if [[ "$AUTO_MODE" == true ]]; then
        CHOICE="yes"
    else
        CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "UPDATE" --menu "\nUpdate Proxmox VE now?" 11 58 2 \
            "yes" " " \
            "no" " " 3>&2 2>&1 1>&3)
    fi

    case $CHOICE in
    yes)
        info "Proxmox VE updaten (even geduld)..."
        if apt update &>/dev/null && apt -y dist-upgrade &>/dev/null; then
            success "Proxmox VE geüpdatet"
        else
            fail "Proxmox VE update mislukt"
        fi
        ;;
    no)
        msg_skip "Proxmox VE niet geüpdatet"
        ;;
    esac

    # ──────────────────────────────────────────────────────────────────────
    # Belangrijke melding
    # ──────────────────────────────────────────────────────────────────────
    echo ""
    echo -e "  ${PURPLE_90}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${YELLOW_90}  BELANGRIJKE MELDING${NC}"
    echo -e "  ${PURPLE_90}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    printf "    ${GREEN_90}✓${NC} Bij cluster met meerdere nodes: voer dit script uit op ELKE node\n"
    printf "    ${GREEN_90}✓${NC} Na de upgrade: HERSTART wordt sterk aanbevolen\n"
    printf "    ${GREEN_90}✓${NC} Leeg je browser cache (Ctrl+Shift+R) na herstart\n"
    echo ""

    if [[ "$AUTO_MODE" == false ]]; then
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "Post-Install Reminder" --msgbox \
            "IMPORTANT:

If you have multiple Proxmox VE hosts in a cluster, please make sure to run this script on every node individually.

After completing these steps, it is strongly recommended to REBOOT your node.

After the upgrade or post-install routines, always clear your browser cache or perform a hard reload (Ctrl+Shift+R) before using the Proxmox VE Web UI to avoid UI display issues.
" 20 80
    fi

    # ──────────────────────────────────────────────────────────────────────
    # STAP 12: Reboot
    # ──────────────────────────────────────────────────────────────────────
    if [[ "$AUTO_MODE" == true ]]; then
        CHOICE="yes"
    else
        CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "REBOOT" --menu "\nReboot Proxmox VE now? (recommended)" 11 58 2 \
            "yes" " " \
            "no" " " 3>&2 2>&1 1>&3)
    fi

    case $CHOICE in
    yes)
        echo ""
        info "Systeem herstarten..."
        sleep 2
        success "Post Install Routines voltooid - systeem herstart..."
        sleep 1
        reboot
        ;;
    no)
        echo ""
        msg_skip "Systeem niet herstart (herstart aanbevolen!)"
        echo ""
        success "Post Install Routines voltooid"
        echo ""
        ;;
    esac
}

# ============================================================================
# START SCRIPT
# ============================================================================

main