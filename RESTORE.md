# Restore Handleiding — Proxmox Homelab

> Gebruik deze handleiding bij een volledige herinstallatie van de Proxmox host en/of Docker VM.

---

## Voorbereiding (doe dit VOOR een noodgeval)

Bewaar de volgende bestanden veilig buiten de server (bijv. op je Mac of in een password manager):

| Bestand | Locatie | Waarvoor |
|---|---|---|
| `proxmox_vm_key` + `proxmox_vm_key.pub` | `~/.ssh/` op je Mac | SSH toegang tot Docker VM |
| `nas_mediasync_key` | `~/.ssh/` op NAS | rsync NAS ↔ VM |
| Cloudflare API token | Password manager | Traefik DNS challenge |
| Tailscale auth key | Tailscale dashboard | VPN tunnel |

**Backups worden automatisch dagelijks om 07:00 gemaakt** en staan op de Proxmox host onder `/root/backups/`. Download regelmatig de meest recente backup naar je Mac:

```bash
scp root@192.168.187.48:/root/backups/docker-vm-backup-<datum>.zip .
```

---

## Herstelstappen

### Stap 1 — Proxmox herinstalleren

1. Installeer Proxmox VE via de officiële ISO op [proxmox.com](https://www.proxmox.com/en/downloads)
2. Stel het IP in op `192.168.187.48` tijdens de installatie
3. Log in als root via SSH of de console

### Stap 2 — Scripts installeren

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/xthephreakx/proxmox-homelab-automation/main/install.sh)"
```

Dit downloadt alle scripts naar `/opt/proxmox-setup/` en start de launcher.

### Stap 3 — Proxmox basis configureren

Draai via de launcher (of direct):

```bash
bash /opt/proxmox-setup/proxmox-post-install.sh   # Updates, repos, basis instellingen
bash /opt/proxmox-setup/proxmox-setup-storage.sh  # Storage disk koppelen
```

### Stap 4 — SSH key herstellen of opnieuw aanmaken

**Optie A — Bestaande key herstellen (aanbevolen):**

```bash
# Kopieer vanaf je Mac naar Proxmox host
scp ~/.ssh/proxmox_vm_key root@192.168.187.48:/root/.ssh/
scp ~/.ssh/proxmox_vm_key.pub root@192.168.187.48:/root/.ssh/
chmod 600 /root/.ssh/proxmox_vm_key
```

**Optie B — Nieuwe key aanmaken:**

```bash
ssh-keygen -t ed25519 -f /root/.ssh/proxmox_vm_key -C "proxmox-to-dockervm" -N ""
```

> Na het aanmaken van een nieuwe VM (Stap 5) wordt de public key automatisch geïnjecteerd via cloud-init.

### Stap 5 — Docker VM aanmaken

```bash
bash /opt/proxmox-setup/proxmox-setup-vms.sh
```

Kies profiel `ubuntu-large` (32GB RAM, 100G disk). Wacht tot de VM is gestart en de guest agent actief is (~2 minuten).

### Stap 6 — Docker VM backup terugzetten

Zorg dat de backup op de Proxmox host staat:

```bash
ls /root/backups/
# Indien niet aanwezig, kopieer van je Mac:
scp docker-vm-backup-<datum>.zip root@192.168.187.48:/root/backups/
```

Draai de restore:

```bash
bash /opt/proxmox-setup/proxmox-restore-docker-files.sh
```

Kies de gewenste backup en kies **ja** bij "Stacks herstarten?" als het gevraagd wordt.

### Stap 7 — Post-restore script draaien

Dit script regelt alle overgebleven handmatige stappen automatisch:

```bash
bash /opt/proxmox-setup/proxmox-post-restore.sh
```

Het script doet automatisch:
- ✓ Docker `proxy` netwerk aanmaken op de VM
- ✓ Bestandsrechten herstellen op de media mappen
- ✓ Alle compose stacks opstarten
- ✓ Auto-launcher toevoegen aan `.bashrc`
- ✓ Dagelijkse backup cron instellen (07:00, max 10 backups)

### Stap 8 — NAS rsync scripts instellen

Kopieer de scripts handmatig naar de NAS:

```bash
# Vanuit je Mac, in de repo map:
scp usefull-scripts/rsync/nas-pull-media.sh   admin@<nas-ip>:/volume1/scripts/
scp usefull-scripts/rsync/nas-pull-books.sh   admin@<nas-ip>:/volume1/scripts/
scp usefull-scripts/rsync/nas-initial-push.sh admin@<nas-ip>:/volume1/scripts/
```

SSH key aanmaken voor NAS ↔ VM sync:

```bash
bash usefull-scripts/rsync/nas-keygen.sh
```

Stel de scripts opnieuw in via de **Synology Task Scheduler**:
- `nas-pull-media.sh` → elke 30 minuten
- `nas-pull-books.sh` → elk uur

### Stap 9 — Verificatie

Controleer of alles werkt:

| Test | URL / Commando |
|---|---|
| Traefik dashboard | https://traefik.local.spallitta.nl |
| Dockge | https://dockge.local.spallitta.nl |
| Portainer | https://portainer.local.spallitta.nl |
| Filebrowser | https://filebrowser.local.spallitta.nl |
| Containers status | `sudo docker ps` op de VM |

```bash
# Snelle check via de VM update tool (vanuit je Mac):
bash usefull-scripts/vm-update.sh
```

---

## Tijdsinschatting

| Stap | Geschatte tijd |
|---|---|
| Proxmox installatie | 15-20 min |
| Scripts + configuratie | 10 min |
| VM aanmaken + opstarten | 5-10 min |
| Backup terugzetten | 5-10 min |
| Post-restore + verificatie | 5 min |
| **Totaal** | **~45-60 minuten** |

---

## Troubleshooting

**Containers starten niet op:**
```bash
# Proxy netwerk ontbreekt?
sudo docker network create proxy
# Start stacks opnieuw
cd /mnt/docker-data/compose/<stacknaam> && sudo docker compose up -d
```

**Traefik geeft certificaat fouten:**
- Controleer of `CF_DNS_API_TOKEN` in de `.env` file van de traefik stack correct is
- Verwijder `/mnt/docker-data/compose/traefik/acme.json` en herstart Traefik om nieuwe certificaten aan te vragen

**SSH verbinding geweigerd naar VM:**
```bash
# Public key toevoegen aan VM
ssh-copy-id -i /root/.ssh/proxmox_vm_key.pub pasta@<vm-ip>
```

**Bestandsrechten fout op media:**
```bash
ssh pasta@192.168.187.200
sudo chown -R mediasync:pasta /mnt/docker-data/media
sudo chmod -R u+rwX /mnt/docker-data/media
```
