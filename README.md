<p align="center">
  <img src="assets/bannerv2.svg" alt="Proxmox Configurate banner" width="1000">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Proxmox-9.x-FF007C?style=flat-square" alt="Proxmox">
  <img src="https://img.shields.io/badge/Bash-5.0+-00FEA2?style=flat-square&logoColor=000" alt="Bash">
  <img src="https://img.shields.io/badge/Python-3.x-00A2FF?style=flat-square&logoColor=000" alt="Python">
  <img src="https://img.shields.io/badge/Docker-CE-904CFE?style=flat-square" alt="Docker">
  <img src="https://img.shields.io/badge/Cloud--init-Ubuntu_Jammy-FF007C?style=flat-square" alt="Cloud-init">
  <img src="https://img.shields.io/badge/License-MIT-FFD300?style=flat-square&logoColor=000" alt="License">
</p>

<p align="center">Proxmox VE automation scripts for setting up a Docker homelab with VM templates, cloud-init, wildcard TLS, and persistent storage.</p>

---

## Index

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [deploy-stack.sh — Stack deployer](#deploy-stacksh--stack-deployer)
- [Configuration](#configuration)
- [Services](#services)
- [Post-Install Notes](#post-install-notes)
- [Backup Management](#backup-management)
- [Troubleshooting](#troubleshooting)
- [File Structure](#file-structure)
- [Safety Notes](#safety-notes)

---

## Overview

This repo automates the full setup of a Proxmox VE homelab. A single script (`proxmox-setup-vms.sh`) generates cloud-init snippets, a shared library, VM configuration profiles, and a `new` CLI command. Running `new docker` provisions a VM that auto-configures Docker, Traefik (with wildcard SSL via Cloudflare DNS), and two Docker Compose stacks:

- **homelab** — Traefik, Mylar, Suwayomi, Dockge, Audiobookshelf, Komga, Tailscale (Komga + Audiobookshelf via Serve)
- **arrstack** — WireGuard VPN gateway + SABnzbd, Radarr, Sonarr, Bazarr (behind VPN) + qBittorrent (own network, port forwarding)

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Proxmox VE 9.x installed | Single-node setup |
| Secondary disk for Docker data | Formatted and configured by `proxmox-setup-storage.sh` |
| Cloudflare account | Domain (e.g. `yourdomain.com`) must be managed by Cloudflare |
| Cloudflare API Token | `Zone:DNS:Edit` permission required for wildcard SSL via DNS-01 challenge |
| Local DNS wildcard record | `*.local.<domain>` pointing to the Docker VM IP (e.g. in UniFi or Pi-hole) |

### Cloudflare API Token

Create a token at [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens) with:

- **Permissions:** Zone / DNS / Edit
- **Zone Resources:** Include / Specific zone / `<your-domain>`

This token goes into `CF_DNS_API_TOKEN` in the `.env` file and is used by Traefik to complete the ACME DNS-01 challenge for wildcard certificates.

### Local DNS Wildcard Record

Add a wildcard DNS record in your local DNS resolver (UniFi, Pi-hole, pfSense, etc.):

```
*.local.yourdomain.com  →  <Docker VM IP>
```

This routes all subdomains (e.g. `traefik.local.yourdomain.com`) to Traefik running on the Docker VM.

---

## Quick Start

SSH into your Proxmox host as root and run:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/xthephreakx/proxmox-homelab-automation/main/install.sh)"
```

Scripts are installed to `/opt/proxmox-setup/`. Run them in order using the launcher:

```bash
./proxmox-launcher.sh
```

The launcher provides a numbered menu with all available scripts. Use **option 11** to download the latest version of all scripts directly from GitHub without leaving the menu.

Or run the VM setup script directly:

```bash
chmod +x proxmox-setup-vms.sh
./proxmox-setup-vms.sh
```

Then create a Docker VM:

```bash
new docker
```

### VM Profiles

| Type | Cores | RAM | Disk | Description |
|------|-------|-----|------|-------------|
| `ubuntu` | 2 | 4 GB | 10G | Minimal Ubuntu server |
| `ubuntu-large` | 2 | 32 GB | 100G | Ubuntu server with large resources |
| `ubuntu-gui` | 4 | 12 GB | 50G | Ubuntu desktop environment |
| `docker` | 2 | 20 GB | 50G | Docker host with Traefik + stacks |

---

## deploy-stack.sh — Stack deployer

`deploy-stack.sh` deploys any Docker Compose stack to the Docker VM with automatic Traefik integration. Run it from your Mac — it handles everything from transformation to restart.

> **Local requirements (Mac):** `python3` and `PyYAML` — used to transform and merge compose files before uploading. The script installs PyYAML automatically if missing (`pip3 install pyyaml`).

### Setup

Copy the example config and fill in your values (gitignored, never committed):

```bash
cp deploy.conf.example deploy.conf
nano deploy.conf
```

| Variable | Example | Description |
|----------|---------|-------------|
| `VM_HOST` | `192.168.1.100` | Docker VM IP address |
| `VM_USER` | `pasta` | SSH user on the VM |
| `SSH_KEY` | `~/.ssh/proxmox_vm_key` | Path to your SSH private key |
| `BASE_DOMAIN` | `local.yourdomain.com` | Base domain for Traefik routes |
| `COMPOSE_BASE_PATH` | `/mnt/docker-data/compose` | Stack root directory on the VM |

### Usage

```bash
# Deploy a new standalone stack (auto-detect port)
./deploy-stack.sh <stack-name> <compose-file-or-url>

# Deploy with explicit port
./deploy-stack.sh <stack-name> <compose-file-or-url> <port>

# Merge a service into an existing stack
./deploy-stack.sh <stack-name> <compose-file-or-url> <port> --add-to <existing-stack>
```

### Examples

```bash
# New standalone stack from a URL
./deploy-stack.sh it-tools https://raw.githubusercontent.com/.../docker-compose.yml 8080

# New standalone stack from a local file (store test files in test/ — gitignored)
./deploy-stack.sh my-app ./test/my-app-compose.yml 3000

# Add a service to an existing stack (e.g. a second homepage instance into the homepage stack)
./deploy-stack.sh homepage-eliza ./test/homepage-eliza-compose.yml 3000 --add-to homepage
```

### What it does automatically

| Feature | Details |
|---------|---------|
| **Traefik labels** | Injects router/service labels — service available at `<name>.<BASE_DOMAIN>` |
| **Port detection** | Reads container port from `ports:` mapping — override with 3rd argument |
| **Service rename** | Renames the service key to `<stack-name>` to prevent merge conflicts |
| **Path rewriting** | NAS paths (`/volume1/...`) are rewritten to VM paths under `COMPOSE_BASE_PATH` |
| **Env cleanup** | Strips trailing garbage characters from env values (e.g. `TZ=Europe/Amsterdam>`) |
| **Version removal** | Removes deprecated `version:` key |
| **Volume dirs** | Creates rewritten volume directories on the VM with correct ownership |
| **`--add-to` merge** | Downloads existing compose from VM, merges new service, re-uploads, restarts |

> **Tip:** Save compose files you want to deploy in `test/` — this folder is gitignored so nothing sensitive gets committed.

---

## Configuration

All configuration is stored in `/mnt/docker-data/compose/homelab/.env` on the Docker VM. The file is created automatically on first boot. Edit it before or after first run:

```bash
nano /mnt/docker-data/compose/homelab/.env
```

| Variable | Example | Description |
|----------|---------|-------------|
| `BASE_DOMAIN` | `local.yourdomain.com` | Base domain for all service URLs. All services get `<name>.${BASE_DOMAIN}` |
| `LE_EMAIL` | `me@example.com` | Email for Let's Encrypt account registration |
| `CF_DNS_API_TOKEN` | `<token>` | Cloudflare token with Zone:DNS:Edit — required for wildcard cert |
| `TRAEFIK_DASHBOARD_AUTH` | (optional) | htpasswd string for Traefik dashboard basic auth |
| `TS_AUTHKEY` | `tskey-auth-...` | Tailscale auth key for `komga-ts` node — share Komga with friends |
| `TS_AUTHKEY_AUDIOBOOK` | `tskey-auth-...` | Tailscale auth key for `audiobook-ts` node — share Audiobookshelf with friends |

For the arrstack, edit `/mnt/docker-data/compose/arrstack/.env`:

| Variable | Example | Description |
|----------|---------|-------------|
| `BASE_DOMAIN` | `local.yourdomain.com` | Must match homelab BASE_DOMAIN |
| `PIA_USER` | `p1234567` | PIA username (PIA variant only) |
| `PIA_PASS` | `...` | PIA password (PIA variant only) |

> After editing `.env`, restart the affected stack: `cd /mnt/docker-data/compose/homelab && docker compose up -d`

### ACME staging vs production

The generated `traefik.yml` uses the Let's Encrypt **staging** server by default (safe for testing, issues untrusted certs). Switch to production when ready:

```yaml
# /mnt/docker-data/compose/traefik/traefik.yml
certificatesResolvers:
  le:
    acme:
      #caServer: "https://acme-staging-v02.api.letsencrypt.org/directory"
      caServer: "https://acme-v02.api.letsencrypt.org/directory"
```

Then remove `acme.json` and restart Traefik:

```bash
rm /mnt/docker-data/compose/traefik/acme.json
touch /mnt/docker-data/compose/traefik/acme.json
chmod 600 /mnt/docker-data/compose/traefik/acme.json
cd /mnt/docker-data/compose/homelab && docker compose restart traefik
```

---

## Services

### Homelab stack

| Service | URL | Direct Port | Description |
|---------|-----|-------------|-------------|
| Traefik | `https://traefik.${BASE_DOMAIN}` | 80 / 443 | Reverse proxy + TLS termination |
| FileBrowser | `https://filebrowser.${BASE_DOMAIN}` | 80 | Web-based file manager |
| IT-Tools | `https://it-tools.${BASE_DOMAIN}` | 8080 | Developer tools (sharevb fork) |
| Homepage | `https://homepage.${BASE_DOMAIN}` | 3000 | Dashboard |
| Mylar | `https://mylar.${BASE_DOMAIN}` | 8304 | Comics downloader |
| Suwayomi | `https://suwayomi.${BASE_DOMAIN}` | 8316 | Manga reader |
| Dockge | `https://dockge.${BASE_DOMAIN}` | 5001 | Docker Compose stack manager |
| Audiobookshelf | `https://audiobookshelf.${BASE_DOMAIN}` | 8309 | Audiobook and ebook server |
| Komga | `https://komga.${BASE_DOMAIN}` | 8306 | Comics and ebook server |
| tailscale-komga | `https://komga-ts.<tailnet>.ts.net` | — | Tailscale Serve — share Komga with friends |
| tailscale-audiobook | `https://audiobook-ts.<tailnet>.ts.net` | — | Tailscale Serve — share Audiobookshelf with friends |
| dockerproxy | (internal) | 2375 | Read-only Docker socket proxy for Homepage |

### Arrstack (behind WireGuard VPN)

| Service | URL | Direct Port | Description |
|---------|-----|-------------|-------------|
| SABnzbd | `https://sabnzbd.${BASE_DOMAIN}` | 8301 | Usenet downloader |
| Radarr | `https://radarr.${BASE_DOMAIN}` | 8302 | Movie management |
| Sonarr | `https://sonarr.${BASE_DOMAIN}` | 8303 | TV show management |
| Bazarr | `https://bazarr.${BASE_DOMAIN}` | 6767 | Subtitle management |

SABnzbd, Radarr, Sonarr and Bazarr run with `network_mode: service:wireguard` — all traffic is routed through the WireGuard container.

### qBittorrent (own network)

| Service | URL | Direct Port | Torrent Port | Description |
|---------|-----|-------------|--------------|-------------|
| qBittorrent | `https://qb.${BASE_DOMAIN}` | 8311 | 43398 TCP+UDP | Torrent client |

qBittorrent runs on its own network (not behind WireGuard) for direct port forwarding support. Configure a port forward on your router for port `43398` (TCP+UDP) to the Docker VM IP. This allows peers to make inbound connections, which is required for seeding on private trackers.

**Volume mounts per service:**
- **SABnzbd:** `/downloads`, `/incomplete-downloads`, `/NZB`
- **Radarr:** `/downloads`, `/incomplete-downloads`, `/NZB`, `/movies`
- **Sonarr:** `/downloads`, `/incomplete-downloads`, `/NZB`, `/tvshows`
- **Mylar:** `/comics`, `/downloads`, `/watch`

---

## Post-Install Notes

### SABnzbd — hostname whitelist

SABnzbd requires its reverse proxy hostname to be whitelisted in `sabnzbd.ini`. The setup script automatically:

1. Starts the arrstack with `docker compose up -d`
2. Waits up to 60 seconds for SABnzbd to create its config file
3. Adds `sabnzbd.${BASE_DOMAIN}` to `host_whitelist` in `sabnzbd.ini`
4. Restarts the SABnzbd container

If the automatic configuration fails (e.g. SABnzbd did not initialize within 60 seconds), add the entry manually:

```bash
SABNZBD_INI="/mnt/docker-data/compose/arrstack/sabnzbd/config/sabnzbd.ini"
# Stop sabnzbd first
cd /mnt/docker-data/compose/arrstack && docker compose stop sabnzbd
# Add the whitelist entry under [misc]
sed -i "/^\[misc\]/a host_whitelist = sabnzbd.local.yourdomain.com" "$SABNZBD_INI"
# Restart
docker compose start sabnzbd
```

### Tailscale — Serve setup + node sharing

Both Tailscale containers (`tailscale-komga` and `tailscale-audiobook`) use `TS_SERVE_CONFIG` to proxy Komga and Audiobookshelf over HTTPS on your tailnet. Generate auth keys at [tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys) and add them to `.env`:

```bash
TS_AUTHKEY=tskey-auth-...           # for komga-ts
TS_AUTHKEY_AUDIOBOOK=tskey-auth-... # for audiobook-ts
```

To share with friends, go to [tailscale.com/admin/machines](https://login.tailscale.com/admin/machines), click the node (`komga-ts` or `audiobook-ts`) → **Share** → enter their email. Friends accept the invite in their Tailscale app and can then access:

- `https://komga-ts.<tailnet>.ts.net` — Komga
- `https://audiobook-ts.<tailnet>.ts.net` — Audiobookshelf

### WireGuard — VPN credentials

The WireGuard container does not start with a valid config until credentials are provided.

**PIA variant:** Edit the arrstack `.env` before starting:

```bash
nano /mnt/docker-data/compose/arrstack/.env
# Set PIA_USER and PIA_PASS
cd /mnt/docker-data/compose/arrstack && docker compose up -d
```

**Default WireGuard variant:** Place your `.conf` file in the config directory before starting:

```bash
cp your-vpn.conf /mnt/docker-data/compose/arrstack/wireguard/config/wg_confs/
# Add PostUp/PostDown for LAN access to [Interface] in the .conf file:
# PostUp = ip rule add from 192.168.0.0/16 table main priority 99; ip route add 192.168.0.0/16 via 172.18.0.1 dev eth0
# PostDown = ip rule del from 192.168.0.0/16 table main priority 99; ip route del 192.168.0.0/16 via 172.18.0.1 dev eth0
cd /mnt/docker-data/compose/arrstack && docker compose up -d
```

After a WireGuard restart, restart the arr containers to re-attach their network namespace:

```bash
cd /mnt/docker-data/compose/arrstack
docker compose restart sabnzbd radarr sonarr bazarr
```

> qBittorrent runs on its own network and does not need to be restarted after a WireGuard restart.

---

## Troubleshooting

### Wildcard certificate not issuing

**Symptom:** Traefik shows certificate errors or uses a self-signed cert.

**Checks:**
1. Verify `CF_DNS_API_TOKEN` in `.env` has `Zone:DNS:Edit` permission for your zone
2. Check Traefik logs: `docker logs traefik 2>&1 | grep -i acme`
3. Confirm `tls.domains[0].main=*.${BASE_DOMAIN}` label is on each router — this is required to request the wildcard cert
4. Check DNS propagation: Traefik uses a 30-second delay before checking (`delayBeforeChecks: 30`)
5. If using staging, the cert will be issued but browsers will show an untrusted cert warning — this is expected

### WireGuard container unhealthy

**Symptom:** WireGuard stays in `unhealthy` state, arr containers do not start.

**Default variant check:**
```bash
docker exec wireguard wg show
# Must show an interface name (e.g. wg0)
```

**PIA variant check:**
```bash
docker logs wireguard
# Look for connection errors or credential failures
```

The healthcheck uses `wg show | grep -q interface` (default) or `ping -c 1 www.privateinternetaccess.com` (PIA). If PIA credentials are wrong, the ping will fail.

### SABnzbd "Access denied" behind reverse proxy

**Symptom:** SABnzbd shows "Access denied - Check hostname in SABnzbd" when accessed via Traefik.

**Fix:** Add the hostname to `host_whitelist` in `sabnzbd.ini`:

```bash
docker compose -f /mnt/docker-data/compose/arrstack/docker-compose.yml stop sabnzbd
SABNZBD_INI="/mnt/docker-data/compose/arrstack/sabnzbd/config/sabnzbd.ini"
sed -i "s/^host_whitelist = .*/& sabnzbd.local.yourdomain.com/" "$SABNZBD_INI"
docker compose -f /mnt/docker-data/compose/arrstack/docker-compose.yml start sabnzbd
```

### Traefik "multiple services" error

**Symptom:** Traefik logs show `service "wireguard" is not configured` or multiple routers competing for the same service.

**Cause:** When multiple routers are defined on a single container (as in the wireguard container for all arr services), each router must explicitly declare its target service via `traefik.http.routers.<name>.service=<name>`.

**Fix:** Ensure each arr router has the `service=` label set, e.g.:

```yaml
- "traefik.http.routers.sabnzbd.service=sabnzbd"
- "traefik.http.services.sabnzbd.loadbalancer.server.port=8080"
```

These labels are already set in the generated `docker-compose.yml`. If you have an older setup without them, add the `service=` labels to each router in `arrstack/docker-compose.yml` and run `docker compose up -d`.

### Suwayomi downloads failing — "No such file or directory"

**Symptom:** Suwayomi shows a download error; logs contain `java.io.IOException: No such file or directory` pointing to `ArchiveProvider.kt`.

**Cause:** Suwayomi writes downloads to `/mnt/docker-data/media/comics/Mangas/mangas/<SourceName>/<MangaTitle>/<Chapter>/`. When this directory is synced from the NAS by the `mediasync` user, the source-named subdirectory (e.g. `Weeb Central (EN)/`) may get `drwxr-x---` permissions — group has read+execute but **no write**. When Suwayomi (running as `pasta`, UID 1000, in the `pasta` group) tries to create a chapter subdirectory, it fails with ENOENT.

**Fix — existing installation:**
```bash
chmod -R g+ws /mnt/docker-data/media/comics/Mangas
```

The `g+w` gives the group write permission; `g+s` (setgid) ensures new subdirectories automatically inherit the group and permissions.

**Prevention:** `proxmox-setup-vms.sh` and `nas-initial-push.sh` both apply this chmod automatically. If you sync mangas from the NAS manually, always run the chmod afterward.

---

### rsync exit 23 — NAS sync fails

**Symptom:** `nas-pull-*.sh` reports `rsync exit 23` for comics or media folders.

**Cause 1 — Synology metadata directories:** `@eaDir` folders synced from NAS to VM. Fixed by adding excludes to rsync options:
```bash
RSYNC_OPTS="-az --update --stats --exclude='@eaDir' --exclude='.*'"
```

**Cause 2 — File permissions:** Files downloaded by Mylar or other containers may have restrictive permissions (e.g. `600`, `----r-----`) that prevent `mediasync` from reading them.

Fix existing files:
```bash
sudo find /mnt/docker-data/media -type f ! -perm -u+r -exec chmod u+r {} \;
sudo find /mnt/docker-data/media -type f ! -perm -g+r -exec chmod g+r {} \;
```

Prevent future issues by ensuring containers have `UMASK=002` in their environment — this ensures new files are created as `664` (group-readable).

---

### Backup management

Daily backups run automatically at 07:00 via cron (`proxmox-backup-docker-files.sh`). The backup includes all compose stacks, `.env` files, and `daemon.json` — but excludes `cache/`, `logs/` directories (regenerable). Max **7 backups** are kept on the Proxmox host; older ones are automatically deleted by cron.

Download backups to your Mac using `proxmox-download-backups.sh` (located in the private repo):

```bash
cd ~/Documents/repositories/proxmox-prod-private
./usefull-scripts/proxmox-download-backups.sh           # download newest backup
./usefull-scripts/proxmox-download-backups.sh --all     # download all missing backups
./usefull-scripts/proxmox-download-backups.sh --list    # show available backups on server
```

> ⚠️ Backups contain secrets (`.env` / tokens / VPN configs) — store them securely and never commit them.

---

### SSH host key warning after VM recreation

When a new VM gets the same IP as a previous one, remove the old key:

```bash
ssh-keygen -R <ip>
```

---

## File Structure

```
proxmox-launcher.sh       # Central menu — start here
proxmox-post-install.sh   # Step 1: Proxmox post-install
proxmox-setup-storage.sh  # Step 2: Format Docker storage disk
proxmox-setup-vms.sh      # Step 3: VM automation setup
proxmox-vm-cleanup.sh     # Maintenance: remove VMs
proxmox-test-docker-vm.sh # Maintenance: test Docker VM
proxmox-set-password.sh   # Maintenance: set VM user password

deploy-stack.sh           # Deploy any Compose stack to the Docker VM with Traefik
deploy.conf               # Your local VM connection config (gitignored)
deploy.conf.example       # Template — copy to deploy.conf and fill in values
test/                     # Local compose files for testing/deploying (gitignored)

# Private scripts (in separate private repo — proxmox-prod-private):
usefull-scripts/
  manage.sh                    # Main menu launcher
  proxmox-download-backups.sh  # Download VM backups from Proxmox host to local Mac
  vm-docker-restart.sh         # Restart individual containers or full stacks (respects depends_on)
  vm-docker-update.sh          # Pull latest images and recreate containers
  vm-update.sh                 # VM apt update + upgrade
rsync/
  nas-pull-media.sh            # NAS pulls new media from VM (run via Synology Task Scheduler)
  nas-pull-books.sh            # NAS pulls books/comics/audiobooks from VM
RenameScripts/
  manga-rename.sh              # Rename Suwayomi CBZ downloads — runs every 30min via VM cron
backups/                       # Local downloaded backups (gitignored)

# Generated by proxmox-setup-vms.sh:
/usr/local/bin/new               # Create new VMs
/opt/vmconfigs/lib.sh            # Shared library
/opt/vmconfigs/*.conf            # VM profiles
/opt/templates/*.template        # Template mappings
/var/lib/vz/snippets/            # Cloud-init snippets

# Generated on the Docker VM by cloud-init:
/mnt/docker-data/compose/homelab/    # Homelab stack
/mnt/docker-data/compose/arrstack/   # Arrstack (VPN + arr apps)
/mnt/docker-data/compose/traefik/    # Traefik config + acme.json
/mnt/docker-data/media/              # Media library
```

---

## Safety Notes

- Destructive operations always require explicit confirmation
- The Docker storage script formats the chosen disk — all data on it will be lost
- Always back up important data before running cleanup scripts
- Review all scripts before execution in production environments
