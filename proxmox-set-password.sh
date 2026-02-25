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

# ==============================
# Load default VM user
# ==============================
DEFAULTS_FILE="/opt/vmconfigs/defaults.conf"
VM_USER="pasta"
if [[ -f "$DEFAULTS_FILE" ]]; then
    source "$DEFAULTS_FILE"
fi

# ==============================
# Build list of running eps-* VMs
# ==============================
echo ""
echo -e "${MAGENTA_90}  Set VM Password${NC}"
echo ""

mapfile -t VM_IDS    < <(qm list | grep -E "eps-[0-9]+-[0-9]+" | awk '$3 == "running" {print $1}')
mapfile -t VM_NAMES  < <(qm list | grep -E "eps-[0-9]+-[0-9]+" | awk '$3 == "running" {print $2}')

if [[ ${#VM_IDS[@]} -eq 0 ]]; then
    warn "No running eps-* VMs found."
    echo ""
    echo -e "  ${YELLOW_90}Only running VMs can receive a password — start the VM first.${NC}"
    echo ""
    exit 0
fi

# ==============================
# Display VM table
# ==============================
echo "  Running VMs:"
echo ""
echo "  ┌──────┬────────────────────────────────────────────────────┐"
echo "  │ VMID │ Name                                               │"
echo "  ├──────┼────────────────────────────────────────────────────┤"

for i in "${!VM_IDS[@]}"; do
    VMID="${VM_IDS[$i]}"
    VM_NAME="${VM_NAMES[$i]}"
    if [[ ${#VM_NAME} -gt 50 ]]; then
        VM_NAME="${VM_NAME:0:47}..."
    fi
    printf "  │ %-4s │ %-50s │\n" "$VMID" "$VM_NAME"
done

echo "  └──────┴────────────────────────────────────────────────────┘"
echo ""

# ==============================
# Select VM
# ==============================
read -rp "  Enter VMID: " SELECTED_VMID

# Validate selection
VALID=false
for id in "${VM_IDS[@]}"; do
    if [[ "$id" == "$SELECTED_VMID" ]]; then
        VALID=true
        break
    fi
done

if [[ "$VALID" != true ]]; then
    error "Invalid VMID: $SELECTED_VMID"
fi

# Get VM name for display
SELECTED_NAME=""
for i in "${!VM_IDS[@]}"; do
    if [[ "${VM_IDS[$i]}" == "$SELECTED_VMID" ]]; then
        SELECTED_NAME="${VM_NAMES[$i]}"
        break
    fi
done

echo ""
echo -e "  ${GREEN_90}✓${NC} Selected: $SELECTED_VMID ($SELECTED_NAME)"
echo -e "  ${YELLOW_90}User: ${VM_USER}${NC}"
echo ""

# ==============================
# Check guest agent is reachable
# ==============================
info "Checking guest agent..."
if ! qm guest exec "$SELECTED_VMID" -- echo "ok" &>/dev/null; then
    echo ""
    error "Guest agent not responding on VM $SELECTED_VMID. Make sure the VM is fully booted."
fi
success "Guest agent OK"

# Get VM IP via guest agent
VM_IP=$(qm guest cmd "$SELECTED_VMID" network-get-interfaces 2>/dev/null | \
    jq -r '.[] | select(.name != "lo") | .["ip-addresses"][]? | select(.["ip-address-type"] == "ipv4") | .["ip-address"]' \
    2>/dev/null | grep -Ev '^(127\.|169\.254\.)' | head -n1 || true)
VM_IP="${VM_IP:-<unknown>}"

# ==============================
# Ask for new password (twice)
# ==============================
echo ""
while true; do
    read -rsp "  New password: " PASSWORD1
    echo ""
    read -rsp "  Confirm password: " PASSWORD2
    echo ""

    if [[ "$PASSWORD1" != "$PASSWORD2" ]]; then
        warn "Passwords do not match. Try again."
        echo ""
    elif [[ -z "$PASSWORD1" ]]; then
        warn "Password cannot be empty. Try again."
        echo ""
    else
        break
    fi
done

# ==============================
# Set password via guest agent
# ==============================
echo ""
info "Setting password for user '${VM_USER}' on VM $SELECTED_VMID..."

if ! qm guest exec "$SELECTED_VMID" -- bash -c \
    "echo '${VM_USER}:${PASSWORD1}' | chpasswd" &>/dev/null; then
    error "Failed to set password on VM $SELECTED_VMID."
fi

success "Password set successfully."

# ==============================
# Optionally enable SSH password auth
# ==============================
echo ""
echo -e "  ${YELLOW_90}⚠  SSH password authentication is currently disabled by default.${NC}"
echo -e "  ${YELLOW_90}   Enabling it allows login without an SSH key, but reduces security.${NC}"
echo ""
read -rp "  Enable SSH password authentication? [y/N] " ENABLE_SSH

if [[ "${ENABLE_SSH,,}" == "y" ]]; then
    info "Enabling SSH password authentication..."

    qm guest exec "$SELECTED_VMID" -- bash -c \
        "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
         sed -i 's/^#*KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config && \
         systemctl restart ssh" &>/dev/null

    success "SSH password authentication enabled."
    echo ""
    echo -e "  ${GREEN_90}You can now log in with:${NC}"
    echo -e "  ${GREEN_90}  ssh ${VM_USER}@${VM_IP}${NC}"
else
    echo ""
    echo -e "  ${YELLOW_90}!${NC} SSH password authentication left unchanged."
    echo ""
    echo -e "  ${YELLOW_90}You can still use the password for sudo inside the VM.${NC}"
fi

echo ""
