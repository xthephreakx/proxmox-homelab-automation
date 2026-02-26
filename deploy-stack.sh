#!/usr/bin/env bash
set -euo pipefail

# ==============================
# deploy-stack.sh
# ==============================
# Injecteert Traefik labels in een docker-compose.yml
# en deployt de stack naar de Docker VM.
#
# Gebruik:
#   ./deploy-stack.sh <stack-naam> <compose-bestand-of-url> [poort]
#
# Voorbeelden:
#   ./deploy-stack.sh it-tools https://raw.githubusercontent.com/.../docker-compose.yml 8080
#   ./deploy-stack.sh mijn-app ./docker-compose.yml 3000
#   ./deploy-stack.sh mijn-app ./docker-compose.yml        # poort auto-detectie

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

trap 'stop_spinner; tput cnorm 2>/dev/null || true' EXIT INT TERM

# ==============================
# Config laden
# ==============================
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CONF_FILE="$SCRIPT_DIR/deploy.conf"

if [[ ! -f "$CONF_FILE" ]]; then
    fail "Config bestand niet gevonden: $CONF_FILE\nKopieer deploy.conf.example naar deploy.conf en vul je gegevens in."
fi

source "$CONF_FILE"

# Verplichte config variabelen
: "${VM_HOST:?  VM_HOST niet ingesteld in deploy.conf}"
: "${VM_USER:?  VM_USER niet ingesteld in deploy.conf}"
: "${SSH_KEY:?  SSH_KEY niet ingesteld in deploy.conf}"
: "${BASE_DOMAIN:?  BASE_DOMAIN niet ingesteld in deploy.conf}"
: "${COMPOSE_BASE_PATH:?  COMPOSE_BASE_PATH niet ingesteld in deploy.conf}"

SSH_OPTS="-i ${SSH_KEY} -o StrictHostKeyChecking=no -o BatchMode=yes"

# ==============================
# Argumenten
# ==============================
if [[ $# -lt 2 ]]; then
    printf "\n${YELLOW_90}Gebruik:${NC} $0 <stack-naam> <compose-bestand-of-url> [poort]\n\n"
    printf "  ${GREEN_90}Voorbeeld:${NC}\n"
    printf "    $0 it-tools https://raw.githubusercontent.com/.../docker-compose.yml 8080\n"
    printf "    $0 mijn-app ./docker-compose.yml 3000\n\n"
    exit 1
fi

STACK_NAME="$1"
COMPOSE_INPUT="$2"
PORT_OVERRIDE="${3:-}"

# ==============================
# Start
# ==============================
header "Deploy Stack: $STACK_NAME"

# ==============================
# Stap 1: Compose ophalen
# ==============================
step "Compose ophalen"

TMP_DIR=$(mktemp -d)
trap 'stop_spinner; tput cnorm 2>/dev/null || true; rm -rf "$TMP_DIR"' EXIT INT TERM

COMPOSE_RAW="$TMP_DIR/docker-compose.raw.yml"

if [[ "$COMPOSE_INPUT" =~ ^https?:// ]]; then
    info "Downloaden van URL..."
    curl -fsSL "$COMPOSE_INPUT" -o "$COMPOSE_RAW" 2>/dev/null || fail "Kon compose niet downloaden van: $COMPOSE_INPUT"
    success "Compose gedownload"
else
    [[ -f "$COMPOSE_INPUT" ]] || fail "Bestand niet gevonden: $COMPOSE_INPUT"
    cp "$COMPOSE_INPUT" "$COMPOSE_RAW"
    success "Compose geladen: $COMPOSE_INPUT"
fi

# ==============================
# Stap 2: Poort detecteren + Traefik injecteren (Python)
# ==============================
step "Traefik labels injecteren"

info "PyYAML controleren..."
python3 -c "import yaml" 2>/dev/null || {
    stop_spinner
    warn "PyYAML niet gevonden, installeren..."
    pip3 install pyyaml -q
}
success "PyYAML beschikbaar"

COMPOSE_OUT="$TMP_DIR/docker-compose.yml"

info "Compose transformeren..."
DETECTED_PORT=$(python3 - "$COMPOSE_RAW" "$STACK_NAME" "$BASE_DOMAIN" "$PORT_OVERRIDE" "$COMPOSE_OUT" <<'PYEOF'
import sys, yaml, re

compose_file = sys.argv[1]
stack_name   = sys.argv[2]
base_domain  = sys.argv[3]
port_override = sys.argv[4]
output_file  = sys.argv[5]

with open(compose_file, "r") as f:
    doc = yaml.safe_load(f)

if not doc or "services" not in doc:
    print("ERROR: geen 'services' gevonden in compose", file=sys.stderr)
    sys.exit(1)

services = doc["services"]

# Detecteer eerste service met ports, of gewoon de eerste service
target_service = None
detected_port  = None

for svc_name, svc in services.items():
    ports = svc.get("ports", [])
    if ports:
        target_service = svc_name
        # Pak de container-poort (rechts van de : of het gehele getal)
        port_str = str(ports[0])
        match = re.search(r':?(\d+)(?:/tcp|/udp)?$', port_str.split("->")[-1])
        if match:
            detected_port = int(match.group(1))
        break

if not target_service:
    target_service = list(services.keys())[0]

# Poort: override > gedetecteerd > fout
if port_override:
    port = int(port_override)
elif detected_port:
    port = detected_port
else:
    print("ERROR: kan poort niet detecteren, geef poort op als 3e argument", file=sys.stderr)
    sys.exit(1)

print(port)  # output voor bash

svc = services[target_service]

# Verwijder directe port mappings
svc.pop("ports", None)

# Voeg proxy netwerk toe aan service
if "networks" not in svc:
    svc["networks"] = []
if isinstance(svc["networks"], list) and "proxy" not in svc["networks"]:
    svc["networks"].append("proxy")
elif isinstance(svc["networks"], dict) and "proxy" not in svc["networks"]:
    svc["networks"]["proxy"] = None

# Traefik labels
traefik_labels = [
    "traefik.enable=true",
    f"traefik.http.routers.{stack_name}.rule=Host(`{stack_name}.{base_domain}`)",
    f"traefik.http.routers.{stack_name}.entrypoints=websecure",
    f"traefik.http.routers.{stack_name}.tls=true",
    f"traefik.http.routers.{stack_name}.tls.certresolver=le",
    f"traefik.http.routers.{stack_name}.tls.domains[0].main=*.{base_domain}",
    f"traefik.http.services.{stack_name}.loadbalancer.server.port={port}",
]

existing = svc.get("labels", [])
if isinstance(existing, dict):
    existing = [f"{k}={v}" for k, v in existing.items()]
# Verwijder eventuele bestaande traefik labels en voeg nieuwe toe
existing = [l for l in existing if not str(l).startswith("traefik.")]
svc["labels"] = existing + traefik_labels

# Top-level proxy netwerk
if "networks" not in doc:
    doc["networks"] = {}
doc["networks"]["proxy"] = {"external": True}

with open(output_file, "w") as f:
    yaml.dump(doc, f, default_flow_style=False, allow_unicode=True, sort_keys=False)

PYEOF
) || fail "Compose transformatie mislukt"

success "Traefik labels geïnjecteerd op poort $DETECTED_PORT → $STACK_NAME.$BASE_DOMAIN"

# ==============================
# Stap 3: .env aanmaken
# ==============================
ENV_FILE="$TMP_DIR/.env"
cat > "$ENV_FILE" <<EOF
BASE_DOMAIN=${BASE_DOMAIN}
COMPOSE_PROJECT_NAME=${STACK_NAME}
EOF

# ==============================
# Stap 4: Map aanmaken op VM
# ==============================
step "Map aanmaken op VM"

REMOTE_PATH="${COMPOSE_BASE_PATH}/${STACK_NAME}"

info "SSH verbinding testen..."
ssh $SSH_OPTS "${VM_USER}@${VM_HOST}" "echo ok" > /dev/null 2>&1 || fail "Kan niet verbinden met ${VM_USER}@${VM_HOST}"
success "SSH verbinding OK"

info "Map aanmaken: $REMOTE_PATH"
ssh $SSH_OPTS "${VM_USER}@${VM_HOST}" \
    "sudo mkdir -p '${REMOTE_PATH}' && sudo chown ${VM_USER}:${VM_USER} '${REMOTE_PATH}'" \
    > /dev/null 2>&1
success "Map aangemaakt"

# ==============================
# Stap 5: Bestanden uploaden
# ==============================
step "Bestanden uploaden"

info "docker-compose.yml uploaden..."
scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
    "$COMPOSE_OUT" "$ENV_FILE" \
    "${VM_USER}@${VM_HOST}:${REMOTE_PATH}/" > /dev/null 2>&1
success "Bestanden geüpload"

# ==============================
# Stap 6: Container starten
# ==============================
step "Container starten"

info "docker compose up --build..."
ssh $SSH_OPTS "${VM_USER}@${VM_HOST}" \
    "cd '${REMOTE_PATH}' && docker compose up -d --build 2>&1" \
    | while IFS= read -r line; do
        [[ "$line" =~ (Started|Running|Created|Built|Pulled) ]] && success "$line" || true
      done

# ==============================
# Stap 7: Verifiëren
# ==============================
step "Verifiëren"

sleep 2

CONTAINER_STATUS=$(ssh $SSH_OPTS "${VM_USER}@${VM_HOST}" \
    "docker ps --filter name=${STACK_NAME} --format '{{.Status}}' 2>/dev/null | head -1")

if [[ "$CONTAINER_STATUS" =~ ^Up ]]; then
    success "Container draait: $CONTAINER_STATUS"
else
    fail "Container status onbekend: '${CONTAINER_STATUS}'"
fi

TRAEFIK_RULE=$(ssh $SSH_OPTS "${VM_USER}@${VM_HOST}" \
    "docker inspect ${STACK_NAME} --format '{{index .Config.Labels \"traefik.http.routers.${STACK_NAME}.rule\"}}' 2>/dev/null || true")

if [[ -n "$TRAEFIK_RULE" ]]; then
    success "Traefik route: $TRAEFIK_RULE"
else
    warn "Traefik label niet gevonden (container naam kan afwijken van stack naam)"
fi

# ==============================
# Klaar
# ==============================
printf "\n${GREEN_90}══════════════════════════════════════${NC}\n"
printf "  ${GREEN_90}✓ Stack '${STACK_NAME}' is live!${NC}\n"
printf "  ${BLUE_90}➜ https://${STACK_NAME}.${BASE_DOMAIN}${NC}\n"
printf "${GREEN_90}══════════════════════════════════════${NC}\n\n"
