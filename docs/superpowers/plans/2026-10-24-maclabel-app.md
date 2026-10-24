# MacLabel.app Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eine einheitliche, sandboxed SwiftUI-App `MacLabel.app` auf Basis von MacLabelKit: Hauptfenster mit Live-Vorschau, Menüleisten-Schnelldruck, Dienst, App Intents und eingebettetes CLI.

**Architecture:**
- Neues Library-Target `MacLabelApp` im bestehenden `Package.swift` mit Dienst, Modellen, Views und AppKit-Brücken, testbar mit `swift test`.
- Ein dünnes Xcode-App-Target aus `App/project.yml` (XcodeGen) liefert nur `@main`, Scenes, Intents, Services, Info.plist und Entitlements.
- Ein zweites Xcode-Target baut das CLI ins Bundle.

**Tech Stack:** Swift 6.4 (Sprachmodus 6), SwiftUI, Observation, AppKit-Brücken (`NSViewRepresentable`), Contacts/ContactsUI, App Intents, XcodeGen 2.46, `xcodebuild`, Swift Testing.

**Spec:**
- App: `docs/superpowers/specs/2026-10-24-maclabel-app-design.md`
- Hauptspec: `docs/superpowers/specs/2026-10-23-maclabel-design.md`

## Global Constraints

- **Plattform:** macOS 26+. Bundle-ID `io.github.darkspike1988.maclabel`. App-Name „MacLabel“.
- **Entitlements der App** genau diese vier:
  - `com.apple.security.app-sandbox`
  - `com.apple.security.device.usb`
  - `com.apple.security.files.user-selected.read-only`
  - `com.apple.security.temporary-exception.iokit-user-client-class` = `[AppleUSBHostFrameworkInterfaceClient]`
- **Keine Netzwerk-Entitlements, kein Netzwerkcode** (`URLSession`, `Network`) in `Sources/` oder `App/`.
- **Keine neuen Laufzeit-Abhängigkeiten.** XcodeGen ist nur Werkzeug. Die erzeugte `App/MacLabel.xcodeproj` wird nicht eingecheckt.
- **Am echten Drucker** nur `status()`/`version()` senden. Kein Druck aus Tests oder Entwicklung. Echte App-Drucke nur nach Freigabe durch den Auftraggeber.
- **Status-Polling:** alle 5 s, nur bei sichtbarem Fenster oder Panel. Nach „belegt“ 15 s Pause. Während eines Drucks pausiert.
- **Vorschau:**
  - Render-Debounce 100 ms; ein neuer Auftrag bricht den alten ab.
  - Höchstens die ersten 50 Etiketten einer Serie werden gerendert.
- **Texte:** Nutzertexte de/en über einen String Catalog in `MacLabelApp`. Sprachwahl wie `MacLabelKit.localizedBundle(preferred:)`.
- **Debug-Haken:** `MACLABEL_FAKE_PRINTER=<Pfad>` nur unter `#if DEBUG`.
- **Commits** enden mit dem Co-Authored-By-Trailer des schreibenden Modells.

## Review Focus

1. **Kein Drucker angeschlossen oder Drucker wird abgezogen**:
   - Fenster bleibt bedienbar, Status „Kein Drucker“.
   - Drucken-Knopf deaktiviert mit Hinweis, kein Absturz.
   - Abziehen während der Statusabfrage → „getrennt“, danach Neuerkennung beim nächsten Poll (Task 2, Task 5).
2. **Sehr lange Eingaben oder CSV mit Tausenden Zeilen**:
   - Vorschau bleibt flüssig: Debounce, nur die ersten 50 werden gerendert.
   - Drucken rendert alles erst beim Druck (Task 4).
3. **Erststart ohne gemerkte Rolle**: Rollen-Sheet erscheint genau einmal pro Drucker. Intent und Menüleiste ohne Rolle → Klartextfehler statt Raten (Task 5, Task 9).
4. **Dienst oder Intent bei geschlossener App**: Der Text kommt an, auch wenn die App erst gestartet wird (Task 9).
5. **CLI über Symlink aus dem Terminal**: Findet `media.json` und Strings im Bundle (Task 1, Task 9).

---

## File Structure

```
Package.swift                                  (+ Produkt/Target MacLabelApp, MacLabelAppTests)
Sources/LabelMedia/ResourceLocator.swift       Bundle-Lookup mit Symlink-Fallback
Sources/MacLabelKit/RollChoice.swift           Rollenwahl-Logik (aus CLI verschoben)
Sources/MacLabelKit/PrinterSelection.swift     Druckerwahl (aus CLI verschoben)
Sources/MacLabelApp/
  Service/LabelPrinter.swift                   actor: Druckerwahl, Status, Druck, Rolle
  Service/TransportFactory.swift               USB vs. Debug-Fake
  Model/LabelDocument.swift                    Dokument + Layouts → [LabelContent]
  Model/QRPayload.swift                        WLAN/vCard/URL-Payloads
  Model/PreviewEngine.swift                    Debounce, Abbruch, Serien-Vorschau
  Model/AppModel.swift                         @MainActor @Observable Zustand
  Model/PrinterMonitor.swift                   Polling mit Sichtbarkeitszähler
  Views/MainWindow.swift, Views/EditorForm.swift, Views/LabelPreviewView.swift,
  Views/PrintBar.swift, Views/MoreInspector.swift, Views/RollPicker.swift,
  Views/FirstRunRollSheet.swift, Views/MenuBarPanel.swift, Views/SettingsView.swift
  Bridges/ContactPickerButton.swift, Bridges/VisibilityReporter.swift
  Localizable.xcstrings, L10n.swift
Tests/MacLabelAppTests/*.swift
App/project.yml, App/MacLabel/MacLabelMain.swift, App/MacLabel/AppDelegate.swift,
App/MacLabel/Intents.swift, App/MacLabel/Info.plist, App/MacLabel/MacLabel.entitlements,
App/CLI/maclabel-cli.entitlements (leer, ohne Sandbox)
scripts/build-app.sh
docs/app-checklist.md
```

---

### Task 1: Kern-Vorbereitung – Rollenwahl, Druckerwahl, Ressourcen-Lookup, App-Target

**Files:**
- Create: `Sources/MacLabelKit/RollChoice.swift`, `Sources/MacLabelKit/PrinterSelection.swift`, `Sources/LabelMedia/ResourceLocator.swift`, `Sources/MacLabelApp/MacLabelAppModule.swift` (Platzhalter), `Tests/MacLabelAppTests/SmokeTests.swift`
- Modify:
  - `Package.swift`: Produkt `.library(name: "MacLabelApp", targets: ["MacLabelApp"])`, Target `MacLabelApp` (deps MacLabelKit; resources `.process("Localizable.xcstrings")`), Test-Target `MacLabelAppTests`
  - `Sources/LabelMedia/MediaCatalog.swift` und `Sources/MacLabelKit/L10n.swift`: Bundle-Zugriff über `ResourceLocator`
  - `Sources/maclabel/RollResolver.swift`, `PrintCommand.swift`: nutzen die verschobene Logik
- Test: `Tests/MacLabelKitTests/RollChoiceTests.swift`, `Tests/LabelMediaTests/ResourceLocatorTests.swift`

**Interfaces:**
- Produces:
  - `public enum RollChoice { case resolved(LabelRoll, alternatives: [LabelRoll]); case ambiguous([LabelRoll]); case none }`
  - `public static func choose(query: String?, catalog: MediaCatalog, remembered: String?) -> RollChoice`
    - Regeln wie bisher im CLI: exakte ID/SKU vor Suche. Alle Treffer gleicher physischer Größe (acrossDots, feedDots, kind) → Material „standard“ gewinnt, die anderen als `alternatives`.
    - `query == nil` → gemerkte Rolle oder `.none`.
  - `public enum PrinterSelection { public static func select(serial: String?, from printers: [DiscoveredPrinter]) throws -> DiscoveredPrinter }`
    - Wählt den ersten `.lwClassic` bzw. den mit passender Seriennummer.
    - Fehler `PrinterSelectionError.noPrinter`, `.unsupported(modelName: String)`, `.serialNotFound(String)` als `LocalizedError` (de/en im Kit-Katalog).
  - `public enum ResourceLocator { public static func bundle(named: String, fallback: @autoclosure () -> Bundle?) -> Bundle? }` in LabelMedia.
    - Suchreihenfolge: (1) `fallback()`, also der Bundle.module-Zugriff des Aufrufers. (2) `URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()` → `../Resources/<name>.bundle`. (3) Dasselbe Verzeichnis `/<name>.bundle`.
    - Wichtig: `Bundle.module` darf nicht per `fatalError` abbrechen. Deshalb den Bundle-Pfad selbst über `Bundle(path:)` prüfen, bevor auf `Bundle.module` zurückgegriffen wird.

- [ ] **Step 1: Failing tests**
```swift
@Test func sameSizePrefersStandard() { guard case .resolved(let r, let alt) = RollChoice.choose(query: "32x57", catalog: .bundled, remembered: nil) else { Issue.record(); return }
  #expect(r.id == "11354"); #expect(alt.map(\.id).contains("1933084")) }
@Test func exactSku() { guard case .resolved(let r, _) = RollChoice.choose(query: "S0722540", catalog: .bundled, remembered: nil) else { Issue.record(); return }; #expect(r.id == "11354") }
@Test func rememberedUsedWithoutQuery() { guard case .resolved(let r, _) = RollChoice.choose(query: nil, catalog: .bundled, remembered: "30251") else { Issue.record(); return }; #expect(r.id == "30251") }
@Test func noneWithoutQueryOrMemory() { guard case .none = RollChoice.choose(query: nil, catalog: .bundled, remembered: nil) else { Issue.record(); return } }
@Test func differentSizesAmbiguous() { guard case .ambiguous(let list) = RollChoice.choose(query: "adress", catalog: .bundled, remembered: nil) else { Issue.record(); return }; #expect(list.count > 1) }
@Test func selectionPrefersClassic() throws { /* [unsupported SE450, LW450] → LW450; nur SE450 → .unsupported("LabelWriter SE450"); [] → .noPrinter */ }
@Test func locatorFindsBundleBesideSymlinkedExecutable() throws { /* tmp: dir/Contents/MacOS/tool + dir/Contents/Resources/X.bundle, Symlink link → tool; mit argv0 = link → findet X.bundle */ }
```
`ResourceLocator` bekommt dafür eine interne Variante `bundle(named:fallback:executableURL:)`, damit der Test argv0 injizieren kann. Die mit Kommentar beschriebenen Rümpfe werden mit den genannten Erwartungen ausgeschrieben.
- [ ] **Step 2: FAIL.**
- [ ] **Step 3: Implementieren und das CLI auf `RollChoice`/`PrinterSelection` umstellen.** Verhalten und Exit-Codes des CLI bleiben gleich; die bestehenden `maclabelCLITests` müssen weiter grün sein.
- [ ] **Step 4: `swift build` ohne Warnungen, `swift test` → PASS.**
- [ ] **Step 5: Commit** `refactor(kit): Rollen- und Druckerwahl in den Kern, Ressourcen-Lookup für CLI im App-Bundle`.

---

### Task 2: `LabelPrinter` – UI-unabhängiger Druckdienst

**Files:**
- Create: `Sources/MacLabelApp/Service/LabelPrinter.swift`, `Sources/MacLabelApp/Service/TransportFactory.swift`
- Test: `Tests/MacLabelAppTests/LabelPrinterTests.swift`

**Interfaces:**
- Consumes: `USBPrinterDiscovery`, `USBPrinterConnection`, `FileTransport`, `PrintService`, `PrintRequest`, `RollPreferences`, `PrinterSelection`
- Produces:
  - `public protocol TransportFactory: Sendable { func printers() -> [DiscoveredPrinter]; func open(_ printer: DiscoveredPrinter) throws -> any PrinterTransport }`
  - `public struct USBTransportFactory: TransportFactory`
  - `#if DEBUG public struct FakeTransportFactory: TransportFactory { public init(fileURL: URL) }` meldet einen `DiscoveredPrinter` (id 1, Modell 0x20, Seriennummer "FAKE") und öffnet `FileTransport`.
  - `public static func makeDefault(environment: [String: String] = ProcessInfo.processInfo.environment) -> any TransportFactory` (Fake nur unter DEBUG und gesetzter `MACLABEL_FAKE_PRINTER`).
  - `public enum PrinterState: Equatable, Sendable { case noPrinter, unsupported(String), ready(name: String), notReady(name: String, reason: String), busy(name: String), disconnected, error(String) }`
  - `public actor LabelPrinter`:
    - `public init(factory: any TransportFactory = makeDefault(), preferences: RollPreferences = .standard())`
    - `public func availablePrinters() -> [DiscoveredPrinter]`
    - `public func state(for printer: DiscoveredPrinter?) async -> PrinterState`: öffnen, `status()`, schließen. `.busy` bei `TransportError.busy`. Kein Drucker → `.noPrinter`. Nicht unterstütztes Modell → `.unsupported(name)`.
    - `public func rememberedRoll(for printer: DiscoveredPrinter) -> LabelRoll?`, `public func remember(_ roll: LabelRoll, for printer: DiscoveredPrinter)`
    - `public func print(_ request: PrintRequest, on printer: DiscoveredPrinter, progress: @escaping @Sendable (Int, Int) -> Void) async throws`: öffnen, `PrintService.print`, schließen (auch bei Fehler/Abbruch), danach `remember`.

- [ ] **Step 1: Failing tests** (mit einem Test-`TransportFactory`, der `ScriptedTransport`-artig Status liefert)
```swift
@Test func noPrinterState() async { let p = LabelPrinter(factory: StubFactory(printers: []), preferences: tmpPrefs()); #expect(await p.state(for: nil) == .noPrinter) }
@Test func busyState() async { /* open wirft TransportError.busy → .busy(name: "LabelWriter 450") */ }
@Test func readyState() async { /* status 0x03 → .ready(name: "LabelWriter 450") */ }
@Test func paperOutState() async { /* status 0xA0 → .notReady(name:…, reason: localized "out of paper"-Text) */ }
@Test func printRemembersRollAndClosesTransport() async throws { /* nach print: rememberedRoll == 11354, transport.closed == true */ }
@Test func printClosesTransportOnError() async { /* status 0xA0 → wirft printerNotReady, closed == true, keine Rolle gemerkt */ }
#if DEBUG
@Test func fakeFactoryFromEnvironment() { #expect(makeDefault(environment: ["MACLABEL_FAKE_PRINTER": "/tmp/x.bin"]) is FakeTransportFactory) }
#endif
@Test func defaultIsUSB() { #expect(makeDefault(environment: [:]) is USBTransportFactory) }
```
Die mit Kommentar beschriebenen Rümpfe werden mit den genannten Erwartungen ausgeschrieben.
- [ ] **Step 2: FAIL.** **Step 3: Implementieren.** **Step 4: PASS.**
- [ ] **Step 5: Commit** `feat(app): LabelPrinter-Dienst mit Status, Druck und Debug-Fake`.

---

### Task 3: `LabelDocument` und QR-Payloads

**Files:**
- Create: `Sources/MacLabelApp/Model/LabelDocument.swift`, `Sources/MacLabelApp/Model/QRPayload.swift`
- Test: `Tests/MacLabelAppTests/LabelDocumentTests.swift`, `QRPayloadTests.swift`

**Interfaces:**
- Produces:
  - `public enum LabelLayout: String, CaseIterable, Sendable { case text, address, barcode, qr, image }`
  - `public enum QRKind: String, CaseIterable, Sendable { case text, url, wifi, contact }`
  - `public struct LabelDocument: Sendable, Equatable` mit den Feldern:
    - `layout`
    - `text: String`, `bold: Bool`, `alignment: TextContent.TextAlignment`
    - `addressText: String`
    - `symbology: BarcodeSymbology`, `barcodeValue: String`, `showBarcodeText: Bool`
    - `qrKind`, `qrText`, `wifiSSID`, `wifiPassword`, `wifiSecurity` (`WPA`|`WEP`|`nopass`), `contactName`, `contactPhone`, `contactEmail`, `qrCaption: String`
    - `image: CGImage?` (Equatable über Identität), `ditherImage: Bool`
    - `copies: Int = 1`, `counter: CounterSpec?`, `csv: CSVTable?`
    - `density: PrintDensity?`, `quality: PrintQuality?`, `rotation: ReadingRotation?`, `continuousLengthMM: Double = 50`
  - `public func template() throws -> LabelContent`. Adresse → `.text` mit `.leading`. QR → `.qr(QRContent(payload: QRPayload.make(…), caption: qrCaption.isEmpty ? nil : qrCaption))`. Bild ohne `image` → `DocumentError.missingImage`.
  - `public func contents(limit: Int? = nil) throws -> [LabelContent]` über `LabelBatch.expand(template(), copies:, counter:, table:)`, danach auf `limit` gekürzt.
  - `public func labelCount() throws -> Int` = (csv?.rows.count ?? 1) × copies.
  - `public func placeholderNames() -> [String]` = csv?.headers ?? [] (+ "n" wenn counter).
  - `public enum QRPayload { public static func make(kind:text:ssid:password:security:name:phone:email:) -> String }`
    - WLAN: `WIFI:T:<sec>;S:<ssid>;P:<pw>;;`, Sonderzeichen `\ ; , : "` mit Backslash escapen.
    - Kontakt: vCard 3.0 mit `BEGIN:VCARD\r\nVERSION:3.0\r\nFN:…\r\nTEL:…\r\nEMAIL:…\r\nEND:VCARD`, leere Felder weglassen.
    - URL: ohne Schema wird `https://` vorangestellt.

- [ ] **Step 1: Failing tests**
```swift
@Test func wifiEscaping() { #expect(QRPayload.make(kind: .wifi, text: "", ssid: "Haus;Netz", password: "a:b", security: "WPA", name: "", phone: "", email: "") == #"WIFI:T:WPA;S:Haus\;Netz;P:a\:b;;"#) }
@Test func vcardOmitsEmpty() { let v = QRPayload.make(kind: .contact, text: "", ssid: "", password: "", security: "", name: "Max", phone: "", email: "m@x.de")
  #expect(v == "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Max\r\nEMAIL:m@x.de\r\nEND:VCARD") }
@Test func urlGetsScheme() { #expect(QRPayload.make(kind: .url, text: "example.com", ssid: "", password: "", security: "", name: "", phone: "", email: "") == "https://example.com") }
@Test func addressIsLeading() throws { var d = LabelDocument(); d.layout = .address; d.addressText = "A\nB"
  guard case .text(let t) = try d.template() else { Issue.record(); return }; #expect(t.alignment == .leading && t.text == "A\nB") }
@Test func csvTimesCopiesCount() throws { var d = LabelDocument(); d.text = "{Name}"; d.copies = 2; d.csv = try CSVTable(parsing: "Name\nA\nB\nC\n"); #expect(try d.labelCount() == 6) }
@Test func limitCapsContents() throws { var d = LabelDocument(); d.text = "x"; d.copies = 500; #expect(try d.contents(limit: 50).count == 50) }
@Test func imageMissing() { var d = LabelDocument(); d.layout = .image; #expect(throws: DocumentError.missingImage) { try d.template() } }
@Test func placeholderNames() throws { var d = LabelDocument(); d.csv = try CSVTable(parsing: "Name;Ort\nA;B\n"); d.counter = CounterSpec(); #expect(d.placeholderNames() == ["Name", "Ort", "n"]) }
```
- [ ] **Step 2: FAIL.** **Step 3: Implementieren.** `DocumentError` ist `LocalizedError` (de/en im App-Katalog, siehe Task 5). **Step 4: PASS.**
- [ ] **Step 5: Commit** `feat(app): LabelDocument mit Layouts, Serien und QR-Payloads`.

---

### Task 4: `PreviewEngine`

**Files:**
- Create: `Sources/MacLabelApp/Model/PreviewEngine.swift`
- Test: `Tests/MacLabelAppTests/PreviewEngineTests.swift`

**Interfaces:**
- Consumes: `LabelDocument`, `PrintService.prepare`, `PrintRequest`
- Produces:
  - `public struct PreviewResult: Sendable { public let pages: [RenderResult]; public let totalLabels: Int; public let overflowIndices: [Int]; public let error: String? }`
  - `@MainActor public final class PreviewEngine` mit:
    - `public init(debounce: Duration = .milliseconds(100), maxPages: Int = 50)`
    - `public func update(document: LabelDocument, roll: LabelRoll?, model: PrinterModel) async -> PreviewResult?`
      - Gibt `nil` zurück, wenn ein neuerer Aufruf diesen überholt hat.
      - Rendert im Hintergrund (`Task.detached`) über `PrintService.prepare` mit `allowOverflow: true` und `document.contents(limit: maxPages)`.
      - Fehler (leer, ungültiger Barcode, fehlendes Bild, keine Rolle) → `PreviewResult(pages: [], …, error: localizedDescription)`.
  - Ohne Rolle: `error` = „Keine Rolle gewählt“. Ohne Drucker verwendet der Aufrufer das Modell 0x20 (LW450) als Vorschau-Standard.

- [ ] **Step 1: Failing tests**
```swift
@Test @MainActor func rendersFirstPage() async { let e = PreviewEngine(debounce: .zero); var d = LabelDocument(); d.text = "Keller"
  let r = await e.update(document: d, roll: roll11354, model: lw450)!; #expect(r.pages.count == 1 && r.totalLabels == 1 && r.error == nil) }
@Test @MainActor func newerCallSupersedesOlder() async { let e = PreviewEngine(debounce: .milliseconds(100)); var a = LabelDocument(); a.text = "A"; var b = a; b.text = "B"
  async let first = e.update(document: a, roll: roll11354, model: lw450); async let second = e.update(document: b, roll: roll11354, model: lw450)
  let (r1, r2) = await (first, second); #expect(r1 == nil); #expect(r2 != nil) }
@Test @MainActor func capsPagesAt50() async { /* copies 120 → pages.count == 50, totalLabels == 120 */ }
@Test @MainActor func overflowReported() async { /* sehr langer Text → overflowIndices == [0], pages.count == 1 */ }
@Test @MainActor func emptyTextIsError() async { /* text "" → error != nil, pages leer */ }
```
Die mit Kommentar beschriebenen Rümpfe werden mit den genannten Erwartungen ausgeschrieben.
- [ ] **Step 2: FAIL.** **Step 3: Implementieren.** **Step 4: PASS.**
- [ ] **Step 5: Commit** `feat(app): PreviewEngine mit Debounce, Abbruch und Seitenlimit`.

---

### Task 5: `AppModel`, `PrinterMonitor`, Lokalisierung der App

**Files:**
- Create: `Sources/MacLabelApp/Model/AppModel.swift`, `Sources/MacLabelApp/Model/PrinterMonitor.swift`, `Sources/MacLabelApp/Localizable.xcstrings`, `Sources/MacLabelApp/L10n.swift`
- Test: `Tests/MacLabelAppTests/AppModelTests.swift`, `PrinterMonitorTests.swift`

**Interfaces:**
- Consumes: `LabelPrinter`, `PreviewEngine`, `LabelDocument`, `RollChoice`
- Produces:
  - `@MainActor @Observable public final class PrinterMonitor`:
    - `public init(printer: LabelPrinter, interval: Duration = .seconds(5), busyBackoff: Duration = .seconds(15))`
    - `public private(set) var state: PrinterState`
    - `public func visibilityChanged(visible: Bool)` (zählt sichtbare Fenster/Panels; >0 → Polling an)
    - `public func pause()`, `public func resume()`, `public func refreshNow() async`
  - `@MainActor @Observable public final class AppModel`:
    - `public init(printer: LabelPrinter = LabelPrinter(), preview: PreviewEngine = PreviewEngine())`
    - `var document: LabelDocument` (didSet → Vorschau aktualisieren), `var roll: LabelRoll?`, `var printers: [DiscoveredPrinter]`, `var selectedPrinter: DiscoveredPrinter?`, `var previewResult: PreviewResult?`, `var previewPage: Int`
    - `var needsRollChoice: Bool`: true, wenn ein Drucker gewählt ist und keine Rolle gemerkt ist; wird beim ersten Erscheinen eines Druckers ausgewertet.
    - `var printPhase: PrintPhase` (`.idle`, `.printing(done: Int, total: Int)`, `.finished(Int)`, `.cancelled(printed: Int, total: Int)`, `.failed(String)`)
    - `var monitor: PrinterMonitor`
    - `public func refreshPrinters() async`, `public func chooseRoll(_ roll: LabelRoll)` (merken), `public func print(allowOverflow: Bool) async`, `public func cancelPrint()`
    - `public func load(text: String)` für Dienst/Intent: Layout `.text`, Text setzen.
  - `L10n` analog zu `MacLabelKit`: `localizedBundle(preferred:)` für den App-Katalog. Alle neuen Nutzertexte de/en.
    - Pflichttext für den Abbruch (de): „Abgebrochen nach %lld von %lld Etiketten. Ggf. Vorschubtaste drücken, um ein angefangenes Etikett auszugeben.“
- Verhalten:
  - Vor dem Drucken: kein Drucker oder nicht unterstütztes Modell → `.failed(Text)`.
  - Während des Drucks: `monitor.pause()`, danach `resume()`.
  - Fortschritt aktualisiert `printPhase`. Abbruch beendet den Druck-Task und setzt `.cancelled`.

- [ ] **Step 1: Failing tests** (mit `LabelPrinter` über eine Stub-Factory, `debounce: .zero`)
```swift
@Test @MainActor func firstPrinterWithoutRollNeedsChoice() async { let m = model(printers: [lw450], remembered: nil); await m.refreshPrinters(); #expect(m.needsRollChoice) }
@Test @MainActor func rememberedRollSelected() async { let m = model(printers: [lw450], remembered: "11354"); await m.refreshPrinters(); #expect(m.roll?.id == "11354" && !m.needsRollChoice) }
@Test @MainActor func printWithoutPrinterFails() async { let m = model(printers: [], remembered: nil); m.roll = roll11354; m.document.text = "x"; await m.print(allowOverflow: false); guard case .failed = m.printPhase else { Issue.record(); return } }
@Test @MainActor func printProgressAndFinish() async { /* 2 Kopien, Status immer 0x03 → printPhase endet .finished(2) */ }
@Test @MainActor func cancelSetsCancelled() async { /* Stub-Transport blockiert nach Label 1; cancelPrint() → .cancelled(printed: 1, total: 3) */ }
@Test @MainActor func monitorPollsOnlyWhenVisible() async { /* interval .milliseconds(20); unsichtbar 100 ms → 0 Statusabfragen; sichtbar 100 ms → ≥ 2 */ }
@Test @MainActor func monitorBacksOffWhenBusy() async { /* busy → nächste Abfrage frühestens nach busyBackoff (.milliseconds(200)) */ }
@Test func germanCancelText() { #expect(L10n.text("cancelled", preferred: ["de"], 1, 3).hasPrefix("Abgebrochen nach 1 von 3")) }
```
Die mit Kommentar beschriebenen Rümpfe werden mit den genannten Erwartungen ausgeschrieben. Wie `L10n.text` intern heißt, darf angepasst werden; der Test prüft den aufgelösten deutschen Text.
- [ ] **Step 2: FAIL.** **Step 3: Implementieren.** **Step 4: PASS.**
- [ ] **Step 5: Commit** `feat(app): AppModel und PrinterMonitor mit Sichtbarkeits-Polling`.

---

### Task 6: Hauptfenster (Views)

**Files:**
- Create: `Sources/MacLabelApp/Views/MainWindow.swift`, `EditorForm.swift`, `LabelPreviewView.swift`, `PrintBar.swift`, `MoreInspector.swift`, `RollPicker.swift`, `FirstRunRollSheet.swift`, `Sources/MacLabelApp/Bridges/VisibilityReporter.swift`
- Test: `Tests/MacLabelAppTests/ViewSmokeTests.swift`

**Interfaces:**
- Consumes: `AppModel`
- Produces: `public struct MainWindow: View { public init() }` (liest `AppModel` aus `@Environment`)
- Inhalt nach App-Spec §2.1, §6.4 und Hauptspec §4.4:
  - **Toolbar:** Rollen-Chip „11354 · 57 × 32 mm“, öffnet `RollPicker` (Suchfeld, Treffer gleicher Größe gruppiert, Standard zuerst), ⌘L. Status als farbiger Punkt plus Text aus `PrinterState`.
  - **Links `EditorForm`:** Layout-Picker (segmented, ⌘1…⌘5). Felder je Layout. Platzhalter-Menü „Feld einfügen“ aus `document.placeholderNames()`.
  - **Rechts `LabelPreviewView`:**
    - Zeigt `previewResult.pages[previewPage].preview` auf weißer Etikettenfläche mit Eckenradius und dezentem Schatten.
    - Vorschubpfeil am Rand.
    - Roter Rahmen plus Hinweis „Passt nicht aufs Etikett“ bei Überlänge.
    - Blätter-Steuerung „1 von N“ bei Serien.
    - Fehlertext zentriert, wenn `error`.
    - VoiceOver: Label = Etikettentext.
  - **Unten `PrintBar`:** Kopien-Stepper (1…999), „Drucken“ (⌘P, `.borderedProminent`). Bei Überlänge fragt ein Alert „Trotzdem drucken?“. Während des Drucks: Fortschritt „Etikett 3 von 10“ plus „Abbrechen“. Danach Ergebnis-/Fehlertext.
  - **`.inspector` „Mehr“** (Toolbar-Knopf):
    - Dichte und Modus (Auto + Werte)
    - Drehung (Auto/0°/90°/180°/270°)
    - Zähler (an/aus, Start, Stellen)
    - CSV (Datei wählen und Drop, Spalten anzeigen, entfernen)
    - Endlos-Länge (nur bei Endlosrolle)
  - **`FirstRunRollSheet`** bei `needsRollChoice`. Schnellwahl: 11354, 99010, 99012, 11352, 99014, S0904980 (nur zeigen, wenn im Katalog und für den Kopf passend). Dazu ein Suchfeld.
  - **`VisibilityReporter`:** `NSViewRepresentable`, beobachtet `NSWindow.didChangeOcclusionStateNotification` bzw. `isVisible` und ruft `monitor.visibilityChanged`.
  - Mindestgröße 720 × 460. Systemfarben, SF Symbols.
- Vor dem Schreiben den Skill `swiftui-pro` laden und seine Regeln befolgen.

- [ ] **Step 1: Failing smoke tests:** `ImageRenderer` bzw. `NSHostingView` für `MainWindow` mit einem `AppModel` (Stub) in den Zuständen kein Drucker, bereit mit Vorschau, Überlänge und Drucken läuft. Jeweils muss eine nicht leere Ansicht entstehen, ohne Crash. `RollPicker`-Filterlogik als reine Funktion `RollPicker.groups(for query: String, catalog:) -> [[LabelRoll]]` testen: „32x57“ ergibt eine Gruppe mit 11354 zuerst.
- [ ] **Step 2: FAIL.** **Step 3: Implementieren.** **Step 4: PASS.**
- [ ] **Step 5: Commit** `feat(app): Hauptfenster mit Rollenwahl, Editor, Live-Vorschau und Druckleiste`.

---

### Task 7: Kontakte, Bild-Import, CSV-Drop

**Files:**
- Create: `Sources/MacLabelApp/Bridges/ContactPickerButton.swift`, `Sources/MacLabelApp/Model/ContactFormatter.swift`, `Sources/MacLabelApp/Model/ImportHelpers.swift`
- Modify: `EditorForm.swift`, `MoreInspector.swift`
- Test: `Tests/MacLabelAppTests/ImportTests.swift`

**Interfaces:**
- Produces:
  - `public enum ContactFormatter { public static func addressText(name: String, organization: String?, postal: CNPostalAddress?) -> String }`: Name, Firma (falls vorhanden), dann `CNPostalAddressFormatter` (Stil mailingAddress), Leerzeilen entfernt.
  - `ContactPickerButton`: `NSViewRepresentable` mit `CNContactPicker` (als Popover am Knopf). Callback `(CNContact) -> Void`.
  - `public enum ImportHelpers { public static func loadCSV(url: URL) throws -> CSVTable` (UTF-8, Fallback Windows-1252; leere Tabelle → `DocumentError.emptyCSV`) `; public static func loadImage(url: URL) throws -> CGImage }` (über `CGImageSource`).
  - Drag & Drop: `.dropDestination(for: URL.self)`. CSV-Endungen `csv`/`txt` → CSV, Bildtypen → Bild-Layout.

- [ ] **Step 1: Failing tests**
```swift
@Test func formatsGermanAddress() { let a = CNMutablePostalAddress(); a.street = "Musterstraße 1"; a.postalCode = "12345"; a.city = "Musterstadt"; a.isoCountryCode = "de"
  #expect(ContactFormatter.addressText(name: "Max Mustermann", organization: nil, postal: a) == "Max Mustermann\nMusterstraße 1\n12345 Musterstadt") }
@Test func windows1252CSV() throws { /* Datei mit "Name\nMüller\n" in .windowsCP1252 → rows[0]["Name"] == "Müller" */ }
@Test func emptyCSVRejected() { /* "Name\n" → throws DocumentError.emptyCSV */ }
@Test func loadsPNG() throws { /* 2×2-PNG schreiben, laden → width == 2 */ }
```
Die mit Kommentar beschriebenen Rümpfe werden mit den genannten Erwartungen ausgeschrieben. Hinweis: Enthält die formatierte Adresse ein Land, wenn der Systemstandort dazu passt, wird das Land weggelassen. Bei Bedarf den Formatter mit `postal.isoCountryCode` an die Locale anpassen.
- [ ] **Step 2: FAIL.** **Step 3: Implementieren.** **Step 4: PASS.**
- [ ] **Step 5: Commit** `feat(app): Kontakte, Bild- und CSV-Import mit Drag & Drop`.

---

### Task 8: Menüleisten-Panel und Einstellungen

**Files:**
- Create: `Sources/MacLabelApp/Views/MenuBarPanel.swift`, `Sources/MacLabelApp/Views/SettingsView.swift`, `Sources/MacLabelApp/Model/AppSettings.swift`
- Test: `Tests/MacLabelAppTests/MenuBarPanelTests.swift`

**Interfaces:**
- Produces:
  - `public struct MenuBarPanel: View`:
    - Textfeld (mehrzeilig, Fokus beim Öffnen), Statuszeile, Rolle (Text plus „Ändern…“, öffnet das Hauptfenster per `openWindow(id: "main")`), Knopf „Drucken“.
    - Bei Überlänge: kein Druck, Hinweis „Text zu lang – im Fenster öffnen“ als Knopf, der das Hauptfenster mit dem Text öffnet.
    - Meldet seine Sichtbarkeit an `monitor`.
  - `public struct SettingsView: View`:
    - Standarddrucker (Picker bei mehreren Druckern)
    - „In der Menüleiste anzeigen“ (Bool, `@AppStorage("showMenuBarExtra")`, Standard true)
    - „Druckerstatus automatisch abfragen“ (`@AppStorage("statusPolling")`, Standard true)
    - Abschnitt „Kommandozeile“ mit kopierbarem Befehl `ln -sf "<Bundle-Pfad>/Contents/MacOS/maclabel" /usr/local/bin/maclabel` und dem Hinweis, dass App und CLI getrennte gemerkte Rollen haben
  - `public struct AppSettings` kapselt die Schlüssel.
  - Panel-Logik als testbare Funktion `MenuBarPanel.action(for document: LabelDocument, preview: PreviewResult?) -> PanelAction` (`.print`, `.openWindow`, `.disabled(String)`).

- [ ] **Step 1: Failing tests:** Überlänge → `.openWindow`; leerer Text → `.disabled`; normal → `.print`; ohne Rolle → `.disabled("Keine Rolle gewählt")`.
- [ ] **Step 2: FAIL.** **Step 3: Implementieren.** **Step 4: PASS.**
- [ ] **Step 5: Commit** `feat(app): Menüleisten-Schnelldruck und Einstellungen`.

---

### Task 9: Xcode-App, Dienst, App Intents, eingebettetes CLI, Build-Skript

**Files:**
- Create:
  - `App/project.yml`
  - `App/MacLabel/MacLabelMain.swift`: `@main struct MacLabelMain: App` mit
    - `WindowGroup(id: "main")`
    - `MenuBarExtra("MacLabel", systemImage: "printer", isInserted:)` mit `.menuBarExtraStyle(.window)`
    - `Settings`
    - `.commands`: Drucken ⌘P, „Kommandozeilenwerkzeug installieren…“
  - `App/MacLabel/AppDelegate.swift`: `NSApplicationDelegateAdaptor`, `NSApp.servicesProvider`, Selektor `printLabel(_:userData:error:)`
  - `App/MacLabel/Intents.swift`
  - `App/MacLabel/Info.plist`, `App/MacLabel/MacLabel.entitlements`, `App/CLI/maclabel-cli.entitlements`, `App/MacLabel/Assets.xcassets` (App-Icon: einfaches Etikett-Symbol, eigenes Motiv)
  - `scripts/build-app.sh`
  - `docs/app-checklist.md`
- Modify: `.gitignore` (`App/MacLabel.xcodeproj`, `build/`)

**Interfaces:**
- Consumes: `MacLabelApp` (`MainWindow`, `MenuBarPanel`, `SettingsView`, `AppModel`, `LabelPrinter`)
- `project.yml`:
  - Paket lokal `path: ..`
  - Target `MacLabel` (application, deployment 26.0, Produkt-Dep `MacLabelApp`, Entitlements, Info.plist, `ENABLE_HARDENED_RUNTIME: YES`, `CODE_SIGN_IDENTITY: "-"`)
  - Target `maclabel-cli` (tool):
    - Sources `../Sources/maclabel`, Deps `MacLabelKit` + `ArgumentParser`, `PRODUCT_NAME: maclabel`, eigene leere Entitlements ohne Sandbox
    - Ressourcen-Bundles (`MacLabelKit_*.bundle`) per Copy-Files-Phase nach `Contents/Resources`
    - Wird als Abhängigkeit von `MacLabel` mit Copy-Files-Phase nach `Contents/MacOS` eingebettet, signiert mit `CodeSignOnCopy`
- **Info.plist** (beide Texte de/en über InfoPlist-Strings):
  - `NSServices`: `NSMenuItem.default = "Mit MacLabel drucken"`, `NSMessage = printLabel`, `NSSendTypes = [NSStringPboardType, public.utf8-plain-text]`, `NSPortName = MacLabel`
  - `NSContactsUsageDescription`
  - `LSApplicationCategoryType = public.app-category.productivity`
- **Dienst:** Text → `AppModel.load(text:)`, Hauptfenster öffnen und aktivieren. Kommt der Aufruf vor dem Fensteraufbau, wird der Text gepuffert und beim Erscheinen übernommen.
- **Intents:**
  - `PrintLabelIntent`
    - `@Parameter text: String`, `copies: Int = 1`, `rollQuery: String?`, `openAppWhenRun = false`
    - Ablauf: `LabelPrinter` → Drucker wählen → `RollChoice` (Abfrage oder gemerkt) → Fehler in Klartext bei `.none` oder `.ambiguous`, bei Überlänge (`allowOverflow: false`), bei belegtem oder nicht bereitem Drucker.
    - Rückgabe: Dialog „N Etiketten gedruckt“.
  - `PrinterStatusIntent` liefert den Text des `PrinterState`.
  - `AppShortcutsProvider` mit deutschen und englischen Phrasen („Etikett mit \(.applicationName) drucken“).
- **`scripts/build-app.sh [--install]`:**
  - `xcodegen generate --spec App/project.yml`
  - `xcodebuild -project App/MacLabel.xcodeproj -scheme MacLabel -configuration Release -derivedDataPath build/dd build`
  - Kopiert nach `build/MacLabel.app`, `codesign --verify --deep --strict`, gibt die Entitlements aus.
  - `--install` kopiert nach `~/Applications` und ruft `/System/Library/CoreServices/pbs -update` auf.

- [ ] **Step 1: Verifikations-Skript zuerst:** `scripts/verify-app.sh` prüft am gebauten Bundle und schlägt fehl, wenn etwas fehlt:
  1. `codesign -d --entitlements -` zeigt genau die vier erlaubten Entitlements und **kein** `network`.
  2. `Contents/MacOS/maclabel` existiert. Über einen Symlink in einem Temp-Verzeichnis liefert `maclabel rolls search 32x57` Exit 0 und „11354“.
  3. `plutil -extract NSServices` ist vorhanden.
  4. `grep -rE "URLSession|import Network" Sources App` findet nichts.
- [ ] **Step 2: `scripts/verify-app.sh` vor dem Bauen → FAIL** (Bundle fehlt).
- [ ] **Step 3: Projekt, App-Code, Intents, Dienst, Build-Skript implementieren.**
- [ ] **Step 4: `scripts/build-app.sh && scripts/verify-app.sh` → PASS.** Zusätzlich `swift test` grün.
- [ ] **Step 5: Hardware, nur Status:**
  - App mit `open build/MacLabel.app` starten. Status im Fenster muss „LabelWriter 450 · bereit“ zeigen (Screenshot über `screencapture -l` des Fensters oder manuell). Damit ist der sandboxed USB-Zugriff verifiziert.
  - Kein Druck. Zusätzlich `log show --predicate 'process == "MacLabel"' --last 2m | grep -i deny` → keine USB- oder Sandbox-Verweigerung.
- [ ] **Step 6: `docs/app-checklist.md`** (für den Auftraggeber, de):
  - Fenster-Erstdruck mit Rolle 11354
  - Menüleisten-Druck
  - Dienst aus TextEdit („Dienste → Mit MacLabel drucken“; App muss in `~/Applications` liegen, dafür `scripts/build-app.sh --install`)
  - Kurzbefehl „Etikett drucken“
  - Adresse aus Kontakte
  - CSV-Serie
  - Abbrechen mitten im Druck
  - CLI-Symlink
- [ ] **Step 7: README** um „App bauen und starten“ ergänzen.
- [ ] **Step 8: Commit** `feat(app): MacLabel.app mit Menüleiste, Dienst, Kurzbefehlen und eingebettetem CLI`.
