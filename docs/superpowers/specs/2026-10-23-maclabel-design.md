# MacLabel – Design

Stand: 23.10.2026 · Status: Entwurf, autonom erstellt (der Auftraggeber hat alle Entscheidungen an Claude übergeben)

## 1. Worum es geht

MacLabel ist eine native macOS-App (Swift/SwiftUI) für DYMO-LabelWriter-Etikettendrucker. Sie ersetzt „DYMO Connect“ für den Alltag.

**Warum:** DYMO Connect (v1.6.3.9) ist eine portierte .NET-Windows-App. Sie bringt 164 MB, einen root-Daemon, einen lokalen Webserver, Cloud-SDKs und Analytics mit und wirkt wie „Windows Vista“. Der LabelWriter 450 wird dort nur über einen alten CUPS-Treiber angesprochen, ohne Status und ohne Rückmeldung. Auslöser war ein konkretes Erlebnis: Für die Rolle **S0722540 (LW Vielzweck 32 × 57 mm)** hat es „ewig gedauert, die korrekte Einstellung zu finden“, mit mehreren Fehldrucken (Ausrichtung quer statt längs). Die Ursache lässt sich in DYMOs eigenen Daten nachweisen: Für dasselbe physische Etikett gibt es zwei Papiereinträge (`30334`, Portrait, und `11354`, Landscape) mit gegensätzlicher Default-Ausrichtung (siehe `docs/research/dymo-connect-features.md`).

**Leitsatz des Auftraggebers:** *„Unter 10 Sekunden ohne viele Einstellungen passende Labels drucken.“*

**Zielgruppe:** Alle Mac-Nutzer mit DYMO-LabelWriter. Verteilt wird MacLabel zuerst über Homebrew, später als signierte und notarisierte App.

## 2. Ziele, Nicht-Ziele, Anti-Ziele

### Ziele (v1)
1. **10-Sekunden-Druck:** App öffnen (oder Menüleiste/Dienst/CLI), Text tippen oder einfügen, ⌘P. Rolle, Ausrichtung, Schriftgröße und Druckmodus wählt die App selbst.
2. **Rolle per Packungsnummer finden:** Eingabe von `S0722540`, `11354`, `99012`, „32x57“ oder „Adresse“ liefert die richtige Rolle. Die App merkt sich die zuletzt benutzte Rolle pro Drucker.
3. **WYSIWYG-Vorschau:** Die Vorschau ist exakt das 1-Bit-Raster, das gedruckt wird, mit Etikettenkontur und einem Pfeil für die Vorschubrichtung. Was im Vorschaubild steht, kommt so aus dem Drucker.
4. **Direkter USB-Druck ohne DYMO-Software:** Ein eigener Protokoll-Encoder pro Druckerfamilie. Läuft auch, wenn DYMO Connect bzw. die DYMO-Treiber nicht installiert sind.
5. **Echter Druckerstatus:** Bereit, kein Papier, Stau oder Fehler wird live in Klartext angezeigt, ebenso Modell und Firmware (ESC V).
6. **Mehr Modelle als der 450:** Die ganze „LW-Classic“-Familie (300er-Serie, 400/400 Turbo/Twin Turbo, 4XL, 450/450 Turbo/450 Twin Turbo/450 DUO-Labelseite, SE450) wird in v1 per Protokoll unterstützt. Getestet ist am echten Gerät nur der 450.
7. **Inhalte v1:** Text (mehrzeilig, Auto-Fit), Adresse (aus Apple Kontakte), Barcode (Code 128, EAN-13, EAN-8, UPC-A, Code 39, ITF-14), QR-Code (Text/URL/WLAN/vCard), Bild (Drag & Drop, Schwellwert oder Dithering), Datum/Uhrzeit-Platzhalter, Zähler für Serien.
8. **Serien:** n Kopien, Zähler (z. B. „Box 1…20“), CSV-Zeilen als Etiketten (Spalte → Platzhalter).
9. **Schnellwege:** Menüleisten-Extra („Schnelldruck“), macOS-Dienst „Als Etikett drucken“ für markierten Text, App Intents (Kurzbefehle/Siri/Spotlight), CLI `maclabel`.
10. **Sprachen:** Deutsch und Englisch.

### Ausbaustufen nach v1 (geplant, nicht v1)
- **LW-V2-Familie** (550, 550 Turbo, 5XL, 550 Twin): eigener Encoder (Job-ID, Label-Block, LZ4), 32-Byte-Status, NFC-Rollenerkennung. Der Protokollrahmen ist in v1 schon vorgesehen, die Implementierung folgt, sobald ein Testgerät verfügbar ist.
- Import von `.dymo`-Dateien (DYMO-XML), Vorlagenbibliothek, CUPS-Raw-Fallback-Transport, signierte App und Sparkle-Updates.

### Nicht-Ziele
- LabelManager-Bandgeräte (D1-Band), MobileLabeler, Bluetooth, WLAN-Einrichtung, Firmware-Updates.
- Cloud, Konten, Analytics, Telemetrie, Online-Adressprüfung.
- Ein vollwertiger Layout-Editor mit freier Objektplatzierung wie DYMO Connect. v1 arbeitet mit **Layouts** (Text, Adresse, Text+Barcode, Text+QR, Bild …), die sich automatisch einpassen. Freies Platzieren kommt höchstens später.
- Systemdruckdialog-Integration (CUPS-Raster-Pfad).

### Anti-Ziele (wäre ein Fehlschlag, auch wenn es technisch läuft)
- Der Nutzer muss vor dem ersten Druck Rolle, Ausrichtung oder Druckmodus suchen.
- Die Vorschau zeigt etwas anderes als den Druck (Ausrichtung, Ränder, Abschneiden).
- MacLabel verlangt root-Rechte, einen Kernel- oder DriverKit-Treiber oder einen Hintergrund-Daemon.
- Es wird stillschweigend etwas abgeschnitten (DYMO-Treiber: nur `WARNING` im Log). MacLabel warnt sichtbar, bevor gedruckt wird.
- Im öffentlichen Repo landen DYMO-Originaldateien, DYMO-Code, Secrets oder Telemetrie.

## 3. Rahmenbedingungen

- macOS 26+ (Entwicklung auf macOS 27, Xcode 27.1, Swift 6.4, Strict Concurrency).
- Öffentliches GitHub-Repo `darkspike1988/MacLabel`, MIT-Lizenz.
- **Rechtliches zur Rollen-Datenbank:** DYMOs `SKUs.xml`/`Papers.xml` werden **nicht** veröffentlicht. MacLabel enthält eine eigene JSON-Datenbank mit **Fakten** (Artikelnummer, Maße, bedruckbarer Bereich, Eckenradius, Art, Material, Region) in eigenem Format, erzeugt durch ein Skript `tools/import-dymo-media`. Das Skript liest die Daten aus einer lokal installierten DYMO-Connect-App (Interoperabilitätszweck). Übersetzte Produkttexte, Bilder und Suchbegriffe werden nicht übernommen. Eigene Namen und Suchbegriffe pflegt MacLabel selbst.
- Das Protokoll ist aus öffentlich dokumentierten Quellen bekannt: LW450 Technical Reference Manual, DYMOs GPL-CUPS-Treiber. Die REA-Analyse bestätigt es. MacLabel implementiert es neu und kopiert keinen GPL-Code (MIT-Lizenz).
- Kein Testdruck auf der echten Hardware ohne den Auftraggeber. Encoder werden gegen Golden-Byte-Fixtures getestet, die aus der Spezifikation abgeleitet sind.

## 4. Getroffene Entscheidungen (alle von Claude, Auftraggeber hat delegiert)

### 4.1 Architektur
Ein Swift Package `MacLabelKit` mit klaren Modulen, dazu eine Xcode-App und ein CLI-Ziel.

```
MacLabel/
├─ Package.swift                      (MacLabelKit + maclabel CLI)
├─ Sources/
│  ├─ LabelMedia/       Rollen-Modell + gebündelte media.json + Suche
│  ├─ LabelRender/      Layout → CGImage → 1-bpp-Raster (Monochrome-Bitmap)
│  ├─ LabelProtocol/    Encoder: LWClassic (v1), LWV2 (Gerüst); Statusdecoder
│  ├─ LabelTransport/   USB (IOUSBHost/IOKit), Gerätesuche, FileTransport (Debug)
│  ├─ MacLabelKit/      Fassade: PrintService (Render → Encode → Transport), Druckermodelle
│  └─ maclabel/         CLI (swift-argument-parser)
├─ App/                 Xcode-Projekt (SwiftUI-App, Menüleiste, Dienst, App Intents)
├─ Tests/               Swift Testing pro Modul
├─ tools/import-dymo-media/   Skript: lokale DYMO-Daten → media.json
└─ docs/
```

Begründung: Protokoll, Rendering und Medien sind ohne UI testbar. App und CLI teilen denselben Kern, und Homebrew kann das CLI separat bauen.

### 4.2 Druckpfad
1. **Rendern:** Das Layout wird mit Core Graphics/Core Text in ein Bitmap in Druckauflösung gezeichnet: 300 dpi quer, 300 oder 600 lpi in Vorschubrichtung. Text und Barcodes werden per Schwellwert in 1 Bit umgewandelt (kein Dithering), Fotos optional per Floyd-Steinberg. Barcodes werden auf ganze Druckpunkte ausgerichtet (Modulbreite = ganzzahlige Dot-Anzahl), damit sie scannbar bleiben.
2. **Encodieren (LW-Classic):** Bytefolge laut `docs/research/lw450-protocol.md` §2:
   `ESC×~100` (Resync), `ESC @`, `ESC Q 00 00`, `ESC B 00`, `ESC h|i`, `ESC c|d|e|g`, [`ESC q n`], pro Label `ESC L hi lo` und Zeilen mit `ESC D n`/`ESC B n` bei Änderung + `SYN`/`ETB` (jeweils das kürzere), Leerzeilen via `ESC f 01 n`, zwischen Labels `ESC G`, am Ende `ESC E`.
3. **Transport:** IOUSBHost: Gerät per VID 0x0922 + PID-Tabelle finden, Interface Klasse 7 öffnen, Bulk OUT schreiben, Bulk IN für Status/Version lesen. Die Verbindung wird nur für die Dauer eines Jobs oder einer Abfrage gehalten (CUPS-Jobs anderer Apps sollen weiterlaufen). Bei `kIOReturnExclusiveAccess` zeigt die App „Drucker gerade von einer anderen App belegt“.
4. **Status:** `ESC A` → 1 Byte. 0x03 = bereit. Bits: 0x02 TOF, 0x20 kein Papier, 0x40 Stau, 0x80 Fehler. Abfrage vor dem Druck, nach jedem Label und im Leerlauf alle 3 s, solange ein Fenster sichtbar ist. Bei Papierende: Dialog „Neue Rolle einlegen“, danach automatisch ab dem fehlenden Label weiter.
5. **Druckmodus automatisch:** Enthält ein Layout Barcode oder QR, wird im Grafikmodus gedruckt (`ESC i`, 600 lpi), sonst im Textmodus (`ESC h`, 300 lpi, schneller). Dichte Standard „Normal“, bei Material *Durable* „Dark“. Beides lässt sich überschreiben, ist aber versteckt unter „Mehr“.

### 4.3 Rollenmodell und die Ausrichtungsregel
- Jede Rolle hat: `id`, `skus` (alle Artikelnummern, z. B. `["11354","S0722540","2112289"]`), Anzeigename de/en, `kind` (dieCut/continuous), `acrossMM` (quer zum Druckkopf), `feedMM` (in Vorschubrichtung; `nil` bei Endlos), bedruckbarer Bereich (Ursprung + Größe in Dots), Eckenradius, Material, Regionen, kompatible Druckerklassen (Kopfbreite 672 oder 1248 Dots).
- Grundlage: `Papers.xml`, Gruppe `LabelWriter400`, Einheit Twips (1/1440"). `Size.Width` = quer zum Kopf (verifiziert: 30252 Address = 27,7 mm quer × 88,9 mm Vorschub; 11354 = 57,1 × 31,8 mm, druckbar 651 Dots).
- **Duplikate werden zusammengeführt:** Papiere mit identischer Größe und identischem druckbarem Bereich werden zu einer Rolle mit allen SKUs (11354/30334/S0722540/2112289 → eine Rolle).
- **DYMOs `DefaultOrientation` wird verworfen.** MacLabel nutzt eine eigene, einfache Regel: **Die Leseausrichtung ist die, in der die längere Etikettenkante waagerecht liegt.** Der Nutzer kann mit einem Klick drehen, und das wird pro Rolle gemerkt. Bei 11354 (57 quer × 32 Vorschub) ist der Text also entlang der 57-mm-Kante, ohne Rotation im Raster. Bei Adressetiketten (28 quer × 89 Vorschub) wird der Text um 90° gedreht gerastert.
- Die Suche normalisiert Eingaben (Groß/Klein, Leerzeichen, `x`/`×`, mm/Zoll) und findet Artikelnummern, Maße und Namen.
- Nutzer können eigene Rollen anlegen (Maße in mm). Sie werden in Application Support gespeichert.

### 4.4 Bedienung (App)
- **Ein Hauptfenster**, dreigeteilt in Inhalt, Vorschau und Druckleiste:
  - Oben die Rollenauswahl als Suchfeld-Chip („11354 · 57 × 32 mm“) und der Druckerstatus als Punkt + Text („LabelWriter 450 · bereit“).
  - Mitte die große, maßstabsgetreue Vorschau des Rasters auf der Etikettenkontur, darunter Layout-Auswahl als Segmente (Text, Adresse, Barcode, QR, Bild).
  - Links bzw. unter der Vorschau der Inhalt: bei Text ein Textfeld mit Live-Auto-Fit, Fett und Ausrichtung.
  - Unten Kopien-Stepper und der große Button „Drucken“ (⌘P). „Mehr“ öffnet Dichte, Modus, Zähler und CSV.
- Beim Start ist das Textfeld fokussiert. Die zuletzt benutzte Rolle und der Drucker sind vorgewählt.
- Ist der Text zu lang, zeigt die Vorschau eine rote Markierung, und der Druck-Button fragt nach.
- **Menüleisten-Extra:** Textfeld + Drucken + Status, nutzt die letzte Rolle.
- **Dienst** „Mit MacLabel drucken“ (NSServices, Text) öffnet das Schnelldruck-Panel vorbefüllt.
- **App Intents:** „Etikett drucken“ (Text, Rolle optional, Kopien), „Druckerstatus“.
- Natives SwiftUI, folgt dem Systemerscheinungsbild (hell/dunkel, Akzentfarbe), keine eigenen Kontroll-Skins.

### 4.5 CLI
```
maclabel print "Keller · Box 3" [--roll 11354] [--copies 2] [--layout text|qr|barcode] [--dry-run out.png|out.bin]
maclabel status
maclabel rolls search 32x57
maclabel printers
```
`--dry-run` schreibt die Vorschau als PNG oder den Bytestrom als Datei. Das dient dem Testen ohne Hardware und dem Vergleich mit dem DYMO-Treiber.

### 4.6 Qualität
- Swift Testing. Golden-Byte-Tests für den Encoder (Resync, Header, RLE-Grenzfälle 1/127/128/129 Pixel, Leerzeilen-Zusammenfassung 300 → 255+45, Endlos `ESC L FF FF`, Twin-Rollenwahl). Raster-Tests: Abmessungen exakt (z. B. 11354 → 651 Dots breit), Barcode-Modul auf Dots ausgerichtet, Rotation. Mediensuche: S0722540 → Rolle 11354. Statusdecoder: alle Bits.
- GitHub Actions: `swift build` + `swift test` auf macOS.
- Kein Secret im Repo. Keine Netzwerkzugriffe in v1.

### 4.7 Verteilung
- v1: Homebrew-Tap `darkspike1988/homebrew-maclabel` mit Formel für das CLI (Build from source) und einem Cask für die App, sobald es signierte Builds gibt. **Veröffentlichung erst nach Freigabe durch den Auftraggeber.**
- Später: Developer-ID-Signatur, Notarisierung, GitHub Releases, Sparkle.

### 4.8 Entscheidungen nach dem Builder-Check (Claude, autonom)
1. **Hardware-Zugriff ohne Auftraggeber:** Erlaubt ist alles, was **kein Papier bewegt**: Gerät suchen, Interface öffnen, Endpoints lesen, Resync, `ESC @`, `ESC A` (Status), `ESC V` (Version). Verboten sind Rasterdaten, `ESC E`, `ESC G` und `ESC f`. Der Transport wird damit früh am echten 450 verifiziert. Druckausgabe, Ausrichtung und Spiegelung prüft der Auftraggeber beim ersten Testdruck (Checkliste in `docs/first-print-checklist.md`). Bis dahin gilt laut Manual: MSB = linkster Dot, die erste gesendete Zeile kommt zuerst aus dem Drucker. Das Rollenmodell enthält zusätzlich `offsetDots` (aus `Papers.xml` `Offset.X`, quer), damit schmale Etiketten an der richtigen Kopfkante liegen.
2. **Erster Druck ohne gemerkte Rolle:** Beim allerersten Start (und wenn ein neuer Drucker auftaucht) fragt MacLabel **einmalig** in einem Sheet: „Welche Rolle ist eingelegt?“, mit Suchfeld und einer Auswahl der häufigsten Rollen (11354/S0722540, 99010, 99012, 11352, 99014, S0904980). Danach wird nie wieder ungefragt umgestellt. CLI und App Intents ohne `--roll` und ohne gemerkte Rolle brechen mit einem klaren Hinweis ab und raten nicht.
3. **203/204-dpi-Modelle (LW 300er-Serie, SE450):** **nicht in v1.** v1 unterstützt die 300-dpi-Geräte mit 672 Dots (400, 400 Turbo, Twin Turbo, 450, 450 Turbo, 450 Twin Turbo, 450 DUO-Labelseite) und den 4XL (1248 Dots). Die übrigen PIDs werden erkannt und als „noch nicht unterstützt“ angezeigt. Ziel 6 ist entsprechend zu lesen.
4. **Nebeneinander mit DYMO Connect/CUPS:** Das muss weiter funktionieren. Status wird nur abgefragt, solange ein MacLabel-Fenster bzw. das Menüleisten-Panel sichtbar ist: alle 5 s, Interface öffnen, `ESC A`, schließen (< 100 ms). Ist das Gerät belegt, folgt kein Fehler, sondern „belegt“, und 15 s keine Abfrage. Keine Dauerverbindung, kein Polling im Hintergrund.
5. **Öffentliches Repo während der Entwicklung:** Ja, der Auftraggeber hat ein öffentliches GitHub-Repo verlangt. Gepusht wird ab dem Design-Commit. CI (GitHub Actions: build + test) ab dem ersten Code. `media.json` enthält nur Fakten (siehe §3). Vor dem ersten Push mit `media.json` wird geprüft, dass keine DYMO-Texte, Suchbegriffe oder Übersetzungen enthalten sind.

## 5. Dem Umsetzer überlassen
- Genaue SwiftUI-Komponentenstruktur, Animationen, Icons (SF Symbols).
- Wahl zwischen IOUSBHost.framework und IOKit-`IOUSBInterfaceInterface` (Vorzug: das modernere IOUSBHost, falls Bulk-Pipes ohne Entitlement-Probleme gehen).
- Interne Datenformate (media.json-Schema-Details), sofern die Felder aus §4.3 abgedeckt sind.
- Feinheiten des Auto-Fit-Algorithmus (binäre Suche über die Schriftgröße).

## 6. Offene Punkte (brauchen echte Hardware oder den Auftraggeber)
- Erster Echtdruck am LW450: Bulk-Endpoints, ESC-V-Antwort, Ausrichtung und Ränder auf 11354 prüfen.
- Ob LW400/4XL `ESC i` (600 lpi) kennen. Bis das geklärt ist, für diese Modelle nur `ESC h`.
- LW-V2 (550) erst mit Testgerät.
- Homebrew-/Release-Veröffentlichung nach Freigabe.

## 7. Quellen
- `docs/research/lw450-protocol.md`: Kommandosatz, Status, Modellmatrix, USB-Zugriff (REA + offizielle Doku + GPL-Quelle).
- `docs/research/dymo-connect-features.md`: Funktionsumfang DYMO Connect, Datenmodell der Rollen, Inkonsistenzen.
