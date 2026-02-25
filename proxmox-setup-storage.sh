#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Kleuren (90's palette)
# ==============================
MAGENTA_90='\033[38;2;255;0;124m'   # ff007c
GREEN_90='\033[38;2;0;254;162m'     # 00fea2
PURPLE_90='\033[38;2;144;76;254m'   # 904cfe
YELLOW_90='\033[38;2;249;186;4m'    # f9ba04
RED_90='\033[38;2;255;0;54m'        # ff0036
BLUE_90='\033[38;2;0;48;255m'       # 0030ff
NC='\033[0m'

# ==============================
# Spinner & Status functies
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

trap '[[ -n "${SPINNER_PID:-}" ]] && kill "$SPINNER_PID" 2>/dev/null || true; tput cnorm 2>/dev/null || true' EXIT INT TERM

# ==============================
# Banner
# ==============================
echo -e "${MAGENTA_90}░░░░░░░░░░░░░░░░░░░█▀▀░█▀▀░▀█▀░█░█░█▀█░░░░░░░░░░░░░░░░░░░░░░${NC}"
echo -e "${MAGENTA_90}░░░░░░░░░░░░░░░░░░░▀▀█░█▀▀░░█░░█░█░█▀▀░░░░░░░░░░░░░░░░░░░░░░${NC}"
echo -e "${MAGENTA_90}░░░░░░░░░░░░░░░░░░░▀▀▀░▀▀▀░░▀░░▀▀▀░▀░░░░░░░░░░░░░░░░░░░░░░░░${NC}"
echo -e "${MAGENTA_90}░░░█▀▄░█▀█░█▀▀░█░█░█▀▀░█▀▄░░░█▀▀░▀█▀░█▀█░█▀▄░█▀█░█▀▀░█▀▀░░░░${NC}"
echo -e "${MAGENTA_90}░░░█░█░█░█░█░░░█▀▄░█▀▀░█▀▄░░░▀▀█░░█░░█░█░█▀▄░█▀█░█░█░█▀▀░░░░${NC}"
echo -e "${MAGENTA_90}░░░▀▀░░▀▀▀░▀▀▀░▀░▀░▀▀▀░▀░▀░░░▀▀▀░░▀░░▀▀▀░▀░▀░▀░▀░▀▀▀░▀▀▀░░░░${NC}"
echo ""

# ==============================
# Variabelen
# ==============================
MOUNT_POINT="/mnt/docker-storage"
STORAGE_LABEL="docker-storage"
PROXMOX_STORAGE_NAME="docker-storage"
DEFAULTS_FILE="/opt/vmconfigs/defaults.conf"

# ==============================
# Safety checks (pre-selectie)
# ==============================

# Check of we root zijn
if [[ $EUID -ne 0 ]]; then
   fail "Dit script moet als root uitgevoerd worden (of met sudo)"
fi

# ==============================
# Disk selectie
# ==============================

# Laad opgeslagen default als die bestaat
DISK_DEVICE=""
if [[ -f "$DEFAULTS_FILE" ]]; then
    source "$DEFAULTS_FILE"
fi

# Bouw arrays van beschikbare disks
mapfile -t DISK_NAMES  < <(lsblk -d -o NAME  --noheadings)
mapfile -t DISK_SIZES  < <(lsblk -d -o SIZE  --noheadings)
mapfile -t DISK_MODELS < <(lsblk -d -o MODEL --noheadings | sed 's/[[:space:]]*$//')

echo ""
echo -e "  ${MAGENTA_90}Beschikbare disks:${NC}"
echo ""
for i in "${!DISK_NAMES[@]}"; do
    num=$((i + 1))
    echo -e "  ${GREEN_90}[${num}]${NC}  ${YELLOW_90}/dev/${DISK_NAMES[$i]}${NC}  ${DISK_SIZES[$i]}  ${DISK_MODELS[$i]}"
done
echo ""

# Bepaal default index op basis van opgeslagen DISK_DEVICE (of 1 als niets opgeslagen)
DEFAULT_IDX=1
for i in "${!DISK_NAMES[@]}"; do
    if [[ "/dev/${DISK_NAMES[$i]}" == "$DISK_DEVICE" ]]; then
        DEFAULT_IDX=$((i + 1))
        break
    fi
done

if [[ -n "$DISK_DEVICE" ]]; then
    echo -e "  ${YELLOW_90}Opgeslagen keuze: [${DEFAULT_IDX}] /dev/${DISK_NAMES[$((DEFAULT_IDX - 1))]} — druk Enter om te bevestigen${NC}"
else
    echo -e "  ${YELLOW_90}Standaard: [1] /dev/${DISK_NAMES[0]} — druk Enter om te bevestigen${NC}"
fi

read -rp "  Keuze [1-${#DISK_NAMES[@]}]: " INPUT_IDX
INPUT_IDX="${INPUT_IDX:-$DEFAULT_IDX}"

# Valideer keuze
if ! [[ "$INPUT_IDX" =~ ^[0-9]+$ ]] || (( INPUT_IDX < 1 || INPUT_IDX > ${#DISK_NAMES[@]} )); then
    fail "Ongeldige keuze: ${INPUT_IDX} (kies een getal tussen 1 en ${#DISK_NAMES[@]})"
fi

DISK_DEVICE="/dev/${DISK_NAMES[$((INPUT_IDX - 1))]}"

# Sla keuze op in defaults.conf
mkdir -p /opt/vmconfigs
if grep -q "^DISK_DEVICE=" "$DEFAULTS_FILE" 2>/dev/null; then
    sed -i "s|^DISK_DEVICE=.*|DISK_DEVICE=\"${DISK_DEVICE}\"|" "$DEFAULTS_FILE"
else
    echo "DISK_DEVICE=\"${DISK_DEVICE}\"" >> "$DEFAULTS_FILE"
fi

PARTITION="${DISK_DEVICE}1"

info "Uitvoeren safety checks..."

# Check of disk bestaat
if [[ ! -b "$DISK_DEVICE" ]]; then
    fail "Disk $DISK_DEVICE niet gevonden!"
fi

# Disk info tonen
DISK_SIZE=$(lsblk -b -d -n -o SIZE "$DISK_DEVICE" | awk '{printf "%.1f GB", $1/1024/1024/1024}')
DISK_MODEL=$(lsblk -d -n -o MODEL "$DISK_DEVICE" | xargs)
success "Safety checks OK"

echo ""
warn "═══════════════════════════════════════════════════════════"
warn "LET OP: Deze disk wordt GEWIST!"
warn "═══════════════════════════════════════════════════════════"
echo ""
echo -e "  ${YELLOW_90}Disk:${NC}  $DISK_DEVICE"
echo -e "  ${YELLOW_90}Model:${NC} $DISK_MODEL"
echo -e "  ${YELLOW_90}Size:${NC}  $DISK_SIZE"
echo ""

# Check of disk al gemount is
if mount | grep -q "^$DISK_DEVICE"; then
    MOUNT_LOCATION=$(mount | grep "^$DISK_DEVICE" | awk '{print $3}')
    warn "Disk $DISK_DEVICE is al gemount op: $MOUNT_LOCATION"
    echo ""
    read -rp "  Wil je de disk unmounten en opnieuw formatteren? (j/N): " UNMOUNT_CONFIRM
    if [[ "${UNMOUNT_CONFIRM,,}" == "j" ]]; then
        info "Disk unmounten..."
        # Verwijder Proxmox storage entry als die bestaat
        if pvesm status 2>/dev/null | grep -q "^$PROXMOX_STORAGE_NAME"; then
            pvesm remove "$PROXMOX_STORAGE_NAME" 2>/dev/null || true
        fi
        # Verwijder fstab entry
        sed -i "/LABEL=$STORAGE_LABEL/d" /etc/fstab
        # Unmount
        umount -l "$MOUNT_LOCATION" 2>/dev/null || fail "Unmounten mislukt — controleer of er processen actief zijn op $MOUNT_LOCATION"
        success "Disk geunmount"
    else
        fail "Geannuleerd — unmount eerst de disk: umount $MOUNT_LOCATION"
    fi
fi

# Check of disk partities heeft die in gebruik zijn
if lsblk "$DISK_DEVICE" -o MOUNTPOINT | grep -v "MOUNTPOINT" | grep -q "/"; then
    warn "Er zijn partities op deze disk die in gebruik zijn!"
    lsblk "$DISK_DEVICE"
    read -rp "  Wil je alle partities forceren te unmounten? (j/N): " FORCE_CONFIRM
    if [[ "${FORCE_CONFIRM,,}" == "j" ]]; then
        info "Partities unmounten..."
        while read -r mp; do
            umount -l "$mp" 2>/dev/null || true
        done < <(lsblk "$DISK_DEVICE" -o MOUNTPOINT --noheadings | grep "/")
        success "Partities geunmount"
    else
        fail "Geannuleerd — unmount alle partities eerst"
    fi
fi

# Laatste bevestiging
echo ""
read -p "Weet je ZEKER dat je deze disk wilt formatteren? Alle data gaat verloren! (typ 'YES' om door te gaan): " CONFIRM

if [[ "$CONFIRM" != "YES" ]]; then
    fail "Geannuleerd door gebruiker"
fi

echo ""

# ==============================
# Disk voorbereiden
# ==============================
info "Wissen bestaande partition table..."
wipefs -a "$DISK_DEVICE" 2>/dev/null || true
dd if=/dev/zero of="$DISK_DEVICE" bs=1M count=100 2>/dev/null || true
success "Disk gewist"

info "Nieuwe partition aanmaken..."
(
echo o      # Nieuwe DOS partition table
echo n      # Nieuwe partition
echo p      # Primary
echo 1      # Partition nummer 1
echo        # Default - eerste sector
echo        # Default - laatste sector (gebruik hele disk)
echo w      # Write changes
) | fdisk "$DISK_DEVICE" >/dev/null 2>&1 || true

# Wacht even tot kernel de partition herkent
sleep 2
partprobe "$DISK_DEVICE" 2>/dev/null || true
sleep 2

success "Partition aangemaakt: $PARTITION"

# ==============================
# Formatteren
# ==============================
info "Formatteren met ext4 filesystem..."
mkfs.ext4 -F -L "$STORAGE_LABEL" "$PARTITION" >/dev/null 2>&1 || fail "Formatteren mislukt"
success "Disk geformatteerd met label: $STORAGE_LABEL"

# ==============================
# Mount point aanmaken
# ==============================
info "Mount point aanmaken..."
mkdir -p "$MOUNT_POINT"
success "Mount point klaar: $MOUNT_POINT"

# ==============================
# Mounten
# ==============================
info "Disk mounten..."
mount "$PARTITION" "$MOUNT_POINT" || fail "Mounten mislukt"
success "Disk gemount op $MOUNT_POINT"

# ==============================
# Fstab entry
# ==============================
info "Toevoegen aan /etc/fstab..."

# Check of entry al bestaat
if grep -q "$STORAGE_LABEL" /etc/fstab; then
    success "Fstab entry bestaat al"
else
    echo "LABEL=$STORAGE_LABEL $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
    success "Fstab entry toegevoegd"
fi

# ==============================
# Directory structuur aanmaken
# ==============================
info "Directory structuur aanmaken..."
mkdir -p "$MOUNT_POINT/docker-vms"
mkdir -p "$MOUNT_POINT/backups"

# Permissies
chmod 755 "$MOUNT_POINT"
chmod 755 "$MOUNT_POINT/docker-vms"
chmod 755 "$MOUNT_POINT/backups"

success "Directory structuur klaar"

# ==============================
# Proxmox storage toevoegen
# ==============================
info "Storage toevoegen aan Proxmox..."

# Verwijder eventuele stale config entry (actief of niet)
pvesm remove "$PROXMOX_STORAGE_NAME" >/dev/null 2>&1 || true

pvesm add dir "$PROXMOX_STORAGE_NAME" \
    --path "$MOUNT_POINT/docker-vms" \
    --content images,rootdir,vztmpl \
    --shared 0 >/dev/null 2>&1 || fail "Proxmox storage toevoegen mislukt"

success "Proxmox storage toegevoegd: $PROXMOX_STORAGE_NAME"

# ==============================
# Verificatie
# ==============================
info "Verificatie uitvoeren..."

# Check mount
if mount | grep -q "$MOUNT_POINT"; then
    success "Disk is correct gemount"
else
    fail "Disk is niet gemount!"
fi

info "Proxmox storage controleren..."
if pvesm status | grep -q "^$PROXMOX_STORAGE_NAME"; then
    success "Proxmox storage is actief"
else
    fail "Proxmox storage is niet actief!"
fi

# Disk info
AVAILABLE=$(df -h "$MOUNT_POINT" | tail -1 | awk '{print $4}')
USED=$(df -h "$MOUNT_POINT" | tail -1 | awk '{print $3}')

# ==============================
# Samenvatting
# ==============================
echo ""
echo -e "  ${GREEN_90}═══════════════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN_90}✓ Setup succesvol voltooid!${NC}"
echo -e "  ${GREEN_90}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${YELLOW_90}Disk:${NC}              $DISK_DEVICE ($DISK_MODEL)"
echo -e "  ${YELLOW_90}Partition:${NC}         $PARTITION"
echo -e "  ${YELLOW_90}Filesystem:${NC}        ext4"
echo -e "  ${YELLOW_90}Label:${NC}             $STORAGE_LABEL"
echo -e "  ${YELLOW_90}Mount point:${NC}       $MOUNT_POINT"
echo -e "  ${YELLOW_90}Proxmox storage:${NC}   $PROXMOX_STORAGE_NAME"
echo -e "  ${YELLOW_90}Beschikbaar:${NC}       $AVAILABLE"
echo -e "  ${YELLOW_90}In gebruik:${NC}        $USED"
echo ""
echo -e "  ${YELLOW_90}Directory structuur:${NC}"
echo -e "    $MOUNT_POINT/docker-vms/    → Docker VM data (via Proxmox)"
echo -e "    $MOUNT_POINT/backups/       → Backup locatie"
echo ""
success "Je kunt nu de Proxmox VM setup draaien met docker support!"
echo ""

exit 0
