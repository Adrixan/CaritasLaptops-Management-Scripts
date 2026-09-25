# Caritas Laptops: Installations- und Betriebshandbuch

Dieses Handbuch dokumentiert die vollständige Neuinstallation, Konfiguration, Härtung und laufende Administration der Caritas Laptop-Flotte unter Verwendung der modernen Caritas Management-Suite.

---

## 1. Zentrale Zugangsdaten und Stammdaten

Die folgenden Zugangsdaten gelten standardisiert für alle Laptops der Organisation:

| Bereich | Benutzername / Kennung | Kennwort / PIN | Zweck |
| :--- | :--- | :--- | :--- |
| Windows Administrator | `CaritasAdmin` (oder `Cari Tas`) | `CariUntertasse-STMK-2025!` | Lokale Geräteverwaltung und Wartung |
| Windows Standard-Nutzer | `User` | `Caritas2412!` | Geteiltes Patron-Konto für Klientinnen und Klienten |
| BIOS / UEFI | Administrator | `WirHelfen2025!` bzw. `WirHelfen2025` | Hardwareschutz und Boot-Sperre |
| Microsoft-Konto (Fallback) | `caritas-laptops@outlook.com` | `CariUntertasse-STMK-2025!` | Bei Bedarf für OOBE-Ersteinrichtung |
| Alternative Notfall-Mail | `julia.bretterklieber@caritas-steiermark.at` | s. o. | Sicherheitskontakt des Microsoft-Kontos |
| MS Office 2024 Lizenz | Alle Geräte | `9YQNX-W4TVK-74HXJ-YDFX6-QYM2Q` | Volumenlizenzierung für Word, Excel, PowerPoint |

---

## 2. Hardware-Inventar und Gerätenamen

Jedem Gerät ist anhand seiner eindeutigen Hardware-Seriennummer (im BIOS oder auf der Geräteunterseite lesbar) ein fester Hostname zugewiesen. Die Caritas Management-Suite liest die BIOS-Seriennummer automatisch aus und benennt den Laptop beim Setup oder Härten ohne manuelle Eingabe um:
| Seriennummer | Modell | Zugewiesener Hostname | BIOS Hotkey | Boot-Menü Hotkey |
| :--- | :--- | :--- | :--- | :--- |
| `PF1WVA11` | Lenovo ThinkPad T480 | `Caritas-T480-1` | Enter / F1 | F12 |
| `PF0YG5PW` | Lenovo ThinkPad X1 Carbon | `Caritas-X1-1` | Enter / F1 | F12 |
| `NXEG9EV00105209C977600` | Acer TravelMate / Aspire | `Caritas-Acer-1` | F2 | F12 |
| `NXEG9EV00105209CB17600` | Acer TravelMate / Aspire | `Caritas-Acer-2` | F2 | F12 |
| `NXEG9EV00105209CB47600` | Acer TravelMate / Aspire | `Caritas-Acer-3` | F2 | F12 |
| `NXEG9EV00105209CBB7600` | Acer TravelMate / Aspire | `Caritas-Acer-4` | F2 | F12 |
| `5CG6388SJG` | HP EliteBook / ProBook | `Caritas-HP-1` | Esc / F10 | F9 |
| `5CG6502VZQ` | HP EliteBook / ProBook | `Caritas-HP-2` | Esc / F10 | F9 |

---

## 3. Betriebssystem-Neuinstallation (Windows 11 Pro)

### 3.1 BIOS-Vorbereitung
- Laptop mit dem Stromnetz verbinden.
- Während des Einschaltens die herstellerspezifische Hotkey-Taste (Lenovo: `Enter`, Acer: `F2`, HP: `Esc`) drücken.
- BIOS-Kennwort `WirHelfen2025` eingeben.
- Prüfen, dass der Boot von USB-Medien (`USB Boot`) auf `Enabled` steht.
- Secure Boot aktiviert lassen (für Windows 11 erforderlich).
- Einstellungen mit `F10` speichern und neu starten.

### 3.2 Zero-Touch USB-Installation mit autounattend.xml (Empfohlen)
Für eine vollständig unbegleitete Neuinstallation steht in der Suite die Antwortdatei [`setup/autounattend.xml`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/setup/autounattend.xml) bereit:
- Einen bootfähigen Windows 11 USB-Stick (z. B. via Microsoft Media Creation Tool oder Rufus) erstellen.
- Die Datei [`setup/autounattend.xml`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/setup/autounattend.xml) direkt in das Stammverzeichnis des USB-Sticks kopieren (`D:\autounattend.xml`).
- Den USB-Stick am Ziel-Laptop anstecken und über das Boot-Menü starten (Lenovo: `F12`, Acer: `F12`, HP: `F9`).
- Der gesamte Installationsprozess läuft vollautomatisch ohne Benutzereingriff ab:
- Umgeht Hardware-Voraussetzungen (TPM 2.0, SecureBoot, RAM, CPU-Prüfungen) für ältere Spenden-Laptops.
- Partitioniert die primäre Festplatte nach UEFI/GPT-Standard (EFI, MSR, NTFS).
- Installiert Windows 11 Pro mit Sprach- und Tastaturlayout Deutsch (Österreich, `de-AT`).
- Legt das lokale Administratorkonto `CaritasAdmin` mit Kennwort `CariUntertasse-STMK-2025!` an.
- Umgeht den Microsoft-Konto-Onlinezwang (`BypassNRO`) und unterdrückt alle OOBE-Datenschutzfragen.
- Führt eine automatische Erstanmeldung als `CaritasAdmin` durch. Direkt nach dem Start steht der saubere Desktop bereit.

### 3.3 Manuelle Installation von USB-Medium (Fallback)
Falls ohne Antwortdatei installiert wird:
- Vorbereiteten USB-Installationsstick mit Windows 11 Pro anstecken und starten.
- Sprache: Deutsch (Österreich), Tastatur: Deutsch.
- Bei der Editionswahl **Windows 11 Pro** wählen (digitale Lizenz ist im Mainboard hinterlegt).
- Vorhandene Partitionen auf dem Ziellaufwerk löschen und in den unzugewiesenen Speicherplatz installieren.
- In der Windows-Ersteinrichtung (OOBE) die Option **Für persönliche Verwendung einrichten** wählen.
- Microsoft-Konto `caritas-laptops@outlook.com` mit Kennwort `CariUntertasse-STMK-2025!` verwenden (oder lokales Konto `CaritasAdmin` anlegen).
- Alle Fragen zu Standort, Diagnose und Werbe-ID mit der datenschutzfreundlichsten Option beantworten.
- Angebote zu Microsoft 365, Game Pass und Cloud-Speicher überspringen oder ablehnen.
- Sobald der Windows-Desktop erscheint, mit Schritt 4 fortfahren.

---

## 4. Bereitstellung mit der Caritas Management-Suite

Die gesamte Systemkonfiguration, Software-Installation, Härtung, Benutzeranlage und Taskleisten-Einrichtung erfolgt vollautomatisch über das integrierte Kontrollzentrum.

### 4.1 Herunterladen der aktuellen Suite
- Auf dem neu installierten Laptop den Browser öffnen.
- Die offizielle Release-Seite aufrufen:
  `https://github.com/Adrixan/CaritasLaptops-Management-Scripts/releases/latest`
- Die Datei `CaritasScripts.zip` herunterladen.
- Die ZIP-Datei per Rechtsklick -> **Alle extrahieren...** auf den Desktop des Administrators entpacken (Ziel: `Desktop\CaritasScripts`).

### 4.2 Starten des Kontrollzentrums
- Den extrahierten Ordner `CaritasScripts` öffnen.
- Die Datei [`Caritas-Verwaltung.cmd`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/Caritas-Verwaltung.cmd) per Doppelklick starten.
- Die Windows Benutzerkontensteuerung (UAC) mit **Ja** bestätigen.
- Es öffnet sich das grafische Kontrollzentrum im Caritas Corporate Design:

```
+--------------------------------------------------------------------------+
|  CARITAS LAPTOPS  |  KONTROLLZENTRUM                                     |
+--------------------------------------------------------------------------+
|  [▶ Erst-Einrichtung jetzt starten]                                      |
+--------------------------------------------------------------------------+
```

*(Hinweis: Für reine Konsolenumgebungen steht alternativ [`Caritas-Verwaltung-TUI.cmd`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/Caritas-Verwaltung-TUI.cmd) zur Verfügung.)*

### 4.3 Ausführen der 1-Klick-Erst-Einrichtung
Auf die grüne Hauptschaltfläche klicken:
`[▶ Erst-Einrichtung jetzt starten]`

Den Dialog bestätigen. Das System führt nun fünf vollautomatisierte Phasen durch:

- **Phase 1: Software-Synchronisation & Bereinigung**
  - Installiert alle freigegebenen Standardanwendungen über den Windows Paketmanager (`winget`).
  - Entfernt Microsoft Werbe-Apps (News, Wetter, Solitaire, Xbox, Zune).
  - Deinstalliert Discord und entfernt den Discord System Helper mitsamt Squirrel-Hintergrunddiensten vollständig.
- **Phase 2: Windows Update & Treiber-Synchronisation**
  - Sucht online nach aktuellen Windows-Sicherheitsupdates.
  - Installiert herstellerspezifische OEM-Firmware und Treiber für Audio, WLAN, Chipsatz und Grafik (Intel, Realtek, Lenovo, HP, Acer).
- **Phase 3: System-Härtung & Energie-Konfiguration**
  - Konfiguriert kontinuierliche Verfügbarkeit: Deaktiviert Standby-Timeout, Ruhezustand und Display-Abschaltung bei Netz- und Akkubetrieb.
  - Schaltet den Ruhezustand (`powercfg /hibernate off`) ab, um SSD-Speicherplatz freizugeben.
  - Aktiviert Windows Defender PUA-Schutz (Potenziell unerwünschte Anwendungen) und Echtzeitschutz.
  - Deaktiviert unsichere Legacy-Protokolle: SMBv1, LLMNR und NetBIOS über TCP/IP.
  - Setzt strikte Datenschutz-Gruppenrichtlinien für Standort, Telemetrie und Eingabepersonalisierung.
- **Phase 4: Standard-Programme, Suchmaschine & Werbeblocker**
  - Setzt Mozilla Firefox als Standardbrowser und PDF-Betrachter, VLC Media Player für alle Medienformate, Microsoft Office / LibreOffice für Dokumente sowie 7-Zip für Archive.
  - Erzwingt Brave Search (`https://search.brave.com`) als unveränderliche Startseite, Suchmaschine und Neuer-Tab-Seite auf Firefox, Chrome und Edge.
  - Installiert die uBlock Origin Erweiterung mit kuratierten Filterlisten (uBlock, EasyList, EasyPrivacy, Malware-Schutz, EasyList Germany sowie Cookie-Banner-Unterdrückung).
  - Unterdrückt Firefox-Willkommensdialoge (`about:welcome`), Nutzungsbedingungen (`SkipTermsOfUse`) und Autostart beim Login.
  - Konfiguriert das einheitliche Windows 11 Taskleisten-Layout: Heftet Datei-Explorer, Firefox, Word, Excel und PowerPoint an; entfernt Microsoft Edge, Microsoft Store und Outlook.
- **Phase 5: Benutzerkonto 'User' & Wartungstasks**
  - Erstellt das Standard-Gastkonto `User` mit Kennwort `Caritas2412!`.
  - Aktiviert die automatische Anmeldung (Autologon) auf der Windows-Konsole beim Systemstart.
  - Lässt `ForceAutoLogon` deaktiviert, sodass manuelles Sperren (`Win+L`) zuverlässig gesperrt bleibt.
  - Isoliert das Konto: Sperrt Microsoft-Konto-Verknüpfung (`NoConnectedUser = 3`) und deaktiviert OneDrive-Hintergrundsynchronisation.
  - Platziert die Desktop-Verknüpfung `Sitzung zurücksetzen.lnk` auf dem Public-Desktop.
  - Richtet Windows Storage Sense und monatliche Bereinigungstasks ein.

Nach Abschluss der Routine ist das Gerät technisch vollständig konfiguriert.

---

## 5. Microsoft Office Aktivierung

Die Microsoft Office 2024 LTSC Installation wird über den Standard-Volumenlizenzschlüssel aktiviert.

### Automatische Aktivierung durch die Caritas Management-Suite (Standard)
Die Caritas Management-Suite führt die Aktivierung im Rahmen der Erst-Einrichtung ([`setup/Install-CaritasEnvironment.ps1`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/setup/Install-CaritasEnvironment.ps1)), der Software-Synchronisation ([`scripts/Sync-CaritasSoftware.ps1`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/scripts/Sync-CaritasSoftware.ps1)) sowie der Standardanwendungs-Konfiguration ([`scripts/Configure-CaritasDefaults.ps1`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/scripts/Configure-CaritasDefaults.ps1)) vollautomatisch im Hintergrund durch:
- Prüft über das Office Software Protection Platform Skript (`ospp.vbs`), ob bereits eine gültige Lizenz vorliegt.
- Hinterlegt bei Bedarf den MAK-Volumenlizenzschlüssel `9YQNX-W4TVK-74HXJ-YDFX6-QYM2Q`.
- Löst die Online-Aktivierung bei Microsoft aus und protokolliert den Erfolg.

### Manuelle Aktivierung (Fallback)
Falls eine manuelle Aktivierung gewünscht ist:
- **Über die Kommandozeile:**
  ```cmd
  cscript.exe "%ProgramFiles%\Microsoft Office\Office16\ospp.vbs" /inpkey:9YQNX-W4TVK-74HXJ-YDFX6-QYM2Q
  cscript.exe "%ProgramFiles%\Microsoft Office\Office16\ospp.vbs" /act
  ```
- **Über die Programmoberfläche:**
  Word starten, auf **Konto** -> **Product Key ändern** klicken, den Lizenzschlüssel `9YQNX-W4TVK-74HXJ-YDFX6-QYM2Q` eingeben und bestätigen.

---

## 6. TeamViewer Fernwartung

Für den Remote-Support über das Internet ist TeamViewer für den unbeaufsichtigten Zugriff vorkonfiguriert.

### Automatische Vorbereitung durch die Management-Suite (Standard)
Die Caritas Management-Suite konfiguriert TeamViewer bei der Erst-Einrichtung und beim System-Hardening ([`scripts/Configure-CaritasHardening.ps1`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/scripts/Configure-CaritasHardening.ps1)) direkt in der Registrierung:
- Schaltet die Windows-Authentifizierung für alle Benutzer frei (`Security_WinLogin = 2`). Support-Mitarbeitende können sich mit den Windows-Administrator-Zugangsdaten (`CaritasAdmin` / `CariUntertasse-STMK-2025!`) direkt aufschalten.
- Aktiviert den automatischen Systemstart mit Windows (`Always_Online = 1` und `Autostart = 1`).
- Setzt den Windows-Dienst `TeamViewer` auf den Starttyp `Automatisch` und stellt sicher, dass der Dienst aktiv läuft.

### Manuelle Fernwartungs-Optionen (Fallback)
- TeamViewer über das Startmenü als Administrator (`CaritasAdmin`) starten.
- In den Einstellungen unter **Sicherheit** prüfen, dass **Windows-Authentifizierung** auf **Für alle Benutzer zulassen** steht.
- Bei Bedarf die TeamViewer-ID im Firmenkonto zuweisen.

---

## 7. Laufender Betrieb & Wartung

### 7.1 Sitzung von 'User' zurücksetzen (Clean Slate)
Klientinnen und Klienten hinterlassen während der Nutzung persönliche Dokumente, Browser-Verläufe und Downloads. Das Zurücksetzen erfolgt strikt nach Bedarf (On-Demand):

- **Durch Klienten oder Betreuungspersonal:**
  Auf dem Desktop des Kontos `User` befindet sich die Verknüpfung:
  `[Sitzung zurücksetzen]`
  Ein Doppelklick stößt die Bereinigung sofort ohne Administrator-Kennwort über eine erhöhte System-Aufgabe an.
- **Durch Administrator über das Kontrollzentrum:**
  In `Caritas-Verwaltung.cmd` die Aktionskarte **Benutzerkonto 'User' zurücksetzen** anklicken.

Der Bereinigungsprozess umfasst sechs Stufen:
- Trennung aktiver Sitzungen und Abmeldung des Benutzers.
- Vollständige Löschung des Profilverzeichnisses `C:\Users\User` via CIM/WMI `Win32_UserProfile.Delete()`.
- Bereinigung verwaister Registrierungsschlüssel (`ProfileList`).
- Neuanlage des Benutzerkontos mit Kennwort `Caritas2412!` und erneute Autologon-Konfiguration.
- Sicherstellung, dass Firefox-Autostart-Einträge und Discord-Reste gelöscht bleiben.
- Beim nächsten Start wird das Profil blitzsauber aus der Vorlage `C:\Users\Default` mit dem korrekten Taskleisten-Layout neu erzeugt.

### 7.2 In-Place-Updates der Management-Suite
Das Kontrollzentrum prüft bei jedem Start automatisch auf GitHub nach neuen Skriptversionen:
- Liegt auf GitHub eine neuere Release-Version vor, erscheint im Kopfbereich der Oberfläche die Schaltfläche:
  `[⚡ Update auf vX.X.X installieren]`
- Ein Klick lädt die neue Version automatisch herunter, entpackt sie direkt im aktuellen Verzeichnis und startet die Oberfläche neu.

---

## 8. Protokolldateien und Fehlersuche

Alle administrativen Aktionen protokollieren ausführlich in den Unterordner `logs\` innerhalb des Skriptordners:

| Protokolldatei | Zweck |
| :--- | :--- |
| `logs\SoftwareSync.log` | Protokoll der winget-Paketinstallationen und Windows-Updates |
| `logs\Hardening.log` | Protokoll der Energieeinstellungen, Defender- und Netzwerkhärtung |
| `logs\Defaults.log` | Protokoll der Dateizuordnungen, Firefox-Richtlinien und Taskleisten-Pins |
| `logs\UserReset.log` | Protokoll der Profilbereinigung und Kennwort-Synchronisation |
| `logs\MaintenancePrivacy.log` | Protokoll der Browser-Datenschutzrichtlinien und USB-Sperren |
