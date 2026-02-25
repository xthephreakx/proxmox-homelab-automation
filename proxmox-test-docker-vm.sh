#!/usr/bin/env bash
set -uo pipefail

# ==============================
# Docker VM Test Script (VMID-based)
# ==============================
# Usage: ./test-docker-vm.sh <VMID>
# Example: ./test-docker-vm.sh 105

# ==============================
# Kleuren (source lib.sh of fallback)
# ==============================
LIB_FILE="/opt/vmconfigs/lib.sh"
if [[ -f "$LIB_FILE" ]]; then
    source "$LIB_FILE"
else
    MAGENTA_90='\033[38;2;255;0;124m'
    GREEN_90='\033[38;2;0;254;162m'
    PURPLE_90='\033[38;2;144;76;254m'
    YELLOW_90='\033[38;2;249;186;4m'
    RED_90='\033[38;2;255;0;54m'
    NC='\033[0m'
fi
BLUE_90='\033[38;2;0;48;255m'

# ==============================
# VM gebruiker laden
# ==============================
DEFAULTS_FILE="/opt/vmconfigs/defaults.conf"
if [[ -f "$DEFAULTS_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$DEFAULTS_FILE"
fi
VM_USER="${VM_USER:-pasta}"

# Test functies (overschrijven lib.sh spinners — tests gebruiken simpele output)
pass() { echo -e "  ${GREEN_90}✅ PASS${NC} - $1"; }
fail() { echo -e "  ${RED_90}❌ FAIL${NC} - $1"; }
info() { echo -e "  ${BLUE_90}ℹ️  INFO${NC} - $1"; }
warn() { echo -e "  ${YELLOW_90}⚠️  WARN${NC} - $1"; }

VMID="${1:-}"
if [[ -z "${VMID}" ]]; then
  fail "Geen VMID opgegeven"
  echo "Usage: $0 <VMID>"
  echo "Example: $0 105"
  exit 1
fi

if ! [[ "${VMID}" =~ ^[0-9]+$ ]]; then
  fail "VMID moet een nummer zijn"
  exit 1
fi

command -v qm >/dev/null 2>&1 || { fail "qm command niet gevonden (draai dit op de Proxmox host)"; exit 1; }
command -v jq >/dev/null 2>&1 || { fail "jq niet gevonden op Proxmox host (apt install -y jq)"; exit 1; }

if ! qm status "${VMID}" >/dev/null 2>&1; then
  fail "VMID ${VMID} bestaat niet (qm status ${VMID} faalt)"
  exit 1
fi

VM_STATUS="$(qm status "${VMID}" | awk '{print $2}')"
VM_NAME="$(qm config "${VMID}" | awk -F': ' '/^name:/{print $2}' || true)"

echo "════════════════════════════════════════════════════════"
echo "  Docker VM Test Suite (VMID-based)"
echo "  VMID:   ${VMID}"
echo "  Naam:   ${VM_NAME:-unknown}"
echo "  Status: ${VM_STATUS:-unknown}"
echo "════════════════════════════════════════════════════════"
echo ""

FAILED=0

# ------------------------------
# Helper: haal IP op via QGA
# ------------------------------
get_vm_ip() {
  # voorkeur: eerste non-lo IPv4
  qm guest cmd "${VMID}" network-get-interfaces 2>/dev/null | \
    jq -r '
      .[] |
      select(.name != "lo") |
      .["ip-addresses"][]? |
      select(.["ip-address-type"] == "ipv4") |
      .["ip-address"]
    ' | \
    grep -Ev '^(127\.|169\.254\.)' | \
    head -n1
}

# Wacht tot VM running + QGA IP beschikbaar
echo "━━━ Preflight: VM status + IP ophalen ━━━"

if [[ "${VM_STATUS}" != "running" ]]; then
  warn "VM is niet running (status: ${VM_STATUS}). IP ophalen kan falen."
fi

VM_IP=""
MAX_WAIT=120
STEP=3
WAITED=0

while [[ -z "${VM_IP}" && "${WAITED}" -lt "${MAX_WAIT}" ]]; do
  VM_IP="$(get_vm_ip || true)"
  if [[ -n "${VM_IP}" ]]; then
    break
  fi
  sleep "${STEP}"
  WAITED=$((WAITED + STEP))
done

if [[ -z "${VM_IP}" ]]; then
  fail "Geen IP kunnen ophalen via qemu-guest-agent binnen ${MAX_WAIT}s"
  echo ""
  echo "Troubleshooting:"
  echo "  - Zit QEMU guest agent aan op Proxmox?  qm config ${VMID} | grep agent"
  echo "  - Draait agent in VM?                   systemctl status qemu-guest-agent"
  echo "  - Handmatig check:                      qm guest cmd ${VMID} network-get-interfaces | jq"
  exit 1
fi

pass "IP gevonden via QGA: ${VM_IP}"
info "Test target: ${VM_USER}@${VM_IP}"

# ------------------------------
# SSH helpers
# ------------------------------
SSH_OPTS=(
  -o ConnectTimeout=8
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
)

ssh_run() {
  # ssh_run "<command>"
  ssh "${SSH_OPTS[@]}" "${VM_USER}@${VM_IP}" "$1"
}

# ==============================
# Test 1: SSH Connectivity
# ==============================
echo ""
echo "━━━ Test 1: SSH Connectivity ━━━"
if ssh "${SSH_OPTS[@]}" "${VM_USER}@${VM_IP}" "exit" 2>/dev/null; then
  pass "SSH connection successful"
else
  fail "Cannot connect via SSH"
  ((FAILED++))
  echo ""
  echo "Troubleshooting:"
  echo "  - Check VM console / cloud-init"
  echo "  - Check firewall / netwerk"
  echo "  - Probeer: ssh ${VM_USER}@${VM_IP}"
  exit 1
fi

# ==============================
# Test 2: Cloud-init completion + errors
# ==============================
echo ""
echo "━━━ Test 2: Cloud-init status ━━━"
if ssh_run "command -v cloud-init >/dev/null 2>&1 && timeout 180 cloud-init status --wait >/dev/null 2>&1; echo \$?" | grep -qx "0"; then
  pass "cloud-init is klaar (status --wait OK)"
else
  warn "cloud-init status --wait niet binnen 180s klaar of cloud-init ontbreekt"
  info "Laatste regels cloud-init output:"
  ssh_run "sudo tail -40 /var/log/cloud-init-output.log 2>/dev/null || true" || true
fi

echo ""
echo "━━━ Test 2b: cloud-init output errors ━━━"
ERR_COUNT=$(ssh_run "sudo grep -iE '(^|\\s)(ERROR|FAIL[^e]|Traceback|cloud-init.*failed)' /var/log/cloud-init-output.log 2>/dev/null | grep -ivE 'update-notifier|failed to fetch.*Translation|apt-get.*failed|packages that failed at' | wc -l || true")
if [[ "${ERR_COUNT}" -eq 0 ]]; then
  pass "Geen duidelijke ERROR/FAIL/Traceback in cloud-init-output.log"
else
  warn "Gevonden: ${ERR_COUNT} mogelijke error(s) in cloud-init-output.log"
  info "Top hits:"
  ssh_run "sudo grep -iE '(^|\\s)(ERROR|FAIL[^e]|Traceback|cloud-init.*failed)' /var/log/cloud-init-output.log 2>/dev/null | grep -ivE 'update-notifier|failed to fetch.*Translation|apt-get.*failed|packages that failed at' | tail -20" || true
  ((FAILED++))
fi

# ==============================
# Test 3: Persistent Disk Mount
# ==============================
echo ""
echo "━━━ Test 3: Persistent Disk Mount ━━━"
MOUNT_CHECK=$(ssh_run "mountpoint -q /mnt/docker-data && echo yes || echo no" 2>/dev/null || echo no)
if [[ "$MOUNT_CHECK" == "yes" ]]; then
  pass "/mnt/docker-data is gemount"
  DISK_INFO=$(ssh_run "df -h /mnt/docker-data | tail -1" || true)
  info "$DISK_INFO"
else
  fail "/mnt/docker-data is NIET gemount"
  ((FAILED++))
  echo ""
  echo "Troubleshooting:"
  echo "  - Check disk in VM: ssh ${VM_USER}@${VM_IP} 'lsblk -f'"
  echo "  - Check fstab:      ssh ${VM_USER}@${VM_IP} 'cat /etc/fstab | grep docker-data'"
  echo "  - Check logs:       ssh ${VM_USER}@${VM_IP} 'sudo tail -120 /var/log/cloud-init-output.log'"
fi

# ==============================
# Test 3b: fstab nofail entry
# ==============================
echo ""
echo "━━━ Test 3b: fstab entry (/mnt/docker-data + nofail) ━━━"
FSTAB_OK=$(ssh_run "sudo awk '!/^#/ && NF{print}' /etc/fstab | grep -qE '^[^ ]+ +/mnt/docker-data +ext4 +[^ ]*nofail' && echo yes || echo no" || echo no)
if [[ "$FSTAB_OK" == "yes" ]]; then
  pass "fstab entry aanwezig met nofail"
else
  warn "fstab entry ontbreekt of heeft geen nofail"
  info "fstab docker-data regels:"
  ssh_run "sudo grep -nE '/mnt/docker-data' /etc/fstab || true" || true
fi

# ==============================
# Test 4: Docker installed + running
# ==============================
echo ""
echo "━━━ Test 4: Docker service ━━━"
DOCKER_BIN=$(ssh_run "command -v docker >/dev/null 2>&1 && echo yes || echo no" || echo no)
if [[ "$DOCKER_BIN" == "yes" ]]; then
  pass "docker binary aanwezig"
else
  fail "docker is niet geïnstalleerd"
  ((FAILED++))
fi

DOCKER_ACTIVE=$(ssh_run "systemctl is-active docker 2>/dev/null || true" || true)
if [[ "$DOCKER_ACTIVE" == "active" ]]; then
  pass "docker service is active"
else
  fail "docker service is niet active (status: ${DOCKER_ACTIVE:-unknown})"
  ((FAILED++))
  info "docker status:"
  ssh_run "sudo systemctl --no-pager -l status docker || true" || true
fi

# ==============================
# Test 5: Docker Data Root
# ==============================
echo ""
echo "━━━ Test 5: Docker Data Root ━━━"
DOCKER_ROOT=$(ssh_run "docker info 2>/dev/null | awk -F': ' '/Docker Root Dir/ {print \$2}'" || true)
if [[ "$DOCKER_ROOT" == "/mnt/docker-data/docker" ]]; then
  pass "Docker gebruikt persistent storage (Docker Root Dir correct)"
  info "Docker Root Dir: $DOCKER_ROOT"
else
  fail "Docker Root Dir niet correct"
  ((FAILED++))
  info "Docker Root Dir: ${DOCKER_ROOT:-niet gevonden}"
  info "daemon.json:"
  ssh_run "sudo cat /etc/docker/daemon.json 2>/dev/null || true" || true
fi

# ==============================
# Test 6: Symlink /opt/docker
# ==============================
echo ""
echo "━━━ Test 6: Symlink /opt/docker ━━━"
SYMLINK_TARGET=$(ssh_run "[ -L /opt/docker ] && readlink -f /opt/docker || echo not-a-symlink" || echo not-a-symlink)
if [[ "$SYMLINK_TARGET" == "/mnt/docker-data/compose" ]]; then
  pass "/opt/docker → /mnt/docker-data/compose"
else
  fail "/opt/docker symlink is fout of ontbreekt"
  ((FAILED++))
  info "Current: $SYMLINK_TARGET"
  echo ""
  echo "Fix (manual):"
  echo "  ssh ${VM_USER}@${VM_IP} \"sudo rm -rf /opt/docker && sudo ln -sf /mnt/docker-data/compose /opt/docker\""
fi

# ==============================
# Test 7: Compose file aanwezig + compose werkt
# ==============================
echo ""
echo "━━━ Test 7: docker-compose.yml + docker compose ━━━"
# /opt/docker is een symlink naar /mnt/docker-data/compose
# Compose bestanden zitten in subdirectories (homelab/, arrstack/, etc.)
COMPOSE_COUNT=$(ssh_run "find -L /opt/docker -maxdepth 2 -name 'docker-compose.yml' 2>/dev/null | wc -l" || echo 0)
if [[ "${COMPOSE_COUNT}" -gt 0 ]]; then
  pass "${COMPOSE_COUNT} docker-compose.yml bestand(en) gevonden onder /opt/docker"
  ssh_run "find -L /opt/docker -maxdepth 2 -name 'docker-compose.yml' 2>/dev/null" | while read -r f; do
    info "  $f"
  done || true
else
  fail "Geen docker-compose.yml gevonden onder /opt/docker"
  FAILED=$((FAILED + 1))
  info "Listing /opt/docker:"
  ssh_run "ls -la /opt/docker || true" || true
fi

COMPOSE_OK=$(ssh_run "docker compose version >/dev/null 2>&1 && echo yes || echo no" || echo no)
if [[ "$COMPOSE_OK" == "yes" ]]; then
  pass "docker compose (v2) is beschikbaar"
else
  fail "docker compose command niet beschikbaar"
  ((FAILED++))
  info "docker --version:"
  ssh_run "docker --version || true" || true
fi

# ==============================
# Test 8: Containers running (traefik + portainer)
# ==============================
echo ""
echo "━━━ Test 8: Containers (traefik + portainer) ━━━"
TRAEFIK_RUNNING=$(ssh_run "docker ps --format '{{.Names}}' | grep -qx traefik && echo yes || echo no" || echo no)
PORTAINER_RUNNING=$(ssh_run "docker ps --format '{{.Names}}' | grep -qx portainer && echo yes || echo no" || echo no)

if [[ "$TRAEFIK_RUNNING" == "yes" && "$PORTAINER_RUNNING" == "yes" ]]; then
  pass "traefik en portainer draaien"
  ssh_run "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" || true
else
  fail "Niet alle verplichte containers draaien"
  ((FAILED++))
  info "traefik running: $TRAEFIK_RUNNING | portainer running: $PORTAINER_RUNNING"
  echo ""
  info "docker ps -a:"
  ssh_run "docker ps -a --format 'table {{.Names}}\t{{.Status}}'" || true
  echo ""
  echo "Troubleshooting:"
  echo "  - Start compose: ssh ${VM_USER}@${VM_IP} 'cd /opt/docker && docker compose up -d --remove-orphans'"
  echo "  - Logs:          ssh ${VM_USER}@${VM_IP} 'cd /opt/docker && docker compose logs --tail=200'"
fi

# ==============================
# Test 9: Traefik reachable (localhost:8080)
# ==============================
echo ""
echo "━━━ Test 9: Traefik Dashboard (Port 8080) ━━━"
TRAEFIK_HTTP=$(ssh_run "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080 2>/dev/null || true" || true)
if [[ "$TRAEFIK_HTTP" == "200" || "$TRAEFIK_HTTP" == "301" || "$TRAEFIK_HTTP" == "302" ]]; then
  pass "Traefik dashboard bereikbaar (HTTP ${TRAEFIK_HTTP})"
  info "URL: http://${VM_IP}:8080"
else
  warn "Traefik dashboard niet bereikbaar (HTTP ${TRAEFIK_HTTP:-n/a})"
  info "Check: ssh ${VM_USER}@${VM_IP} 'docker logs traefik --tail=200'"
fi

# ==============================
# Test 10: Portainer reachable (localhost:9000)
# ==============================
echo ""
echo "━━━ Test 10: Portainer (Port 9000) ━━━"
PORTAINER_HTTP=$(ssh_run "curl -s -o /dev/null -w '%{http_code}' http://localhost:9000 2>/dev/null || true" || true)
if [[ "$PORTAINER_HTTP" == "200" || "$PORTAINER_HTTP" == "307" || "$PORTAINER_HTTP" == "302" ]]; then
  pass "Portainer bereikbaar"
  info "URL: http://${VM_IP}:9000"
else
  warn "Portainer niet bereikbaar (HTTP ${PORTAINER_HTTP:-n/a})"
  info "Check: ssh ${VM_USER}@${VM_IP} 'docker logs portainer --tail=200'"
fi

# ==============================
# Test 11: Directory Structure (new layout)
# ==============================
echo ""
echo "━━━ Test 11: Directory structuur (/mnt/docker-data) ━━━"
REQ_DIRS=(/mnt/docker-data/docker /mnt/docker-data/compose /mnt/docker-data/media /mnt/docker-data/backups)
MISSING=0
for d in "${REQ_DIRS[@]}"; do
  exists=$(ssh_run "[ -d '$d' ] && echo yes || echo no" || echo no)
  if [[ "$exists" == "yes" ]]; then
    pass "Dir exists: $d"
  else
    fail "Dir missing: $d"
    ((MISSING++))
  fi
done
if [[ "$MISSING" -gt 0 ]]; then
  ((FAILED++))
  info "Listing /mnt/docker-data:"
  ssh_run "ls -la /mnt/docker-data || true" || true
fi

# ==============================
# Test 12: VM_USER in docker group
# ==============================
echo ""
echo "━━━ Test 12: ${VM_USER} in docker group ━━━"
IN_GROUP=$(ssh_run "id -nG ${VM_USER} | tr ' ' '\n' | grep -qx docker && echo yes || echo no" || echo no)
if [[ "$IN_GROUP" == "yes" ]]; then
  pass "${VM_USER} zit in docker group"
else
  warn "${VM_USER} zit NIET in docker group (kan pas werken na re-login)"
  info "Fix: ssh ${VM_USER}@${VM_IP} 'sudo usermod -aG docker ${VM_USER}' en daarna opnieuw inloggen."
fi

# ==============================
# Test 13: Arrstack — VPN verbonden
# ==============================
echo ""
echo "━━━ Test 13: Arrstack — WireGuard VPN verbonden ━━━"
WG_CONTAINER=$(ssh_run "docker ps --format '{{.Names}}' | grep -qx wireguard && echo yes || echo no" || echo no)
if [[ "$WG_CONTAINER" == "no" ]]; then
  warn "wireguard container draait niet — arrstack tests overgeslagen"
  info "Start de arrstack: ssh ${VM_USER}@${VM_IP} 'cd /mnt/docker-data/compose/arrstack && docker compose up -d'"
else
  pass "wireguard container draait"

  # Controleer of VPN écht verbonden is (bytes received > 0)
  WG_RX=$(ssh_run "docker exec wireguard wg show 2>/dev/null | awk '/transfer:/{gsub(/[^0-9.]/, \"\", \$2); print \$2}' || echo 0" || echo 0)
  if [[ -n "$WG_RX" && "$WG_RX" != "0" ]]; then
    pass "VPN tunnel verbonden (${WG_RX} B ontvangen)"
    # Toon publiek IP via de VPN tunnel
    PUBLIC_IP=$(ssh_run "docker exec wireguard curl -s --max-time 5 https://api.ipify.org 2>/dev/null || true" || true)
    if [[ -n "$PUBLIC_IP" ]]; then
      info "Publiek IP (via VPN): ${PUBLIC_IP}"
    fi
  else
    fail "VPN tunnel NIET verbonden (0 B received) — controleer PIA credentials in .env"
    ((FAILED++))
    info "Logs: ssh ${VM_USER}@${VM_IP} 'docker logs wireguard --tail=50'"
  fi

  # ==============================
  # Test 14: Arrstack — alle containers healthy
  # ==============================
  echo ""
  echo "━━━ Test 14: Arrstack — alle containers draaien ━━━"
  ARR_SERVICES=(wireguard sabnzbd radarr sonarr bazarr qbittorrent)
  ARR_FAILED=0
  for svc in "${ARR_SERVICES[@]}"; do
    SVC_STATUS=$(ssh_run "docker ps --filter name=^${svc}$ --format '{{.Status}}' 2>/dev/null || true" || true)
    if echo "$SVC_STATUS" | grep -qi "up"; then
      pass "${svc}: ${SVC_STATUS}"
    else
      fail "${svc} draait NIET (status: ${SVC_STATUS:-niet gevonden})"
      ((ARR_FAILED++))
    fi
  done
  if [[ "$ARR_FAILED" -gt 0 ]]; then
    ((FAILED++))
    info "docker compose ps: ssh ${VM_USER}@${VM_IP} 'cd /mnt/docker-data/compose/arrstack && docker compose ps'"
  fi

  # Namespace sync check — arr containers moeten in wireguard netwerk namespace zitten
  SONARR_IN_NS=$(ssh_run "docker exec wireguard ss -tlnp 2>/dev/null | grep -q ':8989' && echo yes || echo no" || echo no)
  if [[ "$SONARR_IN_NS" == "yes" ]]; then
    pass "Arr services delen wireguard netwerk namespace"
  else
    warn "Sonarr NIET in wireguard namespace — herstart arr services na wireguard restart"
    info "Fix: cd /mnt/docker-data/compose/arrstack && docker compose restart sonarr radarr sabnzbd bazarr qbittorrent"
  fi

  # ==============================
  # Test 15: Arrstack — poorten bereikbaar van buitenaf
  # ==============================
  echo ""
  echo "━━━ Test 15: Arrstack — poorten bereikbaar van host ━━━"
  declare -A ARR_PORTS=(
    [sabnzbd]=8301
    [radarr]=8302
    [sonarr]=8303
    [bazarr]=6767
    [qbittorrent]=8311
  )
  PORT_FAILED=0
  for svc in "${!ARR_PORTS[@]}"; do
    port="${ARR_PORTS[$svc]}"
    HTTP_CODE=$(ssh_run "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:${port} 2>/dev/null || echo 000" || echo 000)
    if [[ "$HTTP_CODE" != "000" && "$HTTP_CODE" != "" ]]; then
      pass "${svc} (poort ${port}): HTTP ${HTTP_CODE}"
      info "URL: http://${VM_IP}:${port}"
    else
      fail "${svc} (poort ${port}): niet bereikbaar (time-out of geen response)"
      ((PORT_FAILED++))
    fi
  done
  if [[ "$PORT_FAILED" -gt 0 ]]; then
    ((FAILED++))
    info "Check: ssh ${VM_USER}@${VM_IP} 'docker exec wireguard ss -tlnp'"
  fi

  # ==============================
  # Test 16: Arrstack — LAN routing (variant-bewust)
  # ==============================
  echo ""
  echo "━━━ Test 16: Arrstack — LAN routing ━━━"

  # Detecteer WireGuard variant
  WG_IMAGE=$(ssh_run "docker inspect wireguard --format '{{.Config.Image}}' 2>/dev/null || echo unknown" || echo unknown)

  if echo "$WG_IMAGE" | grep -q "thrnz"; then
    info "WireGuard variant: PIA (thrnz/docker-wireguard-pia)"

    LAN_RULE=$(ssh_run "docker exec wireguard ip rule show 2>/dev/null | grep -E '192\.168\.' | head -3 || true" || true)
    LAN_ROUTE=$(ssh_run "docker exec wireguard ip route show 2>/dev/null | grep -E '192\.168\.' | head -3 || true" || true)
    if [[ -n "$LAN_RULE" || -n "$LAN_ROUTE" ]]; then
      pass "LAN routing aanwezig (LOCAL_NETWORK actief)"
      [[ -n "$LAN_RULE" ]]  && info "ip rule:  $LAN_RULE"
      [[ -n "$LAN_ROUTE" ]] && info "ip route: $LAN_ROUTE"
    else
      warn "Geen 192.168.x regel — LAN toegang mogelijk beperkt"
      info "Check LOCAL_NETWORK in .env en herstart de arrstack"
    fi

    # .env aanwezig + PIA credentials?
    ENV_OK=$(ssh_run "[ -f /mnt/docker-data/compose/arrstack/.env ] && echo yes || echo no" || echo no)
    if [[ "$ENV_OK" == "yes" ]]; then
      pass ".env bestand aanwezig"
      STILL_PLACEHOLDER=$(ssh_run "grep -qE 'PIA_(USER|PASS)=your-pia' /mnt/docker-data/compose/arrstack/.env && echo yes || echo no" || echo no)
      if [[ "$STILL_PLACEHOLDER" == "yes" ]]; then
        warn ".env bevat nog placeholder PIA credentials — vul je gegevens in!"
        info "Edit: nano /mnt/docker-data/compose/arrstack/.env"
      else
        pass "PIA credentials ingevuld in .env"
      fi
    else
      fail ".env bestand ontbreekt in /mnt/docker-data/compose/arrstack/"
      ((FAILED++))
      info "Maak aan: ssh ${VM_USER}@${VM_IP} 'echo PIA_USER=... > /mnt/docker-data/compose/arrstack/.env'"
    fi

  else
    info "WireGuard variant: Default (linuxserver/wireguard)"

    # Check ip route voor LAN (via PostUp in .conf)
    LAN_ROUTE=$(ssh_run "docker exec wireguard ip route show 2>/dev/null | grep -E '192\.168\.' | head -3 || true" || true)
    if [[ -n "$LAN_ROUTE" ]]; then
      pass "LAN route aanwezig in wireguard container"
      info "ip route: $LAN_ROUTE"
    else
      warn "Geen 192.168.x route — LAN toegang niet bereikbaar"
      info "Voeg PostUp/PostDown toe aan [Interface] in je .conf bestand:"
      info "PostUp = ip rule add from 192.168.0.0/16 table main priority 99; ip route add 192.168.0.0/16 via 172.18.0.1 dev eth0"
      info "PostDown = ip rule del from 192.168.0.0/16 table main priority 99; ip route del 192.168.0.0/16 via 172.18.0.1 dev eth0"
    fi

    # Check wg_confs/ heeft minstens één .conf bestand
    CONF_COUNT=$(ssh_run "find /mnt/docker-data/compose/arrstack/wireguard/config/wg_confs/ -name '*.conf' 2>/dev/null | wc -l" || echo 0)
    if [[ "${CONF_COUNT}" -gt 0 ]]; then
      pass "WireGuard config aanwezig in wg_confs/ (${CONF_COUNT} bestand(en))"
    else
      warn "Geen .conf gevonden in wg_confs/"
      info "Zet je config in: /mnt/docker-data/compose/arrstack/wireguard/config/wg_confs/"
    fi
  fi
fi

# ==============================
# Summary
# ==============================
echo ""
echo "════════════════════════════════════════════════════════"
if [[ $FAILED -eq 0 ]]; then
  echo -e "${GREEN_90}🎉 ALLE TESTS GESLAAGD!${NC}"
  echo ""
  echo "VMID: ${VMID} | IP: ${VM_IP}"
  echo "Toegang:"
  echo "  • SSH:          ssh ${VM_USER}@${VM_IP}"
  echo "  • Traefik:      http://${VM_IP}:8080"
  echo "  • Portainer:    http://${VM_IP}:9000"
  echo "  • SABnzbd:      http://${VM_IP}:8301"
  echo "  • Radarr:       http://${VM_IP}:8302"
  echo "  • Sonarr:       http://${VM_IP}:8303"
  echo "  • Bazarr:       http://${VM_IP}:6767"
  echo "  • qBittorrent:  http://${VM_IP}:8311"
else
  echo -e "${RED_90}⚠️  $FAILED TEST(S) GEFAALD${NC}"
  echo ""
  echo "VMID: ${VMID} | IP: ${VM_IP}"
  echo "Snelle tip:"
  echo "  ssh ${VM_USER}@${VM_IP} 'sudo tail -200 /var/log/cloud-init-output.log'"
fi
echo "════════════════════════════════════════════════════════"

exit $FAILED