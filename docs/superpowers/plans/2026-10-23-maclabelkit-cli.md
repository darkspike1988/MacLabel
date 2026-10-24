# MacLabelKit + CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein Swift Package `MacLabelKit` (Rollen-Datenbank, Renderer, LW-Classic-Protokoll, USB-Transport, Druckdienst) und das CLI `maclabel`, mit dem man vom Terminal aus auf einem LabelWriter 450 druckt.

**Architecture:** Fünf Library-Targets in einer Schichtung: `LabelProtocol` (Bitmap, Modelle, Encoder, Status) ← `LabelMedia` (Rollen) ← `LabelRender` (Layout → 1-bpp-Bitmap) ← `LabelTransport` (IOUSBHost) ← `MacLabelKit` (PrintService, Batch, Prefs) ← Executable `maclabel`. Die App (Plan 2) baut auf `MacLabelKit` auf.

**Tech Stack:** Swift 6.4 (Strict Concurrency, Swift-Language-Mode 6), SwiftPM, Swift Testing, Core Graphics/Core Text/Core Image, IOUSBHost.framework, swift-argument-parser ≥ 1.5.0, Python 3 (nur das Import-Werkzeug).

**Spec:** `docs/superpowers/specs/2026-10-23-maclabel-design.md`. Protokoll-Fakten: `docs/research/lw450-protocol.md` (§2, §3, §10).

## Global Constraints

- Plattform: `.macOS(.v26)`; `swift-tools-version: 6.2`.
- Keine Netzwerkzugriffe, keine Analytics, keine Secrets im Repo.
- Keine DYMO-Originaldateien, -Texte, -Suchbegriffe oder -Übersetzungen im Repo. `media.json` enthält nur Fakten (Artikelnummern, Maße, Material, Region).
- Am echten Drucker in Tests oder Entwicklung **nie** Rasterdaten, `ESC E`, `ESC G` oder `ESC f` senden. Erlaubt sind Gerätesuche, Öffnen, `ESC A`, `ESC V` und Resync/`ESC @` (Spec §4.8.1). Echte Drucke macht nur der Auftraggeber.
- v1-Druckermodelle: LW-Classic mit 300 dpi (PIDs 0x18, 0x19, 0x1A, 0x1D, 0x1F, 0x20, 0x21, 0x22, 0x23). Andere DYMO-PIDs werden erkannt, aber als `unsupported` gemeldet.
- Einheiten: Twips (1/1440") in den Quelldaten. Druckpunkte quer immer 300 dpi. Zeilen in Vorschubrichtung 300 lpi (`.text`) oder 600 lpi (`.graphics`). Umrechnung: `dots = round(twips / 4.8)`.
- Bitreihenfolge im Raster: MSB = linkester Dot (Dot 0). 1 = schwarz.
- Sprache der Nutzertexte: Deutsch und Englisch (`String(localized:)` mit `.xcstrings` in `MacLabelKit`). Code und Identifier auf Englisch.
- Commit-Messages enden mit `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Text passt nicht auf das Etikett** → `RenderResult.overflow == true`. Niemals still abschneiden. Das CLI bricht ohne `--force` mit Hinweis ab (Task 6, Task 11).
2. **Drucker gerade von CUPS/DYMO belegt** (`kIOReturnExclusiveAccess`) → `TransportError.busy` mit Klartext „Drucker wird gerade von einer anderen App benutzt“. Kein Absturz, kein Hängen (Task 9).
3. **Rolle passt nicht in den Druckkopf** (z. B. 4XL-Versandetikett auf dem 450) → `PrintError.rollTooWide` vor dem Senden (Task 10).
4. **Deutsche CSV aus Excel** (Semikolon, Anführungszeichen, UTF-8-BOM, CRLF) → korrekt geparst (Task 8).
5. **Papier leer oder Drucker vor dem Druck nicht bereit** → `PrintError.printerNotReady(LWStatus)` vor dem ersten Byte Rasterdaten. Zwischen Labels: Status prüfen und bei Fehler abbrechen, mit Angabe, wie viele Labels gedruckt wurden (Task 10).

---

## File Structure

```
Package.swift
Sources/LabelProtocol/MonochromeBitmap.swift      Bitmap 1 bpp, MSB-links
Sources/LabelProtocol/PrinterModel.swift          Modelle/PIDs/Familien
Sources/LabelProtocol/PrintSettings.swift         PrintQuality, PrintDensity, TwinRoll
Sources/LabelProtocol/LWStatus.swift              Status- und Versions-Decoder
Sources/LabelProtocol/LWClassicEncoder.swift      Jobs → Bytes
Sources/LabelMedia/LabelRoll.swift                Rollen-Modell + Geometrie
Sources/LabelMedia/MediaCatalog.swift             Laden, Suche
Sources/LabelMedia/Resources/media.json           generiert (Task 4)
Sources/LabelRender/LabelContent.swift            Inhaltstypen
Sources/LabelRender/LabelGeometry.swift           Rolle+Qualität → Kopfkoordinaten, Rotation
Sources/LabelRender/LabelRenderer.swift           Rendern → RenderResult
Sources/LabelRender/TextLayout.swift              Auto-Fit
Sources/LabelRender/Barcodes/*.swift              Code128, EAN/UPC, Code39, ITF-14, QR-Matrix
Sources/LabelRender/Dithering.swift               Schwellwert / Floyd-Steinberg
Sources/LabelTransport/USBPrinterDiscovery.swift  Gerätesuche
Sources/LabelTransport/USBPrinterConnection.swift Öffnen, schreiben, lesen
Sources/LabelTransport/PrinterTransport.swift     Protokoll + FileTransport
Sources/MacLabelKit/PrintService.swift            Orchestrierung
Sources/MacLabelKit/LabelBatch.swift              Kopien, Zähler, CSV
Sources/MacLabelKit/CSVTable.swift                CSV-Parser
Sources/MacLabelKit/RollPreferences.swift         gemerkte Rolle pro Drucker
Sources/MacLabelKit/Localizable.xcstrings
Sources/maclabel/*.swift                          CLI
Tests/<Target>Tests/*.swift
tools/import-dymo-media/import.py, names.json
.github/workflows/ci.yml
docs/first-print-checklist.md
```

---

### Task 1: Package-Gerüst, CI und `MonochromeBitmap`

**Files:**
- Create: `Package.swift`, `Sources/LabelProtocol/MonochromeBitmap.swift`, `Tests/LabelProtocolTests/MonochromeBitmapTests.swift`, `.github/workflows/ci.yml`
- Create: leere Platzhalter-Dateien für die übrigen Targets, damit das Package baut.

**Interfaces:**
- Produces: `public struct MonochromeBitmap: Sendable, Equatable { public let width: Int; public let height: Int; public var bytesPerRow: Int { (width + 7) / 8 }; public init(width: Int, height: Int); public subscript(x: Int, y: Int) -> Bool { get set }; public func row(_ y: Int) -> ArraySlice<UInt8>; public func isRowBlank(_ y: Int) -> Bool }`. Speicherung `[UInt8]`, MSB = x 0.

- [ ] **Step 1: Package.swift anlegen.** Targets: `LabelProtocol`, `LabelMedia` (deps: LabelProtocol, resources: `.process("Resources")`), `LabelRender` (deps: LabelProtocol, LabelMedia), `LabelTransport` (deps: LabelProtocol; linkerSettings `.linkedFramework("IOUSBHost")`, `.linkedFramework("IOKit")`), `MacLabelKit` (deps: alle vier; resources `.process("Localizable.xcstrings")`), executable `maclabel` (deps: MacLabelKit, ArgumentParser). Test-Targets je Library. Dependency `https://github.com/apple/swift-argument-parser` `from: "1.5.0"`.
- [ ] **Step 2: Failing tests schreiben**
```swift
@Test func bitOrderIsMSBLeft() { var b = MonochromeBitmap(width: 16, height: 1); b[0,0] = true; b[9,0] = true
  #expect(Array(b.row(0)) == [0b1000_0000, 0b0100_0000]) }
@Test func widthNotMultipleOf8PadsRow() { let b = MonochromeBitmap(width: 10, height: 2); #expect(b.bytesPerRow == 2); #expect(b.row(1).count == 2) }
@Test func blankRow() { var b = MonochromeBitmap(width: 8, height: 2); b[3,1] = true; #expect(b.isRowBlank(0)); #expect(!b.isRowBlank(1)) }
```
- [ ] **Step 3: `swift test --filter MonochromeBitmapTests` → FAIL** (Typ fehlt).
- [ ] **Step 4: Implementieren.**
- [ ] **Step 5: `swift test` → PASS**, `swift build` ohne Warnungen.
- [ ] **Step 6: CI** `.github/workflows/ci.yml`: `runs-on: macos-latest`, Schritte `swift build` und `swift test`.
- [ ] **Step 7: Commit** `feat: Package-Gerüst, CI und MonochromeBitmap`.

---

### Task 2: Druckermodelle, Einstellungen, Status- und Versionsdecoder

**Files:**
- Create: `Sources/LabelProtocol/PrinterModel.swift`, `PrintSettings.swift`, `LWStatus.swift`; Test: `Tests/LabelProtocolTests/PrinterModelTests.swift`, `LWStatusTests.swift`

**Interfaces:**
- Produces:
  - `public enum ProtocolFamily: Sendable { case lwClassic, lwV2, unsupported }`
  - `public struct PrinterModel: Sendable, Hashable { public let name: String; public let productID: UInt16; public let family: ProtocolFamily; public let headDots: Int; public let supports600lpi: Bool; public let hasTwinRolls: Bool; public static let vendorID: UInt16 = 0x0922; public static let all: [PrinterModel]; public static func lookup(productID: UInt16) -> PrinterModel? }`
  - `public enum PrintQuality: Sendable { case text, graphics; public var linesPerInch: Int }` (300/600)
  - `public enum PrintDensity: Sendable, CaseIterable { case light, medium, normal, dark }`
  - `public enum TwinRoll: Sendable { case auto, left, right }`
  - `public struct LWStatus: Sendable, Equatable { public let raw: UInt8; public init(raw: UInt8); public var isReady: Bool; public var isTopOfForm: Bool; public var isPaperOut: Bool; public var isJammed: Bool; public var hasError: Bool; public var canPrint: Bool }`
  - `public struct LWVersion: Sendable, Equatable { public let modelNumber: String; public let firmware: String; public init?(response: [UInt8]) }`

- [ ] **Step 1: Failing tests**
```swift
@Test func lw450Lookup() { let m = PrinterModel.lookup(productID: 0x20)!; #expect(m.name == "LabelWriter 450"); #expect(m.family == .lwClassic); #expect(m.headDots == 672); #expect(m.supports600lpi) }
@Test func fourXL() { #expect(PrinterModel.lookup(productID: 0x1F)!.headDots == 1248) }
@Test func twinTurbo() { #expect(PrinterModel.lookup(productID: 0x22)!.hasTwinRolls) }
@Test func lw550IsV2() { #expect(PrinterModel.lookup(productID: 0x28)!.family == .lwV2) }
@Test func se450Unsupported() { #expect(PrinterModel.lookup(productID: 0x24)!.family == .unsupported) }
@Test func unknownPID() { #expect(PrinterModel.lookup(productID: 0x7777) == nil) }
@Test func readyStatus() { let s = LWStatus(raw: 0x03); #expect(s.isReady && s.isTopOfForm && s.canPrint && !s.isPaperOut) }
@Test func paperOut() { let s = LWStatus(raw: 0xA0); #expect(s.isPaperOut && s.hasError && !s.canPrint) }
@Test func jam() { #expect(LWStatus(raw: 0x41).isJammed) }
@Test func versionFromRealDevice() { let v = LWVersion(response: Array("1750111f0J".utf8))!; #expect(v.modelNumber == "1750111"); #expect(v.firmware == "f0J") }
@Test func versionTooShort() { #expect(LWVersion(response: Array("123".utf8)) == nil) }
```
- [ ] **Step 2: FAIL prüfen.**
- [ ] **Step 3: Implementieren.** Modelltabelle laut `lw450-protocol.md` §6:
  - **lwClassic:** 0x18 Twin Turbo, 0x19 400, 0x1A 400 Turbo, 0x1D DUO Label, 0x1F 4XL (1248 Dots), 0x20 450, 0x21 450 Turbo, 0x22 450 Twin Turbo, 0x23 450 DUO.
    - `supports600lpi = true` nur für 0x20–0x23.
    - `hasTwinRolls` für 0x18 und 0x22.
  - **lwV2:** 0x28 550, 0x29 550 Turbo, 0x2A 5XL.
  - **unsupported:** 0x06, 0x07, 0x08, 0x09, 0x10, 0x12 (300er-Serie), 0x24 (SE450), 0x27 (Wireless).
  - **Bits in `LWStatus`:**
    - ready = 0x01, TOF = 0x02, paperOut = 0x20, jam = 0x40, error = 0x80.
    - `canPrint` = ready && !paperOut && !jam && !error.
  - **`LWVersion`:** mindestens 8 Zeichen, die ersten 7 sind ASCII-Ziffern. Firmware = Rest ohne Leerzeichen/NUL.
- [ ] **Step 4: PASS.**
- [ ] **Step 5: Commit** `feat(protocol): Druckermodelle, Status- und Versionsdecoder`.

---

### Task 3: `LWClassicEncoder`

**Files:**
- Create: `Sources/LabelProtocol/LWClassicEncoder.swift`; Test: `Tests/LabelProtocolTests/LWClassicEncoderTests.swift`

**Interfaces:**
- Consumes: `MonochromeBitmap`, `PrintQuality`, `PrintDensity`, `TwinRoll`
- Produces:
  - `public struct LWClassicJob: Sendable { public var labels: [MonochromeBitmap]; public var labelLengthLines: Int?; public var quality: PrintQuality; public var density: PrintDensity; public var twinRoll: TwinRoll?; public init(...) }`. `labelLengthLines == nil` bedeutet Endlos.
  - `public enum LWClassicEncoder { public static func jobHeader(_ job: LWClassicJob) -> [UInt8]; public static func label(_ bitmap: MonochromeBitmap, lengthLines: Int?) -> [UInt8]; public static let betweenLabels: [UInt8]; public static let endOfJob: [UInt8]; public static func encode(_ job: LWClassicJob) -> [UInt8]; public static let statusRequest: [UInt8]; public static let versionRequest: [UInt8]; public static let resync: [UInt8] }`

Bytefolge (verbindlich):
```
resync     = [0x1B] * 156
jobHeader  = resync + [1B 40] + [1B 51 00 00] + [1B 42 00] + quality(text: 1B 68 | graphics: 1B 69)
             + density(light 1B 63 | medium 1B 64 | normal 1B 65 | dark 1B 67) + (twinRoll: 1B 71 30|31|32)
label      = [1B 4C hi lo]  (lengthLines big-endian; nil → FF FF)
             + [1B 44 n]    (n = bitmap.bytesPerRow, einmal pro Label)
             + Zeilen: aufeinanderfolgende leere Zeilen → [1B 66 01 k] in Blöcken k ≤ 255;
               sonst die kürzere von SYN [16 + row] oder ETB [17 + RLE], bei Gleichstand SYN
betweenLabels = [1B 47];  endOfJob = [1B 45];  statusRequest = [1B 41];  versionRequest = [1B 56]
encode     = jobHeader + label₁ + (betweenLabels + labelᵢ)… + endOfJob
RLE        = über bytesPerRow*8 Pixel; Läufe gleicher Farbe, max. 128; Byte = (schwarz ? 0x80 : 0) | (len − 1)
```
Leere Zeilen am Labelende werden ebenfalls als `1B 66 01 k` gesendet.

- [ ] **Step 1: Failing tests** (Bitmaps 16 px breit, also `bytesPerRow` 2)
```swift
@Test func headerTextNormal() { let h = LWClassicEncoder.jobHeader(.init(labels: [], labelLengthLines: 100, quality: .text, density: .normal))
  #expect(h.count == 156 + 2 + 4 + 3 + 2 + 2); #expect(Array(h.prefix(156)) == Array(repeating: 0x1B, count: 156))
  #expect(Array(h.suffix(13)) == [0x1B,0x40, 0x1B,0x51,0,0, 0x1B,0x42,0, 0x1B,0x68, 0x1B,0x65]) }
@Test func headerGraphicsDarkTwinLeft() { let h = LWClassicEncoder.jobHeader(.init(labels: [], labelLengthLines: 1, quality: .graphics, density: .dark, twinRoll: .left))
  #expect(Array(h.suffix(7)) == [0x1B,0x69, 0x1B,0x67, 0x1B,0x71,0x31]) }
@Test func labelLengthBigEndian() { #expect(Array(LWClassicEncoder.label(MonochromeBitmap(width: 16, height: 0), lengthLines: 0x0123).prefix(4)) == [0x1B,0x4C,0x01,0x23]) }
@Test func continuousLength() { #expect(Array(LWClassicEncoder.label(MonochromeBitmap(width: 16, height: 0), lengthLines: nil).prefix(4)) == [0x1B,0x4C,0xFF,0xFF]) }
@Test func tieUsesSYN() { var b = MonochromeBitmap(width: 16, height: 1); for x in 0..<8 { b[x,0] = true }
  #expect(Array(LWClassicEncoder.label(b, lengthLines: 1).dropFirst(7)) == [0x16, 0xFF, 0x00]) }
@Test func allBlackUsesETB() { var b = MonochromeBitmap(width: 16, height: 1); for x in 0..<16 { b[x,0] = true }
  #expect(Array(LWClassicEncoder.label(b, lengthLines: 1).dropFirst(7)) == [0x17, 0x8F]) }
@Test func rleSplitsRunsLongerThan128() { var b = MonochromeBitmap(width: 672, height: 1); for x in 0..<672 { b[x,0] = true }
  #expect(Array(LWClassicEncoder.label(b, lengthLines: 1).dropFirst(7)) == [0x17, 0xFF,0xFF,0xFF,0xFF,0xFF, 0x9F]) } // 5×128 + 32
@Test func blankRowsCollapse() { let b = MonochromeBitmap(width: 16, height: 300)
  #expect(Array(LWClassicEncoder.label(b, lengthLines: 300).dropFirst(7)) == [0x1B,0x66,0x01,0xFF, 0x1B,0x66,0x01,0x2D]) }
@Test func bytesPerLineSent() { #expect(Array(LWClassicEncoder.label(MonochromeBitmap(width: 672, height: 0), lengthLines: 1)[4..<7]) == [0x1B,0x44,84]) }
@Test func twoLabelJob() { let b = MonochromeBitmap(width: 16, height: 0)
  let bytes = LWClassicEncoder.encode(.init(labels: [b, b], labelLengthLines: 5, quality: .text, density: .normal))
  let l = LWClassicEncoder.label(b, lengthLines: 5)
  #expect(bytes == LWClassicEncoder.jobHeader(.init(labels: [], labelLengthLines: 5, quality: .text, density: .normal)) + l + [0x1B,0x47] + l + [0x1B,0x45]) }
```
- [ ] **Step 2: FAIL prüfen.**
- [ ] **Step 3: Implementieren.**
- [ ] **Step 4: PASS.**
- [ ] **Step 5: Commit** `feat(protocol): LW-Classic-Encoder mit SYN/ETB-Auswahl und Leerzeilen-Skip`.

---

### Task 4: Rollen-Datenbank (Import-Werkzeug, `media.json`, `MediaCatalog`)

**Files:**
- Create: `tools/import-dymo-media/import.py`, `tools/import-dymo-media/names.json`, `tools/import-dymo-media/README.md`, `Sources/LabelMedia/LabelRoll.swift`, `Sources/LabelMedia/MediaCatalog.swift`, `Sources/LabelMedia/Resources/media.json` (Ausgabe des Werkzeugs)
- Test: `Tests/LabelMediaTests/MediaCatalogTests.swift`

**Interfaces:**
- Produces:
  - `public struct LabelRoll: Codable, Sendable, Hashable, Identifiable { public let id: String; public let skus: [String]; public let nameDE: String; public let nameEN: String; public let kind: Kind; public let acrossMM: Double; public let feedMM: Double?; public let acrossDots: Int; public let feedDots: Int? /* exakt round(twips/4.8), nil bei Endlos */; public let printable: PrintableArea; public let offsetDots: Int; public let cornerRadiusMM: Double; public let material: String; public let regions: [String]; public let minHeadDots: Int; public enum Kind: String, Codable, Sendable { case dieCut, continuous } }`
  - `public struct PrintableArea: Codable, Sendable, Hashable { public let originAcrossDots: Int; public let originFeedDots: Int; public let widthDots: Int; public let lengthDots: Int? }`. Alles bei 300 dpi bzw. 300 lpi. `lengthDots` ist bei Endlos `nil`.
  - `public var displayName: String` (Systemsprache de → nameDE, sonst nameEN). `public var readingSizeMM: (width: Double, height: Double)`: die längere Kante zuerst, bei Endlos `(acrossMM, nil)`. Endlos wird als quer gelesen mit freier Länge behandelt.
  - `public struct MediaCatalog: Sendable { public let rolls: [LabelRoll]; public static let bundled: MediaCatalog; public init(rolls: [LabelRoll]); public func roll(id: String) -> LabelRoll?; public func roll(sku: String) -> LabelRoll?; public func search(_ query: String) -> [LabelRoll] }`

**Import-Werkzeug** (`python3 -I tools/import-dymo-media/import.py [--dll PATH] --out Sources/LabelMedia/Resources/media.json`):
- Default `--dll` ist `/Applications/DYMO Connect.app/Contents/MonoBundle/DYMO.LabelAPI.dll`. Das Werkzeug liest die eingebetteten Ressourcen `DYMO.LabelAPI.Resources.Papers.xml` und `…SKUs.xml` direkt aus der PE-Datei (CLI-Header → Resources-RVA → pro Ressource 4-Byte-Länge + Daten; Ressourcenoffsets aus der ManifestResource-Tabelle oder per Namenssuche).
  - Nur im Speicher verarbeiten, nichts von DYMO auf die Platte schreiben.
  - Ist die DLL nicht vorhanden: Exit 2 mit Hinweistext.
- **Auswahl:**
  - nur `PaperGroup Id="LabelWriter400"`
  - Papiere mit „offset“ im Namen auslassen
  - Papier aufnehmen, wenn eine SKU darauf zeigt oder der Name mit einer Artikelnummer beginnt (`^\d{5}|^S\d{7}`)
- **Duplikate:** Papiere mit gleichem `(Size.W, Size.H, PrintableSize.W, PrintableSize.H, PrintableOrigin.X, PrintableOrigin.Y)` werden zu einer Rolle zusammengeführt.
  - `skus` = alle SKUs und Namens-Artikelnummern, sortiert: 5-stellig numerisch zuerst, dann der Rest.
  - `id` = erstes Element.
- **Felder:**
  - `acrossMM = W·25.4/1440` (1 Nachkommastelle), `feedMM` analog aus H (bei Endlos `null`). `acrossDots = round(W/4.8)`, `feedDots = round(H/4.8)` (bei Endlos `null`).
  - `kind = continuous`, wenn eine `ContSKU` darauf zeigt oder der Name „Continuous“ enthält.
  - `printable` in Dots über `round(twips/4.8)`, `offsetDots = round(Offset.X/4.8)`.
  - `cornerRadiusMM` aus der SKU, wenn vorhanden (Twips), sonst 0.
  - `material` = erstes SKU-Material in Kleinbuchstaben, sonst `standard`.
  - `regions` = Vereinigung aller SKU-Regionen.
  - `minHeadDots = 672`, wenn `offsetDots + originAcross + width ≤ 672`, sonst `1248`.
- **Namen:**
  - Aus `names.json` (eigene, handgeschriebene Namen; Schlüssel = Roll-ID oder eine SKU).
  - Fallback de `"Etikett {B} × {H} mm"` / en `"Label {B} × {H} mm"` (Lesemaße gerundet, längere Kante zuerst).
  - Endlos: de `"Endlos {B} mm"` / en `"Continuous {B} mm"`.
- `names.json` enthält mindestens:
  - 11354 „Vielzweck“ / „Multi-purpose“
  - 99010 „Adresse“ / „Address“
  - 99012 „Adresse groß“ / „Large address“
  - 99014 „Versand / Namensschild“ / „Shipping / name badge“
  - 11352 „Rücksendeadresse“ / „Return address“
  - 11355 „Vielzweck klein“ / „Small multi-purpose“
  - 11356 „Namensschild“ / „Name badge“
  - 99017 „Hängeregister“ / „Suspension file“
  - S0904980 „Versand groß (4XL)“ / „Large shipping (4XL)“
  - Schlüssel, die keiner Rolle zugeordnet werden, gibt das Werkzeug als Warnung aus.
- JSON-Ausgabe: `{"version":1,"rolls":[…]}`, nach `id` sortiert, deterministisch (sort_keys, indent 1).

- [ ] **Step 1: Failing tests** gegen `MediaCatalog.bundled`:
```swift
@Test func s0722540IsMultipurpose() { let r = MediaCatalog.bundled.roll(sku: "S0722540")!; #expect(r.id == "11354"); #expect(r.skus.contains("30334"))
  #expect(abs(r.acrossMM - 57.1) < 0.05); #expect(abs(r.feedMM! - 31.8) < 0.05); #expect(r.printable.widthDots == 651); #expect(r.feedDots == 375); #expect(r.kind == .dieCut); #expect(r.minHeadDots == 672) }
@Test func searchBySizeAnyOrder() { #expect(MediaCatalog.bundled.search("32x57").first?.id == "11354"); #expect(MediaCatalog.bundled.search("57 × 32 mm").first?.id == "11354") }
@Test func searchCaseAndSpaces() { #expect(MediaCatalog.bundled.search(" s0722540 ").first?.id == "11354") }
@Test func addressRollIsPortraitOnHead() { let r = MediaCatalog.bundled.roll(sku: "99010")!; #expect(r.acrossMM < r.feedMM!) }
@Test func noDuplicateSkus() { let all = MediaCatalog.bundled.rolls.flatMap(\.skus); #expect(Set(all).count == all.count) }
@Test func continuousExists() { #expect(MediaCatalog.bundled.rolls.contains { $0.kind == .continuous && $0.feedMM == nil }) }
@Test func noDymoTextLeaks() throws { let url = Bundle.module.url(forResource: "media", withExtension: "json")!
  let s = try String(contentsOf: url, encoding: .utf8); #expect(!s.contains("SearchTerms")); #expect(!s.contains("Étiquette")); #expect(!s.contains("EnglishName")) }
```
- [ ] **Step 2: FAIL prüfen.**
- [ ] **Step 3: `import.py` und `names.json` schreiben und das Werkzeug laufen lassen.** Erwartet: Ausgabe „N rolls written“ mit N zwischen 40 und 120, keine Warnungen zu `names.json`.
- [ ] **Step 4: `LabelRoll` und `MediaCatalog` implementieren.** Suche:
  - Normalisieren: klein, Leerzeichen raus, `×`/`*` → `x`, „mm“ raus.
  - Ein Maß-Query `AxB` matcht, wenn {A, B} ≈ {Lesebreite, Lesehöhe} (±1 mm).
  - Rangfolge: exakte SKU > SKU-Präfix > Maß > Namensteil.
- [ ] **Step 5: PASS.**
- [ ] **Step 6: Rechtscheck vor dem Commit:** `grep -c -i -E "searchterms|étiquette|etiqueta|EnglishName|LongName" Sources/LabelMedia/Resources/media.json` → 0.
- [ ] **Step 7: Commit** `feat(media): Rollen-Datenbank aus Fakten + Suche (S0722540 → 11354)`.

---

### Task 5: Barcode-Encoder (1D-Module, QR-Matrix)

**Files:**
- Create: `Sources/LabelRender/Barcodes/Code128.swift`, `EANUPC.swift`, `Code39.swift`, `ITF14.swift`, `QRMatrix.swift`, `Barcode.swift`; Test: `Tests/LabelRenderTests/BarcodeTests.swift`

**Interfaces:**
- Produces:
  - `public enum BarcodeSymbology: String, Sendable, CaseIterable, Codable { case code128, ean13, ean8, upcA, code39, itf14 }`
  - `public enum BarcodeError: Error, Equatable { case empty, invalidCharacter(Character), invalidLength(expected: [Int], got: Int), badCheckDigit }`
  - `public enum Barcode { public static func modules(_ s: BarcodeSymbology, _ value: String) throws -> [Bool]; public static func humanReadable(_ s: BarcodeSymbology, _ value: String) throws -> String }`. Module ohne Ruhezone, `true` = Strich.
  - `public static func code128Checksum(_ values: [Int]) -> Int` (in `Code128.swift`)
  - `public enum QRMatrix { public static func modules(_ payload: String) throws -> [[Bool]] }`: CIQRCodeGenerator, Korrektur „M“, Ruhezone abgeschnitten.
- Regeln:
  - **EAN-13 / EAN-8 / UPC-A:**
    - 12/7/11 Ziffern → Prüfziffer anhängen.
    - 13/8/12 Ziffern → Prüfziffer prüfen.
  - **ITF-14:** 13 oder 14 Ziffern, genauso.
  - **Code 39:** A–Z, 0–9, `-. $/+%`. Kleinbuchstaben werden zu Großbuchstaben. Start/Stop `*`, Schmal:Breit = 1:3, Lücke zwischen Zeichen 1 Modul.
  - **Code 128:**
    - Ab 4 aufeinanderfolgenden Ziffern wechselt die Kodierung in Set C, sonst Set B.
    - Zeichen außerhalb von ASCII 32–126 → `invalidCharacter`.

- [ ] **Step 1: Failing tests**
```swift
@Test func ean13KnownValue() throws { let m = try Barcode.modules(.ean13, "4006381333931"); #expect(m.count == 95)
  #expect(Array(m.prefix(3)) == [true,false,true]); #expect(Array(m.suffix(3)) == [true,false,true]); #expect(Array(m[45..<50]) == [false,true,false,true,false]) }
@Test func ean13AppendsCheckDigit() throws { #expect(try Barcode.humanReadable(.ean13, "400638133393") == "4006381333931") }
@Test func ean13BadCheck() { #expect(throws: BarcodeError.badCheckDigit) { try Barcode.modules(.ean13, "4006381333932") } }
@Test func ean8Length() throws { #expect(try Barcode.modules(.ean8, "9638507").count == 67) }
@Test func upcALength() throws { #expect(try Barcode.modules(.upcA, "03600029145").count == 95) }
@Test func code128Checksum() { #expect(code128Checksum([104, 33, 34]) == 102) }
@Test func code128Structure() throws { let m = try Barcode.modules(.code128, "AB")
  #expect(m.count == 11 * 4 + 13); #expect(m.prefix(11).map { $0 ? "1" : "0" }.joined() == "11010010000"); #expect(m.suffix(13).map { $0 ? "1" : "0" }.joined() == "1100011101011") }
@Test func code128UsesSetCForDigits() throws { #expect(try Barcode.modules(.code128, "123456").count == 11 * 5 + 13) } // StartC + 3 Paare + Check
@Test func code128RejectsUmlaut() { #expect(throws: BarcodeError.invalidCharacter("ä")) { try Barcode.modules(.code128, "ä") } }
@Test func code39Uppercases() throws { #expect(try Barcode.humanReadable(.code39, "ab-1") == "*AB-1*") }
@Test func itf14() throws { #expect(try Barcode.humanReadable(.itf14, "1540014128876") == "15400141288763") }
@Test func qrMatrixSquare() throws { let q = try QRMatrix.modules("https://example.com"); #expect(q.count == q[0].count); #expect(q.count >= 21) }
@Test func emptyRejected() { #expect(throws: BarcodeError.empty) { try Barcode.modules(.code128, "") } }
```
- [ ] **Step 2: FAIL.**
- [ ] **Step 3: Implementieren.** Code-128-Tabelle: die 107 Standardmuster (Wertebereich 0–106) als String-Array, Quelle ISO/IEC 15417. EAN-Tabellen L/G/R und Paritätsmuster für die erste Ziffer.
- [ ] **Step 4: PASS.**
- [ ] **Step 5: Commit** `feat(render): Barcode-Encoder (Code128, EAN/UPC, Code39, ITF-14) und QR-Matrix`.

---

### Task 6: Geometrie, Text-Rendering und Auto-Fit

**Files:**
- Create: `Sources/LabelRender/LabelContent.swift`, `LabelGeometry.swift`, `TextLayout.swift`, `LabelRenderer.swift`, `Dithering.swift`; Test: `Tests/LabelRenderTests/GeometryTests.swift`, `TextRenderTests.swift`

**Interfaces:**
- Consumes: `LabelRoll`, `PrinterModel`, `PrintQuality`, `MonochromeBitmap`
- Produces:
  - `public enum ReadingRotation: Sendable { case upright, clockwise90, upsideDown, counterClockwise90 }`
  - `public struct LabelGeometry: Sendable { public init(roll: LabelRoll, headDots: Int, quality: PrintQuality, rotation: ReadingRotation? = nil, continuousLengthMM: Double? = nil); public let headDots: Int; public let lengthLines: Int; public let printableRect: CGRect /* in Kopfkoordinaten: x Dots, y Zeilen */; public let rotation: ReadingRotation; public let readingSizePoints: CGSize /* bedruckbarer Bereich in Lesekoordinaten, 1/72" */; public func headTransform() -> CGAffineTransform /* Lesepunkte → Kopfpixel */ }`
    - Default-Rotation: `.upright`, wenn `acrossMM >= feedMM` oder bei Endlos, sonst `.clockwise90`.
    - `lengthLines = feedDots * lpi / 300`.
    - `printableRect`: x = `offsetDots + originAcrossDots`, y = `originFeedDots * lpi/300`, Breite = `widthDots`, Höhe = `lengthDots * lpi/300`.
    - Endlos: `lengthLines` aus `continuousLengthMM` (Default 50 mm), `printableRect.y = 0`.
    - Abbildung bei `.clockwise90`: Leseposition (rx, ry) → Kopf (x = maxX − ry·sx, y = minY + rx·sy), mit sx = 300/72 und sy = lpi/72.
  - `public struct TextContent: Sendable, Equatable { public var text: String; public var bold: Bool = false; public var alignment: TextAlignment = .center; public enum TextAlignment: Sendable { case leading, center, trailing } }`
  - `public enum LabelContent: Sendable { case text(TextContent); case barcode(BarcodeContent); case qr(QRContent); case image(ImageContent) }`. `BarcodeContent`, `QRContent` und `ImageContent` definiert Task 7. In diesem Task wirft `render` für diese Fälle `RenderError.unsupported`.
  - `public enum RenderError: Error, Equatable { case emptyContent, unsupported, barcode(BarcodeError) }`
  - `public struct RenderResult: Sendable { public let bitmap: MonochromeBitmap /* Kopfkoordinaten, width = headDots, height = lengthLines */; public let preview: CGImage /* Lesekoordinaten, gesamtes Etikett, 300 dpi in beiden Achsen */; public let overflow: Bool; public let quality: PrintQuality }`
  - `public enum LabelRenderer { public static func render(_ content: LabelContent, geometry: LabelGeometry) throws -> RenderResult; public static func preferredQuality(for content: LabelContent, model: PrinterModel) -> PrintQuality }`. Bei Barcode/QR `.graphics`, wenn `model.supports600lpi`, sonst `.text`.
- Text:
  - Zeilen = `text.split("\n")`, kein automatischer Umbruch. Leerer bzw. nur aus Leerzeichen bestehender Text → `RenderError.emptyContent`.
  - Schriftgröße per binärer Suche in 0,5-pt-Schritten von 4 bis 200 pt: die größte, bei der alle Zeilen (Core Text, Systemschrift, optional fett, Zeilenabstand 1,1) in `readingSizePoints` passen.
  - Ist sie bei 4 pt immer noch zu groß: mit 4 pt rendern und `overflow = true`.
  - Vertikal zentriert, horizontal nach `alignment`.
- Rendern:
  - 8-bit-Graustufen-`CGContext` in Kopfgröße, weiß gefüllt, CTM = `headTransform()`.
  - Danach Schwellwert < 128 → schwarz.
  - Alles außerhalb von `printableRect` bleibt weiß (Clip).
- **`preview`** hat dasselbe Raster, zurückgedreht in Lesekoordinaten. Bei `.graphics` wird jede zweite Zeile ausgelassen, damit das Bild 300 × 300 dpi hat.

- [ ] **Step 1: Failing tests**
```swift
let r11354 = MediaCatalog.bundled.roll(id: "11354")!, r99010 = MediaCatalog.bundled.roll(sku: "99010")!
@Test func geometry11354() { let g = LabelGeometry(roll: r11354, headDots: 672, quality: .text)
  #expect(g.rotation == .upright); #expect(g.lengthLines == 375); #expect(Int(g.printableRect.width) == 651) }
@Test func geometry600lpiDoublesLines() { #expect(LabelGeometry(roll: r11354, headDots: 672, quality: .graphics).lengthLines == 750) }
@Test func addressIsRotated() { #expect(LabelGeometry(roll: r99010, headDots: 672, quality: .text).rotation == .clockwise90) }
@Test func textFitsAndIsCentered() throws { let g = LabelGeometry(roll: r11354, headDots: 672, quality: .text)
  let res = try LabelRenderer.render(.text(.init(text: "Keller")), geometry: g)
  #expect(!res.overflow); #expect(res.bitmap.width == 672 && res.bitmap.height == 375)
  let ink = inkBounds(res.bitmap)!; #expect(ink.minX >= Int(g.printableRect.minX)); #expect(ink.maxX < Int(g.printableRect.maxX))
  #expect(abs((ink.minX + ink.maxX)/2 - Int(g.printableRect.midX)) <= 3) }
@Test func longTextOverflows() throws { let g = LabelGeometry(roll: r11354, headDots: 672, quality: .text)
  #expect(try LabelRenderer.render(.text(.init(text: String(repeating: "Sehr langer Text ", count: 40))), geometry: g).overflow) }
@Test func emptyTextRejected() { let g = LabelGeometry(roll: r11354, headDots: 672, quality: .text)
  #expect(throws: RenderError.emptyContent) { try LabelRenderer.render(.text(.init(text: "  \n ")), geometry: g) } }
@Test func rotatedTextInkIsTallerThanWideOnHead() throws { let g = LabelGeometry(roll: r99010, headDots: 672, quality: .text)
  let ink = inkBounds(try LabelRenderer.render(.text(.init(text: "Max Mustermann")), geometry: g).bitmap)!; #expect(ink.height > ink.width) }
@Test func previewIsReadingOriented() throws { let g = LabelGeometry(roll: r99010, headDots: 672, quality: .text)
  let p = try LabelRenderer.render(.text(.init(text: "Max")), geometry: g).preview; #expect(p.width > p.height) }
```
`inkBounds(_:) -> (minX:Int,maxX:Int,minY:Int,maxY:Int,width:Int,height:Int)?` ist eine Test-Hilfsfunktion in `Tests/LabelRenderTests/Helpers.swift`.
- [ ] **Step 2: FAIL.**
- [ ] **Step 3: Implementieren.**
- [ ] **Step 4: PASS.**
- [ ] **Step 5: Commit** `feat(render): Etikettengeometrie, Rotation und Text-Auto-Fit`.

---

### Task 7: Barcode-, QR- und Bild-Layouts

**Files:**
- Modify: `Sources/LabelRender/LabelContent.swift`, `LabelRenderer.swift`, `Dithering.swift`; Test: `Tests/LabelRenderTests/BarcodeRenderTests.swift`, `ImageRenderTests.swift`

**Interfaces:**
- Produces:
  - `public struct BarcodeContent: Sendable, Equatable { public var symbology: BarcodeSymbology; public var value: String; public var showText: Bool = true }`
  - `public struct QRContent: Sendable, Equatable { public var payload: String; public var caption: String? }`
  - `public struct ImageContent: Sendable { public var image: CGImage; public var dither: Bool = true }`
- **Barcode-Layout:**
  - Striche senkrecht zur Lese-x-Achse. Ruhezone 10 Module links und rechts. Der Klartext darunter belegt 20 % der Höhe, wenn `showText`.
  - Modulbreite in Gerätepixeln entlang der Achse, auf der die Lese-x-Achse im Kopf liegt: ganzzahlig, `floor(verfügbar / (module + 20))`.
  - Ist sie < 1: mit 1 rendern, `overflow = true`. Striche werden als ganzzahlige Pixel-Rechtecke direkt ins Bitmap geschrieben, nicht über Core Graphics geglättet.
- **QR:**
  - Quadrat links, maximal groß in der Lesehöhe. Modulgröße ganzzahlig pro Achse (bei 600 lpi doppelte Zeilenzahl). Ruhezone 2 Module.
  - Die `caption` wird rechts davon mit dem Auto-Fit aus Task 6 eingepasst.
- **Bild:**
  - Seitenverhältnis erhalten, zentriert eingepasst.
  - `dither` → Floyd–Steinberg auf Graustufen, sonst Schwellwert 128.
- `BarcodeError` aus dem Encoder → `RenderError.barcode(_)`.

- [ ] **Step 1: Failing tests**
```swift
@Test func ean13BarsAreDotAligned() throws { let g = LabelGeometry(roll: r11354, headDots: 672, quality: .graphics)
  let res = try LabelRenderer.render(.barcode(.init(symbology: .ean13, value: "4006381333931")), geometry: g)
  let runs = runLengthsAcross(res.bitmap, y: res.bitmap.height / 3); let unit = runs.min()!
  #expect(unit >= 2); #expect(runs.allSatisfy { $0 % unit == 0 }) }
@Test func barcodeTooLongOverflows() throws { let narrow = MediaCatalog.bundled.rolls.filter { $0.kind == .dieCut }.min { $0.readingSizeMM.width < $1.readingSizeMM.width }!
  let g = LabelGeometry(roll: narrow, headDots: 672, quality: .graphics)
  #expect(try LabelRenderer.render(.barcode(.init(symbology: .code128, value: String(repeating: "X", count: 60))), geometry: g).overflow) }
@Test func invalidBarcodeSurfaces() { let g = LabelGeometry(roll: r11354, headDots: 672, quality: .graphics)
  #expect(throws: RenderError.barcode(.badCheckDigit)) { try LabelRenderer.render(.barcode(.init(symbology: .ean13, value: "4006381333932")), geometry: g) } }
@Test func qrModulesSquareIn600lpi() throws { let g = LabelGeometry(roll: r11354, headDots: 672, quality: .graphics)
  let res = try LabelRenderer.render(.qr(.init(payload: "https://example.com", caption: "Regal 4")), geometry: g)
  #expect(!res.overflow); let q = qrModuleSize(res.bitmap) /* Hilfsfunktion: kleinste Lauflänge im QR-Bereich je Achse */
  #expect(q.feedLines == 2 * q.acrossDots) }
@Test func preferredQuality() { let m = PrinterModel.lookup(productID: 0x20)!
  #expect(LabelRenderer.preferredQuality(for: .qr(.init(payload: "x")), model: m) == .graphics)
  #expect(LabelRenderer.preferredQuality(for: .text(.init(text: "x")), model: m) == .text)
  #expect(LabelRenderer.preferredQuality(for: .qr(.init(payload: "x")), model: PrinterModel.lookup(productID: 0x19)!) == .text) }
@Test func grayImageIsDithered() throws { /* 50-%-Grau-Bild, dither: true → zwischen 35 % und 65 % schwarze Pixel im druckbaren Bereich; dither: false → 0 % oder 100 % */ }
```
Hilfsfunktionen `runLengthsAcross` und `qrModuleSize` stehen in `Helpers.swift`. Der Rumpf des Dithering-Tests wird mit den im Kommentar genannten Schwellen ausgeschrieben.
- [ ] **Step 2: FAIL.** **Step 3: Implementieren.** **Step 4: PASS.**
- [ ] **Step 5: Commit** `feat(render): Barcode-, QR- und Bild-Layouts mit dot-genauen Modulen`.

---

### Task 8: Serien (Kopien, Zähler, CSV)

**Files:**
- Create: `Sources/MacLabelKit/CSVTable.swift`, `LabelBatch.swift`; Test: `Tests/MacLabelKitTests/CSVTableTests.swift`, `LabelBatchTests.swift`

**Interfaces:**
- Produces:
  - `public struct CSVTable: Sendable, Equatable { public let headers: [String]; public let rows: [[String: String]]; public init(parsing text: String) throws }`
    - Trennzeichen automatisch: `;`, `,` oder Tab, je nachdem, was in der ersten Zeile außerhalb von Anführungszeichen am häufigsten vorkommt.
    - RFC-4180-Quotes inklusive `""`. CRLF/LF, BOM entfernen, leere Zeilen ignorieren.
    - Fehler: `CSVError.noHeader`, `CSVError.unterminatedQuote(line: Int)`.
  - `public struct CounterSpec: Sendable, Equatable { public var start: Int = 1; public var step: Int = 1; public var minimumDigits: Int = 1 }`
  - `public enum LabelBatch { public static func expand(_ template: LabelContent, copies: Int, counter: CounterSpec?, table: CSVTable?) throws -> [LabelContent] }`
    - Platzhalter `{n}` für den Zähler, `{Spaltenname}` für CSV (Groß/Klein egal).
    - Unbekannter Platzhalter → `BatchError.unknownPlaceholder(String)`.
    - Mit CSV: ein Etikett pro Zeile × `copies`. Ohne CSV: `copies` Etiketten. Mit Zähler zählt `{n}` über alle erzeugten Etiketten.
    - Ersetzt wird in `text`, `value`, `payload` und `caption`. `copies < 1` → `BatchError.invalidCopies`.

- [ ] **Step 1: Failing tests**
```swift
@Test func germanExcelCSV() throws { let t = try CSVTable(parsing: "\u{FEFF}Name;Ort\r\n\"Müller; Hans\";Köln\r\n\r\nSchmidt;\"Bad \"\"Neu\"\"\"\r\n")
  #expect(t.headers == ["Name","Ort"]); #expect(t.rows.count == 2); #expect(t.rows[0]["Name"] == "Müller; Hans"); #expect(t.rows[1]["Ort"] == "Bad \"Neu\"") }
@Test func commaCSV() throws { #expect(try CSVTable(parsing: "a,b\n1,2\n").rows[0]["b"] == "2") }
@Test func unterminatedQuote() { #expect(throws: CSVError.unterminatedQuote(line: 2)) { try CSVTable(parsing: "a\n\"x\n") } }
@Test func counterPadding() throws { let out = try LabelBatch.expand(.text(.init(text: "Box {n}")), copies: 3, counter: .init(start: 8, step: 1, minimumDigits: 2), table: nil)
  #expect(out.compactMap { if case .text(let t) = $0 { t.text } else { nil } } == ["Box 08","Box 09","Box 10"]) }
@Test func csvPlaceholdersCaseInsensitive() throws { let t = try CSVTable(parsing: "Name;Ort\nA;X\nB;Y\n")
  let out = try LabelBatch.expand(.text(.init(text: "{name} – {ORT}")), copies: 2, counter: nil, table: t); #expect(out.count == 4) }
@Test func unknownPlaceholder() { #expect(throws: BatchError.unknownPlaceholder("plz")) { try LabelBatch.expand(.text(.init(text: "{plz}")), copies: 1, counter: nil, table: try CSVTable(parsing: "Name\nA\n")) } }
@Test func zeroCopies() { #expect(throws: BatchError.invalidCopies) { try LabelBatch.expand(.text(.init(text: "x")), copies: 0, counter: nil, table: nil) } }
```
- [ ] **Step 2: FAIL.** **Step 3: Implementieren.** **Step 4: PASS.**
- [ ] **Step 5: Commit** `feat(kit): Serienetiketten mit Zähler und CSV (Semikolon/Excel-tauglich)`.

---

### Task 9: USB-Transport und Gerätesuche

**Files:**
- Create: `Sources/LabelTransport/PrinterTransport.swift`, `USBPrinterDiscovery.swift`, `USBPrinterConnection.swift`; Test: `Tests/LabelTransportTests/TransportTests.swift`, `HardwareProbeTests.swift`

**Interfaces:**
- Consumes: `PrinterModel`, `LWClassicEncoder.statusRequest`/`versionRequest`, `LWStatus`, `LWVersion`
- Produces:
  - `public protocol PrinterTransport: Sendable { func write(_ bytes: [UInt8]) async throws; func read(maxLength: Int, timeout: Duration) async throws -> [UInt8]; func close() async }`
  - `public enum TransportError: Error, Equatable { case notFound, busy, timeout, disconnected, ioFailure(Int32) }`. `busy` entspricht `kIOReturnExclusiveAccess`, `ioFailure` trägt den IOReturn-Code.
  - `public struct DiscoveredPrinter: Sendable, Hashable, Identifiable { public let id: UInt64 /* registryEntryID des Interfaces */; public let model: PrinterModel; public let serialNumber: String?; public let locationID: UInt32? }`
  - `public enum USBPrinterDiscovery { public static func printers() -> [DiscoveredPrinter] }`
    - Matching über `IOServiceMatching("IOUSBHostInterface")` + `IOPropertyMatch {idVendor: 0x0922, bInterfaceClass: 7}`.
    - Unbekannte PIDs ignorieren, bekannte inklusive `unsupported` zurückgeben.
    - Seriennummer und locationID vom Parent-`IOUSBHostDevice` (`USB Serial Number`/`kUSBSerialNumberString`, `locationID`).
  - `public actor USBPrinterConnection: PrinterTransport { public init(printer: DiscoveredPrinter) throws }`
    - Öffnet das Interface per `IOUSBHostInterface(__ioService:options:queue:interestHandler:)`.
    - Bulk-OUT/IN-Pipe über die Endpoint-Deskriptoren, beim LW450 verifiziert 0x02/0x82.
    - `write` in 4096-Byte-Blöcken per `sendIORequest`, Timeout 10 s.
  - `public actor FileTransport: PrinterTransport { public init(url: URL) }`: schreibt Bytes in eine Datei, `read` liefert `[0x03]` für einen ESC-A-Request, sonst `[]`.
  - `extension PrinterTransport { public func status() async throws -> LWStatus; public func version() async throws -> LWVersion? }`
- Fehlerabbildung: `kIOReturnExclusiveAccess` → `.busy`; `kIOReturnTimeout` / `kIOUSBTransactionTimeout` → `.timeout`; `kIOReturnNoDevice` / `kIOReturnNotResponding` / `kIOReturnAborted` → `.disconnected`.

- [ ] **Step 1: Failing tests (ohne Hardware)**
```swift
@Test func fileTransportRecordsBytesAndFakesReady() async throws { let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  let t = FileTransport(url: url); #expect(try await t.status().isReady); try await t.write([1,2,3]); await t.close()
  #expect(try Data(contentsOf: url) == Data([0x1B,0x41,1,2,3])) }
@Test func mapsExclusiveAccess() { #expect(TransportError(ioReturn: kIOReturnExclusiveAccess) == .busy) }
@Test func mapsNoDevice() { #expect(TransportError(ioReturn: kIOReturnNoDevice) == .disconnected) }
```
`TransportError(ioReturn:)` ist ein interner Initialisierer, sichtbar über `@testable import`.
- [ ] **Step 2: Hardware-Test, standardmäßig deaktiviert:**
```swift
@Test(.enabled(if: ProcessInfo.processInfo.environment["MACLABEL_HW"] == "1"))
func realLW450StatusAndVersionOnly() async throws {
  let p = try #require(USBPrinterDiscovery.printers().first { $0.model.productID == 0x20 })
  let c = try USBPrinterConnection(printer: p); defer { Task { await c.close() } }
  #expect(try await c.status().raw & 0x01 == 0x01); #expect(try await c.version()?.modelNumber == "1750111") }
```
Dieser Test darf nur `status()` und `version()` aufrufen. Er sendet keine Raster- oder Vorschub-Kommandos (Global Constraints).
- [ ] **Step 3: FAIL.** **Step 4: Implementieren.**
- [ ] **Step 5: `swift test` → PASS; `MACLABEL_HW=1 swift test --filter realLW450` → PASS** (am Entwicklungsrechner mit angeschlossenem 450).
- [ ] **Step 6: Commit** `feat(transport): USB-Gerätesuche und -Verbindung über IOUSBHost`.

---

### Task 10: `PrintService` und gemerkte Rolle

**Files:**
- Create: `Sources/MacLabelKit/PrintService.swift`, `RollPreferences.swift`, `Localizable.xcstrings`; Test: `Tests/MacLabelKitTests/PrintServiceTests.swift`, `RollPreferencesTests.swift`

**Interfaces:**
- Consumes: alles Vorherige.
- Produces:
  - `public struct PrintRequest: Sendable { public var contents: [LabelContent]; public var roll: LabelRoll; public var model: PrinterModel; public var density: PrintDensity? /* nil = automatisch */; public var quality: PrintQuality? /* nil = automatisch */; public var rotation: ReadingRotation?; public var twinRoll: TwinRoll?; public var continuousLengthMM: Double?; public var allowOverflow: Bool = false }`
  - `public enum PrintError: Error, Equatable { case nothingToPrint, unsupportedPrinter(String), rollTooWide(rollID: String, needs: Int, has: Int), overflow(labelIndex: Int), printerNotReady(LWStatus), interrupted(printed: Int, total: Int, status: LWStatus), render(RenderError), transport(TransportError) }` mit `LocalizedError`-Texten de/en.
  - `public struct PreparedJob: Sendable { public let renders: [RenderResult]; public let bytes: [UInt8] }`
  - `public enum PrintService { public static func prepare(_ request: PrintRequest) throws -> PreparedJob; public static func print(_ request: PrintRequest, using transport: any PrinterTransport, progress: (@Sendable (Int, Int) -> Void)? = nil) async throws }`
    - Auto-Dichte: `.dark` bei Material `durable`, sonst `.normal`.
    - Auto-Qualität: die höchste `preferredQuality` aller Inhalte. Ein Job wird einheitlich gedruckt.
    - Prüfreihenfolge in `prepare`: Inhalte leer → `nothingToPrint`, Modellfamilie ≠ `.lwClassic` → `unsupportedPrinter`, `roll.minHeadDots > model.headDots` → `rollTooWide`, rendern, Overflow ohne `allowOverflow` → `overflow(labelIndex:)`.
  - `print` läuft so ab:
    - Vorab `status()` lesen; `!canPrint` → `printerNotReady`.
    - Jobheader senden, dann je Label `label` + (`betweenLabels` außer beim letzten).
    - Nach jedem Label `status()`; bei `!canPrint` → `interrupted(printed:total:status:)`, ohne weiteres Senden.
    - Am Ende `endOfJob`.
    - Transportfehler → `.transport(_)`.
  - `public struct RollPreferences: Sendable { public init(defaults: UserDefaults = .standard); public func lastRollID(forPrinterSerial: String?) -> String?; public func setLastRollID(_ id: String, forPrinterSerial: String?) }`. Schlüssel `maclabel.lastRoll.<serial|default>`.

- [ ] **Step 1: Failing tests** (mit `FileTransport` und einem `ScriptedTransport` im Test, der eine Statusfolge liefert)
```swift
@Test func rejects4XLRollOn450() { let big = MediaCatalog.bundled.roll(sku: "S0904980")!
  #expect(throws: PrintError.rollTooWide(rollID: big.id, needs: 1248, has: 672)) { try PrintService.prepare(.init(contents: [.text(.init(text: "x"))], roll: big, model: lw450)) } }
@Test func overflowBlocksUnlessAllowed() { … #expect(throws: PrintError.overflow(labelIndex: 0)) { … }; allowOverflow = true → kein Fehler }
@Test func autoQualityGraphicsForQR() throws { let job = try PrintService.prepare(.init(contents: [.qr(.init(payload: "x"))], roll: r11354, model: lw450))
  #expect(job.bytes.contains(subsequence: [0x1B,0x69])) }
@Test func durableGetsDark() throws { /* Rolle mit material "durable" aus dem Katalog → Header enthält 1B 67 */ }
@Test func notReadyBeforeStart() async { let t = ScriptedTransport(statuses: [0xA0]); await #expect(throws: PrintError.printerNotReady(LWStatus(raw: 0xA0))) { try await PrintService.print(req, using: t) }; #expect(await t.writtenRasterBytes == 0) }
@Test func interruptedAfterSecondLabel() async { let t = ScriptedTransport(statuses: [0x03, 0x03, 0xA0]) // vor Start, nach L1, nach L2
  await #expect(throws: PrintError.interrupted(printed: 2, total: 3, status: LWStatus(raw: 0xA0))) { try await PrintService.print(threeLabelReq, using: t) } }
@Test func happyPathEndsWithFormFeed() async throws { let t = ScriptedTransport(statuses: [0x03, 0x03, 0x03]); try await PrintService.print(twoLabelReq, using: t); #expect(await t.written.suffix(2) == [0x1B, 0x45]) }
@Test func rememberedRollPerSerial() { let d = UserDefaults(suiteName: UUID().uuidString)!; let p = RollPreferences(defaults: d)
  p.setLastRollID("11354", forPrinterSerial: "A"); #expect(p.lastRollID(forPrinterSerial: "A") == "11354"); #expect(p.lastRollID(forPrinterSerial: "B") == nil) }
```
`ScriptedTransport` (Test-Hilfe) zeichnet `written` auf, beantwortet ESC A der Reihe nach aus `statuses` und zählt `writtenRasterBytes` (Bytes nach dem Jobheader). Die mit `…` bzw. Kommentar markierten Testrümpfe werden mit den angegebenen Erwartungen ausgeschrieben.
- [ ] **Step 2: FAIL.** **Step 3: Implementieren.** **Step 4: PASS.**
- [ ] **Step 5: Commit** `feat(kit): PrintService mit Statusprüfung, Auto-Qualität/-Dichte und gemerkter Rolle`.

---

### Task 11: CLI `maclabel`

**Files:**
- Create: `Sources/maclabel/MacLabelCommand.swift`, `PrintCommand.swift`, `StatusCommand.swift`, `RollsCommand.swift`, `PrintersCommand.swift`; Test: `Tests/MacLabelKitTests/CLISmokeTests.swift` (startet das gebaute Binary per `Process`)

**Interfaces:**
- Consumes: `PrintService`, `USBPrinterDiscovery`, `USBPrinterConnection`, `FileTransport`, `MediaCatalog`, `RollPreferences`, `LabelBatch`, `CSVTable`
- Kommandos (Spec §4.5):
  - `maclabel print <text> [--roll <sku|id|maße>] [--copies N] [--layout text|qr|barcode] [--symbology ean13|code128|…] [--counter START] [--csv FILE] [--density light|medium|normal|dark] [--printer <serial>] [--force] [--dry-run <out.png|out.bin>]`
    - Text kann `\n` enthalten.
    - Ohne `--roll` gilt die gemerkte Rolle. Fehlt sie, folgt Exit 64 mit „Keine Rolle gewählt. Beispiel: maclabel print \"Text\" --roll 11354“.
    - Mehrdeutige Rolle (mehr als ein Treffer mit gleichem Rang) → Exit 64 mit Liste.
    - `--dry-run` mit `.png` schreibt die Vorschau des ersten Labels, mit `.bin` die Bytes. Dabei wird kein Gerät geöffnet.
    - Ein erfolgreicher Druck merkt sich die Rolle.
  - `maclabel status [--printer <serial>]` → z. B. „LabelWriter 450 (1750111, FW f0J) · bereit“. Exit 0 bei bereit, 1 bei nicht bereit, 69 ohne Drucker.
  - `maclabel rolls search <query>` → Tabelle `ID  Name  Maße  Artikelnummern`.
  - `maclabel printers` → Liste mit Modell, Seriennummer, Unterstützungsstatus.
- Fehlertexte über die `LocalizedError`-Texte aus Task 10.

- [ ] **Step 1: Failing smoke tests** (nur ohne Hardware: `rolls search 32x57` enthält „11354“; `print "Test" --roll S0722540 --dry-run /tmp/x.bin` → Exit 0 und die Datei beginnt mit 156×`1B`; `print "Test"` ohne Rolle in einer frischen Defaults-Domain (`MACLABEL_DEFAULTS_SUITE`-Umgebungsvariable) → Exit 64; `print` mit Überlänge ohne `--force` → Exit 65 mit „passt nicht“).
- [ ] **Step 2: FAIL.** **Step 3: Implementieren.** **Step 4: PASS.**
- [ ] **Step 5: Manuelle Verifikation am Gerät (nur lesend):** `swift run maclabel printers` und `swift run maclabel status` → zeigt den 450 und „bereit“.
- [ ] **Step 6: Commit** `feat(cli): maclabel print/status/rolls/printers`.

---

### Task 12: Checkliste für den ersten Druck und README

**Files:**
- Create: `docs/first-print-checklist.md`; Modify: `README.md`

- [ ] **Step 1: Checkliste schreiben.** Für den Auftraggeber, auf Deutsch, je Schritt ein Befehl und das erwartete Ergebnis:
  1. `maclabel status`
  2. Testdruck „MacLabel Test ↑“ mit Pfeil und Rahmen auf 11354 (`--layout text`)
  3. Ausrichtung prüfen (Text entlang der 57-mm-Kante, nicht gespiegelt)
  4. Ränder prüfen
  5. Adressetikett 99010 (Drehung)
  6. QR mit 600 lpi und Handy-Scan
  7. EAN-13-Scan
  8. Zwei Kopien mit Zähler (ESC G zwischen den Labels, kein Leer-Etikett)
  9. Papier-leer-Verhalten (optional)

  Für jedes mögliche Fehlbild steht dabei, welche Konstante zu ändern ist: Spiegelung → Bitreihenfolge in `MonochromeBitmap`, Drehrichtung → `ReadingRotation`-Abbildung in `LabelGeometry`, Versatz → `offsetDots`.
- [ ] **Step 2: README** um Installation (aus dem Quellcode: `swift build -c release`), CLI-Beispiele und den Status „noch nicht am Gerät gedruckt“ ergänzen.
- [ ] **Step 3: Commit** `docs: Checkliste für den ersten Testdruck und README`.
