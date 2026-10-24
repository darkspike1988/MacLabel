# MacLabel.app – Design (Phase 2)

Stand: 24.10.2026 · Status: autonom erstellt (Auftraggeber hat Entscheidungen delegiert: „ich überlasse dir alles“, „mach das app selbst“). Baut auf `2026-10-23-maclabel-design.md` (Hauptspec, insbesondere §2 Ziele, §3 Rahmen, §4.4 Bedienung, §4.8 Entscheidungen) und `docs/porting-plan.md` (Phase 2) auf. Bei Widerspruch gilt dieses Dokument für die App.

## 1. Zweck

Eine einheitliche, native macOS-App, mit der man **in unter 10 Sekunden ohne Einstellungen** das passende Etikett druckt. Sie ersetzt DYMO Connect im Alltag. Der Druckkern (MacLabelKit) ist fertig und auf `main`. Diese Phase baut die Oberfläche, die Systemintegration und die Auslieferung als App.

## 2. Ziele (Phase 2)

1. **Hauptfenster** nach Hauptspec §4.4:
   - Rollen-Chip mit Suche, Druckerstatus, Live-Vorschau (exakt das 1-Bit-Raster), Layout-Segmente (Text, Adresse, Barcode, QR, Bild), Inhaltseditor, Kopien und „Drucken“ (⌘P).
   - „Mehr“ (Inspector-Bereich) mit Dichte, Druckmodus, Drehung, Zähler, CSV-Serie und Endlos-Länge.
2. **Erst-Start und neuer Drucker:** einmaliges Sheet „Welche Rolle ist eingelegt?“ (Hauptspec §4.8.2), danach Rolle pro Drucker gemerkt (`RollPreferences`).
3. **Druckerstatus live:**
   - Abfrage alle 5 s, nur solange ein MacLabel-Fenster oder das Menüleisten-Panel sichtbar ist (Hauptspec §4.8.4).
   - „Belegt“ wird ohne Fehlerdialog angezeigt, danach 15 s Pause.
   - Während eines Drucks wird nicht gepollt (der Druckdienst prüft selbst).
4. **Vorschau = Druck:**
   - Das Vorschaubild ist `RenderResult.preview` desselben Renderaufrufs, der gedruckt würde.
   - Etikettenkontur und Vorschubpfeil werden darüber gezeichnet.
   - Überlänge erscheint als roter Rahmen mit Text. Drucken fragt dann nach („Trotzdem drucken?“).
5. **Adresse aus Kontakte:** Kontaktauswahl über den System-Picker (`CNContactPicker`); Formatierung mit `CNPostalAddressFormatter`. Keine Kontakte-Berechtigung nötig, weil der Picker sie selbst vermittelt.
6. **Bild:** Drag & Drop oder „Bild wählen…“; Schalter „Fotos rastern“ (Dithering).
7. **Serien:** Kopien, Zähler (`{n}`, Start, Stellen), CSV per Drag & Drop oder Dateiauswahl mit Platzhaltern `{Spalte}`. Spaltennamen werden zum Einfügen angeboten. Die Vorschau zeigt das erste Etikett, dazu „1 von N“ mit Blättern.
8. **Menüleisten-Schnelldruck** (`MenuBarExtra`, Fensterstil): Textfeld, Statuszeile, Rolle (nur Anzeige plus „ändern“ öffnet das Hauptfenster), Drucken. Nutzt die zuletzt verwendete Rolle des Druckers.
9. **Dienst „Mit MacLabel drucken“** (NSServices, Text): öffnet das Hauptfenster mit dem markierten Text im Text-Layout.
10. **App Intents (Kurzbefehle/Siri/Spotlight):** „Etikett drucken“ (Text, Kopien; Rolle optional, sonst die gemerkte; ohne gemerkte Rolle Fehler mit Hinweis) und „Druckerstatus abfragen“.
11. **Einheitliche App:**
   - Das CLI `maclabel` liegt im Bundle unter `Contents/Helpers/maclabel` (geändert: Ruling A21, Namenskollision auf APFS – `MacLabel` und `maclabel` in `Contents/MacOS` sind auf einem Volume ohne Groß-/Kleinschreibung dieselbe Datei), mit seinen Ressourcen-Bundles in `Contents/Resources`.
   - Der Menüpunkt „Kommandozeilenwerkzeug installieren…“ zeigt den Symlink-Befehl zum Kopieren an. MacLabel selbst schreibt nichts außerhalb des Containers.
12. **Einstellungen:** Standarddrucker (bei mehreren), „In der Menüleiste anzeigen“, Statusabfrage an/aus, CLI-Hinweis.
13. **Fehler in Klartext** (de/en) aus `PrintError`, `RenderError`, `BatchError`, `CSVError`, `TransportError`. Abbruch während des Drucks mit Fortschritt („Etikett 3 von 10“) und Abbrechen-Knopf.
14. **Barrierefreiheit:** VoiceOver-Beschriftungen für Status, Rolle, Vorschau (Text des Etiketts) und Druckknopf; Tastaturbedienung (⌘P drucken, ⌘L Rolle wählen, ⌘1…⌘5 Layout).
15. **Sprachen:** Deutsch und Englisch über einen String Catalog im App-Kern.

## 3. Nicht-Ziele (Phase 2)

- Import von `.xlsx` und `.dymo` sowie Datum/Uhrzeit-Platzhalter. Das kommt in Phase 2b, eigener Plan.
- Freier Editor (Phase 4), LabelWriter 550 (Phase 3).
- Notarisierung, Developer-ID-Signatur, Sparkle und der Homebrew-Cask. Dafür braucht es einen Apple-Developer-Account des Auftraggebers, deshalb folgt das in einem eigenen Schritt nach seiner Freigabe. In Phase 2 wird ad-hoc signiert („Sign to Run Locally“).
- Druck über den Systemdruckdialog oder CUPS.

## 4. Anti-Ziele

- Ein Fenster voller Einstellungen. Alles außer Rolle, Inhalt, Kopien und Drucken liegt hinter „Mehr“.
- Dialogketten wie bei DYMO. Es gibt höchstens ein Sheet: Rollenwahl beim Erststart.
- Jede Netzwerkverbindung. Die App läuft in der Sandbox **ohne** `com.apple.security.network.client`/`.server`.
- Statusabfragen im Hintergrund oder eine Dauerverbindung zum Drucker.
- Eine Vorschau, die etwas anderes zeigt als den Druck.

## 5. Rahmen

- macOS 26+, Swift 6.4 (Swift-6-Sprachmodus), SwiftUI, Observation (`@Observable`), Xcode 27.1.
- Keine neuen Drittanbieter-Abhängigkeiten zur Laufzeit. XcodeGen (≥ 2.46) ist ein reines Entwicklungswerkzeug und bereits installiert.
- Bundle-ID `io.github.darkspike1988.maclabel`, App-Name „MacLabel“, Kategorie Productivity.
- Entitlements der App:
  - `com.apple.security.app-sandbox`
  - `com.apple.security.device.usb`
  - `com.apple.security.files.user-selected.read-only` (CSV, Bilder)
  - `com.apple.security.temporary-exception.iokit-user-client-class` = `[AppleUSBHostFrameworkInterfaceClient]`. Am echten LW450 verifiziert: ohne diese Ausnahme scheitert IOUSBHost in der Sandbox (siehe `docs/research/lw450-protocol.md` §12).
  - keine Netzwerk-Entitlements
- Das CLI ist nicht sandboxed und hat keinen Netzwerkcode.
- `Info.plist`: `NSContactsUsageDescription` (de/en, nur für den Fall, dass der Picker Zugriff braucht), `NSServices`-Eintrag für den Dienst.
- Nicht drucken ohne Auftraggeber: Tests und Entwicklung schicken nur Status- und Versionsabfragen an den echten Drucker (Hauptspec §4.8.1).

## 6. Entscheidungen (Claude, delegiert)

### 6.1 Projektstruktur
- **Neues Library-Target `MacLabelApp`** im bestehenden `Package.swift`: SwiftUI-Views, View-Models und Dienste der App. Hängt von `MacLabelKit` ab und ist mit `swift test` testbar (Target `MacLabelAppTests`).
- **`App/project.yml` (XcodeGen)** erzeugt `App/MacLabel.xcodeproj`. Die erzeugte Datei wird **nicht** eingecheckt; `.gitignore` deckt sie ab.
  - Target `MacLabel` (macOS-App): nur `@main`-App-Struct, Scenes, App Intents, Services-Provider, Info.plist und Entitlements. Hängt vom lokalen Paket ab (Produkt `MacLabelApp`).
  - Target `maclabel-cli` (Command Line Tool): kompiliert `Sources/maclabel` mit dem Paket-Produkt `MacLabelKit` und ArgumentParser.
  - Eine Copy-Files-Phase legt das Binary nach `Contents/Helpers/maclabel` (geändert: Ruling A21, Namenskollision auf APFS – `MacLabel` und `maclabel` in `Contents/MacOS` sind auf einem Volume ohne Groß-/Kleinschreibung dieselbe Datei) und die Ressourcen-Bundles nach `Contents/Resources`.
  - Ein Build-Skript `scripts/build-app.sh` erzeugt das Projekt, baut Release mit `xcodebuild` und signiert ad-hoc. Ergebnis: `build/MacLabel.app`.
- App Intents liegen im App-Target, weil Xcode dort die Metadaten erzeugt. Ihre Logik ruft `MacLabelApp`-Dienste auf.

### 6.2 Zustandsmodell
- `AppModel` (`@MainActor @Observable`, eine Instanz, per Environment):
  - Druckerliste
  - gewählter Drucker
  - Status
  - Rolle
  - Dokument (`LabelDocument`)
  - Vorschau
  - Druckzustand
- `LabelDocument` (Wertetyp):
  - Layout (`.text`, `.address`, `.barcode`, `.qr`, `.image`)
  - Felder je Layout
  - Kopien, Zähler, CSV-Tabelle, Dichte/Modus/Drehung (optional = automatisch), Endlos-Länge
  - Abbildung auf `[LabelContent]` über `LabelBatch.expand`
- **Vorschau:** Bei jeder Dokumentänderung wird auf einem Hintergrund-Task neu gerendert, mit 100 ms Debounce. Ein neuer Auftrag bricht den laufenden ab. Ergebnis: `[RenderResult]` für die Seriennavigation, höchstens die ersten 50 Etiketten; danach nur noch die Anzahl.
- **`PrinterMonitor`** pollt den Status nach 3.: Timer-Task, der beim Verschwinden aller Fenster oder Panels stoppt (Scene-Phase plus Sichtbarkeitszählung). Während eines Drucks pausiert er.
- **`PrintController`**: startet `PrintService.print` mit eigener `USBPrinterConnection`, leitet den Fortschritt an die UI weiter, ermöglicht Abbrechen (Task-Cancel) und merkt sich danach die Rolle.
- **Rollenwahl:** Das Suchfeld nutzt `MediaCatalog.search`. Treffer gleicher physischer Größe werden zusammengefasst angezeigt (Standard zuerst), wie Ruling 27 im CLI.

### 6.3 Layouts → Inhalte
| Layout | Felder | `LabelContent` |
|---|---|---|
| Text | Text (mehrzeilig), Fett, Ausrichtung | `.text` |
| Adresse | Text (mehrzeilig, aus Kontakt befüllbar), Ausrichtung immer links | `.text` (leading) |
| Barcode | Symbologie, Wert, Klartext an/aus | `.barcode` |
| QR | Art (Text/URL/WLAN/Kontakt), Felder je Art, Beschriftung | `.qr` (Payload aus Art: WLAN `WIFI:T:WPA;S:…;P:…;;`, Kontakt vCard 3.0) |
| Bild | Bild, Rastern an/aus | `.image` |

### 6.4 Visuelle Gestaltung
- Natives macOS 26: `NavigationSplitView` ist nicht nötig. Das Fenster besteht aus einem `HSplitView`-artigen Layout: Inhaltseditor links (Formular), Vorschau rechts groß. Darüber eine Toolbar mit Rollen-Chip und Status, darunter die Druckleiste. „Mehr“ öffnet den `.inspector`.
- Die Vorschau zeigt das Etikett in Lesehaltung auf hellem „Papier“ mit Eckenradius der Rolle und einem dezenten Schatten, dazu einen Vorschubpfeil am Rand. Im Dunkelmodus bleibt das Etikett weiß, weil es Papier darstellt.
- Systemfarben, SF Symbols, keine eigenen Skins. Mindestfenstergröße 720 × 460.

### 6.5 Entscheidungen nach dem Builder-Check (Claude, delegiert)
1. **Sandbox bleibt.** Sie ist per Spike am echten Gerät verifiziert (§5). Plan B, falls sie in einer späteren macOS-Version bricht: Die App druckt über das eingebettete, nicht sandboxed CLI als Hilfsprozess. Das ist in Phase 2 nicht gebaut, nur notiert.
2. **Testbarkeit ohne Hardware:**
   - Nur in DEBUG-Builds ersetzt die Umgebungsvariable `MACLABEL_FAKE_PRINTER=<Dateipfad>` den USB-Transport durch `FileTransport` und meldet einen simulierten LabelWriter 450.
   - Release-Builds enthalten diesen Haken nicht (`#if DEBUG`).
   - Der echte Drucker bekommt in der Entwicklung nur Status- und Versionsabfragen. Echte Drucke aus der App nur nach Freigabe durch den Auftraggeber.
3. **Gemerkte Rolle:** App (Sandbox-Container) und CLI (`~/Library/Preferences`) haben getrennte Speicher. Akzeptiert: Der Menüpunkt zum CLI-Install weist darauf hin. Keine App Group, weil die ad-hoc signiert unzuverlässig ist.
4. **Druck ohne Fenster:** Ein UI-unabhängiger `LabelPrinter`-Dienst (actor) bündelt Druckerwahl, Rolle, Rendern und Drucken. `AppModel`, Menüleiste und Intents nutzen ihn.
   - Intent „Etikett drucken“ läuft ohne App-Fenster (`openAppWhenRun = false`). Bei fehlender Rolle, Überlänge, belegtem oder nicht bereitem Drucker bricht er mit Klartextfehler ab. Er fragt nicht nach.
   - Menüleiste: Überlänge blockiert den Druck und zeigt „Text zu lang – im Fenster öffnen“ (öffnet das Hauptfenster mit dem Text).
5. **Abbrechen:** Nach dem Abbrechen zeigt die UI: „Abgebrochen nach N von M Etiketten. Ggf. Vorschubtaste drücken, um ein angefangenes Etikett auszugeben.“
6. **CLI im Bundle:**
   - Das Xcode-Target `maclabel-cli` kompiliert `Sources/maclabel` erneut. Die Ressourcen (`media.json`, Strings) lädt das CLI nicht über `Bundle.module`, sondern über einen eigenen Lookup in `LabelMedia`/`MacLabelKit`.
   - Reihenfolge des Lookups: 1. `Bundle.module`, falls vorhanden. 2. `<echter Pfad des Executables, Symlinks aufgelöst>/../Resources/<Bundle-Name>.bundle`. 3. Dasselbe neben dem Executable.
   - Muss im Plan per Test verifiziert werden: `maclabel rolls search 32x57` über einen Symlink auf `MacLabel.app/Contents/Helpers/maclabel` (geändert: Ruling A21).
   - Das CLI wird separat und ohne Sandbox-Entitlements signiert (innen nach außen).
7. **CSV und Bilder** werden nicht über Neustarts gemerkt (keine Security-Scoped Bookmarks).
8. **Lokalisierung:** `MacLabelApp` bekommt einen eigenen String Catalog und nutzt denselben Sprachwahl-Mechanismus wie `MacLabelKit` (`localizedBundle(preferred:)`).
9. **Dienst und Intents** sind nur manuell prüfbar (App muss unter `/Applications` liegen). Das Build-Skript bietet `--install` an, um nach `~/Applications` zu kopieren und `pbs -update` aufzurufen.
10. **`Package.swift`** bekommt das Produkt `MacLabelApp`. Die erste Xcode-Auflösung von ArgumentParser darf das Netz nutzen (Build-Zeit, nicht Laufzeit).

## 7. Dem Umsetzer überlassen
- Konkrete View-Hierarchie, Animationen, SF-Symbol-Wahl, Formulierungen innerhalb der genannten Bedeutung.
- Debounce- und Abbruch-Mechanik im Detail, solange die Werte aus §6.2 gelten.
- Wie die Sichtbarkeit von Fenster und Panel gezählt wird.

## 8. Offene Punkte
- Echter Testdruck aus der App erst nach dem CLI-Testdruck des Auftraggebers.
- Signatur und Notarisierung (Developer-ID) nach Freigabe durch den Auftraggeber.
