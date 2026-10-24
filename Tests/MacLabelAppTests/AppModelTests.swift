import Foundation
import Testing
import LabelMedia
import LabelProtocol
import LabelTransport
import MacLabelKit
@testable import MacLabelApp

// MARK: - Fixtures shared with PrinterMonitorTests

let appLW450 = PrinterModel.lookup(productID: 0x20)!
let appLW450Printer = DiscoveredPrinter(id: 1, model: appLW450, serialNumber: "S1", locationID: nil)
let appLW550Printer = DiscoveredPrinter(id: 2, model: PrinterModel.lookup(productID: 0x28)!, serialNumber: "S2", locationID: nil)
let appRoll11354 = MediaCatalog.bundled.roll(id: "11354")!

/// Thread-safe counter of device opens and status queries.
final class DeviceLog: @unchecked Sendable {
    private let lock = NSLock()
    private var openCount = 0
    private var statusCount = 0
    func opened() { lock.withLock { openCount += 1 } }
    func queried() -> Int { lock.withLock { statusCount += 1; return statusCount } }
    var opens: Int { lock.withLock { openCount } }
    var statusQueries: Int { lock.withLock { statusCount } }
}

/// Answers every status query with 0x03 (ready, top of form). From this connection's query number
/// `blockFrom` on, the query hangs until the calling task is cancelled.
actor AppStubTransport: PrinterTransport {
    let log: DeviceLog
    let blockFrom: Int?
    private var queries = 0
    init(log: DeviceLog, blockFrom: Int? = nil) { self.log = log; self.blockFrom = blockFrom }
    func write(_ bytes: [UInt8]) {}
    func read(maxLength: Int, timeout: Duration) -> [UInt8] { [] }
    func transact(_ request: [UInt8], maxLength: Int, timeout: Duration) async throws -> [UInt8] {
        _ = log.queried()
        queries += 1
        if let blockFrom, queries >= blockFrom { try await Task.sleep(for: .seconds(60)) }
        return [0x03]
    }
    func close() {}
}

struct AppStubFactory: TransportFactory {
    var list: [DiscoveredPrinter]
    var log = DeviceLog()
    var blockFrom: Int?
    var openError: TransportError?
    func printers() -> [DiscoveredPrinter] { list }
    func open(_ printer: DiscoveredPrinter) throws -> any PrinterTransport {
        log.opened()
        if let openError { throw openError }
        return AppStubTransport(log: log, blockFrom: blockFrom)
    }
}

/// Never remembers a form feed: no `JobSpacing` pause in tests.
struct AppNoStampClock: FormFeedClock {
    func lastFormFeed(serial: String?) -> Date? { nil }
    func recordFormFeed(serial: String?, at date: Date) {}
}

func appPrefs(remembered: String? = nil, serial: String? = "S1") -> RollPreferences {
    let prefs = RollPreferences(defaults: tempDefaults())
    if let remembered { prefs.setLastRollID(remembered, forPrinterSerial: serial) }
    return prefs
}

@MainActor
private func model(
    printers: [DiscoveredPrinter], remembered: String?, blockFrom: Int? = nil, log: DeviceLog = DeviceLog()
) -> AppModel {
    let factory = AppStubFactory(list: printers, log: log, blockFrom: blockFrom)
    let printer = LabelPrinter(factory: factory, preferences: appPrefs(remembered: remembered), formFeedClock: AppNoStampClock())
    return AppModel(printer: printer, preview: PreviewEngine(debounce: .zero, maxPages: 1))
}

// MARK: - Tests

@Suite struct AppModelTests {
    @Test @MainActor func firstPrinterWithoutRollNeedsChoice() async {
        let m = model(printers: [appLW450Printer], remembered: nil)
        await m.refreshPrinters()
        #expect(m.selectedPrinter == appLW450Printer)
        #expect(m.needsRollChoice)
    }

    @Test @MainActor func rollChoiceAskedOncePerPrinter() async {
        let m = model(printers: [appLW450Printer], remembered: nil)
        await m.refreshPrinters()
        #expect(m.needsRollChoice)
        m.needsRollChoice = false // sheet dismissed without a choice
        await m.refreshPrinters()
        #expect(!m.needsRollChoice)
    }

    @Test @MainActor func rememberedRollSelected() async {
        let m = model(printers: [appLW450Printer], remembered: "11354")
        await m.refreshPrinters()
        #expect(m.roll?.id == "11354" && !m.needsRollChoice)
    }

    @Test @MainActor func chooseRollClearsNeed() async {
        let m = model(printers: [appLW450Printer], remembered: nil)
        await m.refreshPrinters()
        m.chooseRoll(appRoll11354)
        #expect(m.roll == appRoll11354 && !m.needsRollChoice)
    }

    @Test @MainActor func printWithoutPrinterFails() async {
        let m = model(printers: [], remembered: nil)
        m.roll = appRoll11354
        m.document.text = "x"
        await m.print(allowOverflow: false)
        guard case .failed = m.printPhase else { Issue.record("phase \(m.printPhase)"); return }
    }

    @Test @MainActor func printOnUnsupportedPrinterFails() async {
        let log = DeviceLog()
        let m = model(printers: [appLW550Printer], remembered: nil, log: log)
        await m.refreshPrinters()
        m.roll = appRoll11354
        m.document.text = "x"
        await m.print(allowOverflow: false)
        guard case .failed = m.printPhase else { Issue.record("phase \(m.printPhase)"); return }
        #expect(log.opens == 0)
    }

    @Test @MainActor func printWithoutRollFails() async {
        let log = DeviceLog()
        let m = model(printers: [appLW450Printer], remembered: nil, log: log)
        await m.refreshPrinters()
        m.document.text = "x"
        await m.print(allowOverflow: false)
        guard case .failed = m.printPhase else { Issue.record("phase \(m.printPhase)"); return }
        #expect(log.opens == 0)
    }

    @Test @MainActor func printProgressAndFinish() async {
        let m = model(printers: [appLW450Printer], remembered: "11354")
        await m.refreshPrinters()
        m.document.text = "x"
        m.document.copies = 2
        await m.print(allowOverflow: false)
        #expect(m.printPhase == .finished(2))
    }

    @Test @MainActor func cancelSetsCancelled() async {
        // Status queries: 1 = ready check, 2 = after label 1, 3 = after label 2 → hangs.
        let m = model(printers: [appLW450Printer], remembered: "11354", blockFrom: 3)
        await m.refreshPrinters()
        m.monitor.visibilityChanged(visible: true)
        m.document.text = "x"
        m.document.copies = 3
        let job = Task { await m.print(allowOverflow: false) }
        await waitFor { m.printPhase == .printing(done: 1, total: 3) }
        #expect(m.printPhase == .printing(done: 1, total: 3))
        #expect(!m.monitor.isPolling)
        m.cancelPrint()
        await job.value
        #expect(m.printPhase == .cancelled(printed: 1, total: 3))
        #expect(m.monitor.isPolling)
        m.monitor.visibilityChanged(visible: false)
    }

    @Test @MainActor func loadTextSwitchesToTextLayout() {
        let m = model(printers: [], remembered: nil)
        m.document.layout = .barcode
        m.load(text: "Keller")
        #expect(m.document.layout == .text && m.document.text == "Keller")
    }

    @Test @MainActor func documentChangeUpdatesPreview() async {
        let m = model(printers: [appLW450Printer], remembered: "11354")
        await m.refreshPrinters()
        m.document.text = "Hallo"
        await waitFor { m.previewResult?.pages.count == 1 }
        #expect(m.previewResult?.pages.count == 1 && m.previewResult?.error == nil)
    }
}

@Test func germanCancelText() {
    #expect(L10n.cancelledText(printed: 1, total: 3, preferred: ["de"]).hasPrefix("Abgebrochen nach 1 von 3"))
    #expect(L10n.cancelledText(printed: 1, total: 3, preferred: ["de"])
        == "Abgebrochen nach 1 von 3 Etiketten. Ggf. Vorschubtaste drücken, um ein angefangenes Etikett auszugeben.")
    #expect(L10n.cancelledText(printed: 1, total: 3, preferred: ["en"]).hasPrefix("Cancelled after 1 of 3"))
}

@Test func printPhaseMessagesInGerman() {
    let de = localizedBundle(preferred: ["de"])
    #expect(PrintPhase.idle.message(bundle: de) == nil)
    #expect(PrintPhase.positioning(remaining: .seconds(3)).message(bundle: de) == "Drucker positioniert das Etikett …")
    #expect(PrintPhase.printing(done: 1, total: 3).message(bundle: de) == "Drucke Etikett 2 von 3 …")
    #expect(PrintPhase.finished(1).message(bundle: de) == "1 Etikett gedruckt.")
    #expect(PrintPhase.finished(2).message(bundle: de) == "2 Etiketten gedruckt.")
    #expect(PrintPhase.cancelled(printed: 1, total: 3).message(bundle: de)?.hasPrefix("Abgebrochen nach 1 von 3") == true)
    #expect(PrintPhase.failed("x").message(bundle: de) == "x")
}

@Test @MainActor func positioningEventShownAsPhase() async {
    // 3 s of pause left at the injected `now`; the gate sleeper keeps the pause open until released.
    let now = Date(timeIntervalSinceReferenceDate: 1000)
    let clock = FixedClock(lastFeed: now.addingTimeInterval(-7))
    let sleeper = ManualSleeper()
    let printer = LabelPrinter(
        factory: AppStubFactory(list: [appLW450Printer]), preferences: appPrefs(remembered: "11354"), formFeedClock: clock,
        sleep: { try await sleeper.sleep($0) }, now: { now }
    )
    let m = AppModel(printer: printer, preview: PreviewEngine(debounce: .zero, maxPages: 1), defaults: tempDefaults())
    await m.refreshPrinters()
    m.document.text = "x"
    let job = Task { await m.print(allowOverflow: false) }
    await waitFor { if case .positioning = m.printPhase { true } else { false } }
    await waitForAsync { await sleeper.sleepCount == 1 }
    #expect(m.printPhase == .positioning(remaining: .seconds(3)))
    #expect(await sleeper.requests == [.seconds(3)])
    await sleeper.advance()
    await job.value
    #expect(m.printPhase == .finished(1))
}

/// Reports one previous form feed at a fixed time.
private struct FixedClock: FormFeedClock {
    let lastFeed: Date
    func lastFormFeed(serial: String?) -> Date? { lastFeed }
    func recordFormFeed(serial: String?, at date: Date) {}
}

// MARK: - Carry-overs from Task 5

@Suite struct ViewCarryOverTests {
    @Test @MainActor func previewPageSurvivesTheFirstPagePass() async {
        let m = makeViewModel(printers: [appLW450Printer], remembered: "11354", maxPages: 3)
        await m.refreshPrinters()
        m.document.text = "a"
        m.document.copies = 3
        await waitFor { m.previewResult?.pages.count == 3 }
        m.previewPage = 2
        let old = m.previewResult?.pages.first?.preview
        m.document.text = "b"
        // The final result has 3 pages; the page-1 pass before it has only one.
        await waitFor { m.previewResult?.pages.count == 3 && m.previewResult?.pages.first?.preview !== old }
        #expect(m.previewPage == 2)
    }

    @Test @MainActor func previewPageClampedByTheFinalResult() async {
        let m = makeViewModel(printers: [appLW450Printer], remembered: "11354", maxPages: 3)
        await m.refreshPrinters()
        m.document.text = "a"
        m.document.copies = 3
        await waitFor { m.previewResult?.pages.count == 3 }
        m.previewPage = 2
        m.document.copies = 1
        await waitFor { m.previewResult?.totalLabels == 1 && m.previewPage == 0 }
        #expect(m.previewResult?.pages.count == 1 && m.previewPage == 0)
    }

    @Test @MainActor func pauseShowsPrinting() {
        let printer = LabelPrinter(factory: AppStubFactory(list: [appLW450Printer]), preferences: appPrefs(), formFeedClock: AppNoStampClock())
        let monitor = PrinterMonitor(printer: printer)
        monitor.target = appLW450Printer
        monitor.pause()
        #expect(monitor.state == .printing(name: "LabelWriter 450"))
        monitor.resume()
    }
}

@Suite struct PrintAvailabilityTests {
    @Test @MainActor func blockReasonFollowsPrinterAndRoll() async {
        let none = makeViewModel(printers: [], remembered: nil)
        await none.refreshPrinters()
        #expect(none.printBlockReason != nil)

        let noRoll = makeViewModel(printers: [appLW450Printer], remembered: nil)
        await noRoll.refreshPrinters()
        #expect(noRoll.printBlockReason == String(localized: "No roll selected.", bundle: L10n.bundle))

        let ready = makeViewModel(printers: [appLW450Printer], remembered: "11354")
        await ready.refreshPrinters()
        #expect(ready.printBlockReason == nil && !ready.isPrinting)
    }
}
