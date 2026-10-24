# Portierungskonzept: DYMO Connect → MacLabel (Swift)

Stand: 24.10.2026 · Grundlage: `docs/research/dymo-connect-features.md` (Metadaten-Inventar), `docs/research/dymo-connect-decompiled.md` (Analyse des dekompilierten C#-Codes), `docs/research/lw450-protocol.md` (Protokoll, verifiziert am LW450).

## Grundsätze

1. **Verhalten nachbauen, keinen Code übersetzen.** Der dekompilierte DYMO-Code dient als Spezifikation, also für Datenformate, Einheiten und Randfälle. MacLabel implementiert alles neu in Swift. Es gibt keine Zeile-für-Zeile-Übertragung und keine kopierten Tabellen, Texte oder Bilder. So bleibt das Repo MIT-lizenzierbar.
2. **Open Source, keine Datenweitergabe.** Was in DYMO Connect Netzwerk braucht (Analytics, USPS, Google/Outlook-Kontakte, Cloud-Vorlagen, Firmware- und Update-Check), entfällt ersatzlos oder wird durch lokale macOS-Funktionen ersetzt. Die App hat kein Netzwerk-Entitlement.
3. **Eine App.** `MacLabel.app` umfasst Fenster, Menüleiste, Dienst, App Intents und das eingebettete CLI. Den Kern bildet `MacLabelKit`.
4. **Nur macOS-native Technik.** SwiftUI, Core Graphics/Core Text, Core Image, IOUSBHost, Contacts, App Intents, UniformTypeIdentifiers. Keine Drittanbieter-Abhängigkeiten außer `swift-argument-parser`, später evtl. einer kleinen Bibliothek zum Lesen von `.xlsx`.

## Zuordnung: DYMO-Connect-Modul → MacLabel

| DYMO Connect (C#/.NET) | Aufgabe | MacLabel (Swift) | Status |
|---|---|---|---|
| `DYMO.LabelAPI` – `PaperInfoFactory`, Papers.xml/SKUs.xml | Rollen-/Papiermodell (Twips, Kopfbreite × Vorschub) | `LabelMedia` (`LabelRoll`, `MediaCatalog`, eigene `media.json` aus Fakten) | ✅ gebaut |
| `ELabelOrientation`, `DefaultOrientation`, `PaperRegionViewModel.ChooseOrientation` | Ausrichtung (fehlerhaft, Ursache der Fehldrucke) | `ReadingRotation` + Regel „lange Kante waagerecht“, absolute Drehung im Raster | ✅ gebaut, Fehlerquelle beseitigt |
| `DYMO.LabelAPI.Skia` (`SkiaDrawingContext`, `SkiaBitmapFactory`) | Rendering 300 dpi, ohne Antialiasing | `LabelRender` (Core Graphics/Core Text, 1-bpp, 300/600 lpi) | ✅ gebaut |
| `ETextFitMode.AlwaysFit` (iterativer Solver, 0,3-pt-Schritte) | Text-Auto-Fit | `TextLayout` (binäre Suche 0,5 pt, echte Glyphenhöhe) | ✅ gebaut |
| `Base1DBarcode`, `Base2DBarcode`, `QRCode` (ZXing-artig) | Barcodes/QR | `LabelRender/Barcodes` (eigene Encoder, Vision-Round-Trip-Tests) | ✅ 6 Symbologien + QR |
| `libdymoprintingsupport.dylib` (PMPrintSession → CUPS → `raster2dymolw`) | Drucken | `LabelProtocol` (LW-Classic-Encoder) + `LabelTransport` (IOUSBHost) | ✅ gebaut, Testdruck steht aus |
| `GetLegacyStatus` (leer beim 450) | Druckerstatus | `LWStatus` via `ESC A`, `LWVersion` via `ESC V` | ✅ besser als Original |
| `DYMO.PrinterCommands` (LW550-Status, Firmware, WLAN) | 550-Serie | `LWV2Encoder` + 32-Byte-Status | ⏳ Phase 3 |
| Datenimport (IronXL, CSV) + `DataMappingTextSpan` | Serienetiketten | `CSVTable` + `LabelBatch` (Platzhalter `{Spalte}`, `{n}`) | ✅ CSV; `.xlsx` ⏳ Phase 2 |
| `CounterObject`, `DateTimeObject` | Zähler, Datum | Zähler ✅; Datum/Uhrzeit-Platzhalter ⏳ Phase 2 | teilweise |
| `DYMO.AddressBook`, Apple-/Google-/Outlook-Kontakte | Adressen | **Contacts.framework** (lokal); Google/Outlook entfallen | ⏳ Phase 2 (App) |
| `DCDesktopLabel`/`DYMOLabel` (`.dymo`, `.labelx`, `.label`) | Dateiformat | `DymoImport` (XML-Parser, Zoll-Koordinaten, v3/v4, SKU-Alias) | ⏳ Phase 2 |
| `DYMO.LabelTemplates` (67 Vorlagen) | Vorlagen | eigene, schlichte Layout-Vorlagen (Text, Adresse, Text+QR, Text+Barcode, Inventar, Ordnerrücken); keine DYMO-Grafiken | ⏳ Phase 2 |
| `CircularTextObject`, `ShapeObject`, `LineObject`, `ImageObject` | weitere Objekte | Bild ✅; Formen/Linien/Kreistext ⏳ Phase 4 (freier Editor) | teilweise |
| `DYMO.DCDesktop` + 97 Storyboards / ~40 Dialoge | Oberfläche | SwiftUI: ein Fenster, Inspector statt Dialogen, Menüleiste, Dienst | ⏳ Phase 2 |
| `GoogleAnalyticsApi`, `AddressFixer` (USPS), `UpdateHelper`, `FirmwareService`, Cloudflare/S3 | Netzwerk | **entfällt** | 🚫 bewusst nicht |
| `SMJobBless`-Helper, DriverKit-Extension | Privilegierter Zugriff | **entfällt** (IOUSBHost im Nutzerkontext reicht) | 🚫 bewusst nicht |

## Phasen

**Phase 1 – Kern und CLI (fertig auf Branch `feat/maclabelkit-cli`)**
Rollen-Datenbank, Rendering, Barcodes, LW-Classic-Protokoll, USB, Druckdienst, Serien, CLI. Offen ist nur der erste echte Testdruck (`docs/first-print-checklist.md`).

**Phase 2 – Die App (`MacLabel.app`)**
1. SwiftUI-Hauptfenster: Rollen-Chip mit Suche, Live-Vorschau aus `RenderResult.preview`, Layout-Segmente, Druckleiste, Status-Punkt (Abfrage alle 5 s, nur bei sichtbarem Fenster).
2. Erst-Start-Sheet „Welche Rolle ist eingelegt?“.
3. Menüleisten-Schnelldruck, Dienst „Mit MacLabel drucken“, App Intents.
4. Kontakte (Contacts.framework, Picker) für das Adress-Layout.
5. CSV per Drag & Drop. `.xlsx` lesen über eine kleine Open-Source-Bibliothek (z. B. CoreXLSX, MIT) oder einen eigenen schlanken Parser für Zip+XML.
6. Datum/Uhrzeit-Platzhalter (`{datum}`, `{uhrzeit}`, Formate per `DateFormatter`).
7. Import von `.dymo`/`.labelx`: XML tolerant parsen, Zoll → Punkte, `LabelName` über die SKU-Alias-Tabelle der Rollen-Datenbank auflösen, Text-, Barcode- und QR-Objekte auf MacLabel-Layouts abbilden. Nicht abbildbare Objekte melden, nicht verschlucken.
8. Eigene Vorlagen und „Zuletzt gedruckt“ (lokal, JSON in Application Support).
9. Einbettung des CLI, Menüpunkt „Kommandozeilenwerkzeug installieren“, Sandbox ohne Netzwerk-Entitlement, Signatur und Notarisierung.

**Phase 3 – LabelWriter-550-Familie**
`LWV2Encoder`: Job-ID (`ESC s`), Label-Index (`ESC n`), Bitmap-Block mit 12-Byte-Header, LZ4 ab Firmware 1000, `ESC T` für High-Speed, `ESC M` für Durable, 32-Byte-Status mit Kopftemperatur und Schachtstatus. Nur mit Testgerät. NFC-gebundene Etiketten sind eine Einschränkung der Hardware; MacLabel zeigt den Status „counterfeit media“ ehrlich an und umgeht nichts.

**Phase 4 – Freier Editor (optional)**
Freies Platzieren von Objekten, Formen, Linien und Kreistext. Erst wenn die Layout-Vorlagen nicht reichen. Bewusst nach hinten gestellt, weil der Leitsatz „unter 10 Sekunden ohne Einstellungen“ heißt.

## Was MacLabel bewusst besser macht als das Original

- Eindeutige Ausrichtung, ohne Portrait/Landscape-Begriffe. Rollen-Aliasse wie S0722540, 11354 und 30334 sind eine Rolle.
- Vorschau = Druckraster (dasselbe 1-Bit-Bitmap), kein PDF-Umweg über CUPS mit Error-Diffusion.
- Echter Status beim LW450 und sichtbare Fehler statt stummem Scheitern.
- Ganzzahlige Barcode-Module, QR mit Ruhezone, Klartext unter dem Barcode.
- Ein Druckjob für alle Etiketten.
- Keine Telemetrie, keine eingebetteten Schlüssel, keine Netzwerkzugriffe, kein privilegierter Helper.
