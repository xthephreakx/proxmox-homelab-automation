#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Source shared library
# ==============================
LIB_FILE="/opt/vmconfigs/lib.sh"
if [[ ! -f "$LIB_FILE" ]]; then
    echo "ERROR: $LIB_FILE not found. Run proxmox-setup-vms.sh first."
    exit 1
fi
source "$LIB_FILE"

# Extra kleur voor titles (niet in lib.sh)
BLUE_90='\033[38;2;0;48;255m'       # 0030ff

title() { echo -e "  ${BLUE_90}>>${NC} $1"; }

# Functie voor ja/nee vragen
ask_yes_no() {
    local prompt="$1"
    local answer

    while true; do
        read -p "$prompt" answer
        case "${answer,,}" in
            ja|j|yes|y) return 0 ;;
            nee|n|no)   return 1 ;;
            *) echo "Ongeldige keuze. Typ: ja/j/y of nee/n" ;;
        esac
    done
}


echo -e "${MAGENTA_90}░░░░░░░░░░░█▀█░█▀▄░█▀█░█░█░█▄█░█▀█░█░█░░░█░█░█▄█░░░░░░░░░░░░${NC}"
echo -e "${MAGENTA_90}░░░░░░░░░░░█▀▀░█▀▄░█░█░▄▀▄░█░█░█░█░▄▀▄░░░▀▄▀░█░█░░░░░░░░░░░░${NC}"
echo -e "${MAGENTA_90}░░░░░░░░░░░▀░░░▀░▀░▀▀▀░▀░▀░▀░▀░▀▀▀░▀░▀░░░░▀░░▀░▀░░░░░░░░░░░░${NC}"
echo -e "${MAGENTA_90}░░░█▀▀░█░░░█▀▀░█▀█░█▀█░█░█░█▀█░░░█▀▀░█▀▀░█▀▄░▀█▀░█▀█░▀█▀░░░░${NC}"
echo -e "${MAGENTA_90}░░░█░░░█░░░█▀▀░█▀█░█░█░█░█░█▀▀░░░▀▀█░█░░░█▀▄░░█░░█▀▀░░█░░░░░${NC}"
echo -e "${MAGENTA_90}░░░▀▀▀░▀▀▀░▀▀▀░▀░▀░▀░▀░▀▀▀░▀░░░░░▀▀▀░▀▀▀░▀░▀░▀▀▀░▀░░░░▀░░░░░${NC}"
echo ""
warn "Dit script beheert/verwijdert alleen VM's:"
echo "  - eps-* VM's (alles of selectief)"
echo "  - Template VM 9000 (optioneel)"
echo ""

if ! ask_yes_no "Weet je het zeker? (ja/nee): "; then
    echo "Geannuleerd."
    exit 0
fi

echo ""
title "VM's beheren (eps-*)"
echo ""

# Maak arrays van VMID, naam en status
mapfile -t VM_IDS    < <(qm list | grep -E "eps-[0-9]+-[0-9]+" | awk '{print $1}')
mapfile -t VM_NAMES  < <(qm list | grep -E "eps-[0-9]+-[0-9]+" | awk '{print $2}')
mapfile -t VM_STATUS < <(qm list | grep -E "eps-[0-9]+-[0-9]+" | awk '{print $3}')

if [[ ${#VM_IDS[@]} -gt 0 ]]; then
    echo ""
    echo "Gevonden VMs:"
    echo "┌──────┬────────────────────────────────────────────────────┬──────────┐"
    echo "│ VMID │ Naam                                               │ Status   │"
    echo "├──────┼────────────────────────────────────────────────────┼──────────┤"

    for i in "${!VM_IDS[@]}"; do
        VMID="${VM_IDS[$i]}"
        VM_NAME="${VM_NAMES[$i]}"
        STATUS="${VM_STATUS[$i]}"

        # Kap naam af als langer dan 50 karakters
        if [[ ${#VM_NAME} -gt 50 ]]; then
            VM_NAME_DISPLAY="${VM_NAME:0:47}..."
        else
            VM_NAME_DISPLAY="$VM_NAME"
        fi

        printf "│ %-4s │ %-50s │ %-8s │\n" "$VMID" "$VM_NAME_DISPLAY" "$STATUS"
    done

    echo "└──────┴────────────────────────────────────────────────────┴──────────┘"
    echo ""

    read -p "Wil je VMs verwijderen? (ja/nee/selectief): " vm_choice

    case "${vm_choice,,}" in
        ja|j|yes|y)
            echo ""
            for i in "${!VM_IDS[@]}"; do
                VMID="${VM_IDS[$i]}"
                VM_NAME="${VM_NAMES[$i]}"
                safe_stop_vm "$VMID" "$VM_NAME"
                info "Verwijderen VM $VMID ($VM_NAME)..."
                qm destroy "$VMID" --purge >/dev/null 2>&1 || true
                success "VM $VMID verwijderd"
            done
            ;;

        selectief|s)
            echo ""
            for i in "${!VM_IDS[@]}"; do
                VMID="${VM_IDS[$i]}"
                VM_NAME="${VM_NAMES[$i]}"

                # Display (afgekapt) + vraag met volledige naam
                if [[ ${#VM_NAME} -gt 50 ]]; then
                    VM_NAME_DISPLAY="${VM_NAME:0:47}..."
                else
                    VM_NAME_DISPLAY="$VM_NAME"
                fi

                echo "┌──────┬────────────────────────────────────────────────────┐"
                echo "│ VMID │ Naam                                               │"
                echo "├──────┼────────────────────────────────────────────────────┤"
                printf "│ %-4s │ %-50s │\n" "$VMID" "$VM_NAME_DISPLAY"
                echo "└──────┴────────────────────────────────────────────────────┘"

                if ask_yes_no "VM $VMID ($VM_NAME) verwijderen? (ja/nee): "; then
                    safe_stop_vm "$VMID" "$VM_NAME"
                    info "Verwijderen VM $VMID..."
                    qm destroy "$VMID" --purge >/dev/null 2>&1 || true
                    success "VM $VMID verwijderd"
                else
                    success "VM $VMID behouden"
                fi
                echo ""
            done
            ;;

        *)
            success "Alle VMs behouden"
            ;;
    esac
else
    warn "Geen eps-* VMs gevonden"
fi

echo ""
title "Template VM 9000 (optioneel)"
echo ""

if qm status 9000 &>/dev/null; then
    echo "  Template VM 9000 gevonden"
    echo ""
    if ask_yes_no "  Template VM 9000 verwijderen? (ja/nee): "; then
        info "Verwijderen template VM 9000..."
        qm destroy 9000 --purge >/dev/null 2>&1 || true
        success "Template VM 9000 verwijderd"
    else
        success "Template VM 9000 behouden"
    fi
else
    warn "Template VM 9000 niet gevonden, overslaan"
fi

echo ""
success "VM cleanup voltooid!"
echo ""
