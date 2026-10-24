import Foundation
import Testing
import LabelMedia
import LabelProtocol
import LabelTransport
import MacLabelKit
@testable import MacLabelApp

/// Answers `ESC A` with scripted status bytes and records writes and close.
private actor ScriptedTransport: PrinterTransport {
    private var statuses: [UInt8]
    private(set) var written: [UInt8] = []
    private(set) var closed = false

    init(statuses: [UInt8]) { self.statuses = statuses }

    func write(_ bytes: [UInt8]) { written += bytes }
    func read(maxLength: Int, timeout: Duration) -> [UInt8] { [] }
    func transact(_ request: [UInt8], maxLength: Int, timeout: Duration) throws -> [UInt8] {
        guard request == LWClassicEncoder.statusRequest, !statuses.isEmpty else { throw TransportError.timeout }
        return [statuses.removeFirst()]
    }
    func close() { closed = true }
}

private struct StubFactory: TransportFactory {
    var list: [DiscoveredPrinter]
    var transport: ScriptedTransport?
    var openError: TransportError?

    init(printers: [DiscoveredPrinter], transport: ScriptedTransport? = nil, openError: TransportError? = nil) {
        self.list = printers
        self.transport = transport
        self.openError = openError
    }

    func printers() -> [DiscoveredPrinter] { list }
    func open(_ printer: DiscoveredPrinter) throws -> any PrinterTransport {
        if let openError { throw openError }
        guard let transport else { throw TransportError.notFound }
        return transport
    }
}

/// In-memory clock without stamps, so `JobSpacing` never pauses in tests.
private final class MemoryClock: FormFeedClock, @unchecked Sendable {
    private let lock = NSLock()
    private var stamps: [String: Date] = [:]
    func lastFormFeed(serial: String?) -> Date? { lock.withLock { stamps[serial ?? ""] } }
    func recordFormFeed(serial: String?, at date: Date) { lock.withLock { stamps[serial ?? ""] = date } }
}


/// Thread-safe ordered event log shared by `RecordingFactory` and its transports.
private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ e: String) { lock.withLock { items.append(e) } }
    var events: [String] { lock.withLock { items } }
}

/// Always ready; every status query takes `delay`, so concurrent callers would interleave.
private actor SlowReadyTransport: PrinterTransport {
    let log: EventLog
    let delay: Duration
    init(log: EventLog, delay: Duration) { self.log = log; self.delay = delay }
    func write(_ bytes: [UInt8]) {}
    func read(maxLength: Int, timeout: Duration) -> [UInt8] { [] }
    func transact(_ request: [UInt8], maxLength: Int, timeout: Duration) async throws -> [UInt8] {
        try await Task.sleep(for: delay)
        return [0x03]
    }
    func close() { log.add("close") }
}

/// Opens a fresh `SlowReadyTransport` per call and logs every open.
private struct RecordingFactory: TransportFactory {
    let log: EventLog
    var delay: Duration = .milliseconds(20)
    func printers() -> [DiscoveredPrinter] { [lw450Printer] }
    func open(_ printer: DiscoveredPrinter) throws -> any PrinterTransport {
        log.add("open")
        return SlowReadyTransport(log: log, delay: delay)
    }
}

/// Never remembers a form feed: no pause between jobs.
private struct NoStampClock: FormFeedClock {
    func lastFormFeed(serial: String?) -> Date? { nil }
    func recordFormFeed(serial: String?, at date: Date) {}
}

/// Collects phase events.
private final class PhaseLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [PrintPhaseEvent] = []
    func add(_ e: PrintPhaseEvent) { lock.withLock { items.append(e) } }
    var events: [PrintPhaseEvent] { lock.withLock { items } }
}

private let lw450 = PrinterModel.lookup(productID: 0x20)!
private let lw450Printer = DiscoveredPrinter(id: 1, model: lw450, serialNumber: "S1", locationID: nil)
private let r11354 = MediaCatalog.bundled.roll(sku: "11354")!

private func tmpPrefs() -> RollPreferences { RollPreferences(defaults: UserDefaults(suiteName: UUID().uuidString)!) }
private func request() -> PrintRequest { PrintRequest(contents: [.text(.init(text: "Hallo"))], roll: r11354, model: lw450) }

@Test func noPrinterState() async {
    let p = LabelPrinter(factory: StubFactory(printers: []), preferences: tmpPrefs(), formFeedClock: MemoryClock())
    #expect(await p.state(for: nil) == .noPrinter)
}

@Test func busyState() async {
    let p = LabelPrinter(factory: StubFactory(printers: [lw450Printer], openError: .busy), preferences: tmpPrefs(), formFeedClock: MemoryClock())
    #expect(await p.state(for: lw450Printer) == .busy(name: "LabelWriter 450"))
}

@Test func disconnectedState() async {
    let p = LabelPrinter(factory: StubFactory(printers: [lw450Printer], openError: .disconnected), preferences: tmpPrefs(), formFeedClock: MemoryClock())
    #expect(await p.state(for: lw450Printer) == .disconnected)
}

@Test func unsupportedState() async {
    let v2 = DiscoveredPrinter(id: 2, model: PrinterModel.lookup(productID: 0x28)!, serialNumber: nil, locationID: nil)
    let p = LabelPrinter(factory: StubFactory(printers: [v2]), preferences: tmpPrefs(), formFeedClock: MemoryClock())
    #expect(await p.state(for: v2) == .unsupported("LabelWriter 550"))
}

@Test func readyState() async {
    let t = ScriptedTransport(statuses: [0x03])
    let p = LabelPrinter(factory: StubFactory(printers: [lw450Printer], transport: t), preferences: tmpPrefs(), formFeedClock: MemoryClock())
    #expect(await p.state(for: lw450Printer) == .ready(name: "LabelWriter 450"))
    #expect(await t.closed)
}

@Test func paperOutState() async {
    let t = ScriptedTransport(statuses: [0xA0])
    let p = LabelPrinter(factory: StubFactory(printers: [lw450Printer], transport: t), preferences: tmpPrefs(), formFeedClock: MemoryClock())
    #expect(await p.state(for: lw450Printer) == .notReady(name: "LabelWriter 450", reason: localizedString("out of paper")))
    #expect(await t.closed)
}

@Test func availablePrintersComeFromFactory() async {
    let p = LabelPrinter(factory: StubFactory(printers: [lw450Printer]), preferences: tmpPrefs(), formFeedClock: MemoryClock())
    #expect(await p.availablePrinters() == [lw450Printer])
}

@Test func printRemembersRollAndClosesTransport() async throws {
    let t = ScriptedTransport(statuses: [0x03, 0x03])
    let p = LabelPrinter(factory: StubFactory(printers: [lw450Printer], transport: t), preferences: tmpPrefs(), formFeedClock: MemoryClock())
    #expect(await p.rememberedRoll(for: lw450Printer) == nil)
    try await p.print(request(), on: lw450Printer) { _ in }
    #expect(await p.rememberedRoll(for: lw450Printer)?.id == "11354")
    #expect(await t.closed)
    #expect(await t.written.suffix(2) == [0x1B, 0x45])
}

@Test func printRecordsFormFeedForSpacing() async throws {
    let clock = MemoryClock()
    let t = ScriptedTransport(statuses: [0x03, 0x03])
    let p = LabelPrinter(factory: StubFactory(printers: [lw450Printer], transport: t), preferences: tmpPrefs(), formFeedClock: clock)
    try await p.print(request(), on: lw450Printer) { _ in }
    #expect(clock.lastFormFeed(serial: "S1") != nil)
}

@Test func printClosesTransportOnError() async {
    let t = ScriptedTransport(statuses: [0xA0])
    let p = LabelPrinter(factory: StubFactory(printers: [lw450Printer], transport: t), preferences: tmpPrefs(), formFeedClock: MemoryClock())
    await #expect(throws: PrintError.printerNotReady(LWStatus(raw: 0xA0))) {
        try await p.print(request(), on: lw450Printer) { _ in }
    }
    #expect(await t.closed)
    #expect(await p.rememberedRoll(for: lw450Printer) == nil)
}

@Test func printOpenErrorBecomesPrintError() async {
    let p = LabelPrinter(factory: StubFactory(printers: [lw450Printer], openError: .busy), preferences: tmpPrefs(), formFeedClock: MemoryClock())
    await #expect(throws: PrintError.transport(.busy)) {
        try await p.print(request(), on: lw450Printer) { _ in }
    }
}

@Test func rememberIsPerPrinter() async {
    let other = DiscoveredPrinter(id: 3, model: lw450, serialNumber: "S2", locationID: nil)
    let p = LabelPrinter(factory: StubFactory(printers: []), preferences: tmpPrefs(), formFeedClock: MemoryClock())
    await p.remember(r11354, for: lw450Printer)
    #expect(await p.rememberedRoll(for: lw450Printer) == r11354)
    #expect(await p.rememberedRoll(for: other) == nil)
}


@Test func concurrentPrintsRunOneAfterAnother() async throws {
    let log = EventLog()
    let p = LabelPrinter(factory: RecordingFactory(log: log), preferences: tmpPrefs(), formFeedClock: NoStampClock())
    async let first: Void = p.print(request(), on: lw450Printer) { _ in }
    async let second: Void = p.print(request(), on: lw450Printer) { _ in }
    _ = try await (first, second)
    #expect(log.events == ["open", "close", "open", "close"])
}

@Test func stateDuringPrintIsPrintingWithoutOpening() async throws {
    let log = EventLog()
    let clock = MemoryClock()
    // Previous form feed 9.7 s ago: ~300 ms positioning pause before the device is opened.
    clock.recordFormFeed(serial: "S1", at: Date().addingTimeInterval(-9.7))
    let phases = PhaseLog()
    let p = LabelPrinter(factory: RecordingFactory(log: log), preferences: tmpPrefs(), formFeedClock: clock)
    let job = Task { try await p.print(request(), on: lw450Printer) { phases.add($0) } }
    while phases.events.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
    #expect(await p.state(for: lw450Printer) == .printing(name: "LabelWriter 450"))
    #expect(log.events.isEmpty)
    try await job.value
    #expect(log.events == ["open", "close"])
}

@Test func positioningEventBeforeLabels() async throws {
    let clock = MemoryClock()
    clock.recordFormFeed(serial: "S1", at: Date().addingTimeInterval(-9.8))
    let phases = PhaseLog()
    let p = LabelPrinter(factory: RecordingFactory(log: EventLog()), preferences: tmpPrefs(), formFeedClock: clock)
    try await p.print(request(), on: lw450Printer) { phases.add($0) }
    let events = phases.events
    #expect(events.count == 2)
    guard case .positioning(let remaining) = events.first else { Issue.record("no positioning event"); return }
    #expect(remaining > .zero && remaining <= .milliseconds(200))
    #expect(events.last == .label(done: 1, total: 1))
}

@Test func noPositioningEventWithoutRecentFormFeed() async throws {
    let phases = PhaseLog()
    let p = LabelPrinter(factory: RecordingFactory(log: EventLog()), preferences: tmpPrefs(), formFeedClock: NoStampClock())
    try await p.print(request(), on: lw450Printer) { phases.add($0) }
    #expect(phases.events == [.label(done: 1, total: 1)])
}

@Test func modelMismatchIsRejectedBeforeOpening() async {
    let log = EventLog()
    let p = LabelPrinter(factory: RecordingFactory(log: log), preferences: tmpPrefs(), formFeedClock: NoStampClock())
    var turbo = request()
    turbo.model = PrinterModel.lookup(productID: 0x21)!
    await #expect(throws: PrintError.unsupportedPrinter("LabelWriter 450")) {
        try await p.print(turbo, on: lw450Printer) { _ in }
    }
    let v2 = DiscoveredPrinter(id: 2, model: PrinterModel.lookup(productID: 0x28)!, serialNumber: nil, locationID: nil)
    var v2Request = request()
    v2Request.model = v2.model
    await #expect(throws: PrintError.unsupportedPrinter("LabelWriter 550")) {
        try await p.print(v2Request, on: v2) { _ in }
    }
    #expect(log.events.isEmpty)
}

@Test func sharedInstanceExists() {
    _ = LabelPrinter.shared
}

#if DEBUG
@Test func fakeFactoryFromEnvironment() {
    #expect(LabelPrinter.makeDefault(environment: ["MACLABEL_FAKE_PRINTER": "/tmp/x.bin"]) is FakeTransportFactory)
}

@Test func fakeFactoryReportsReadyFakePrinter() async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "maclabel-fake-\(UUID().uuidString).bin")
    defer { try? FileManager.default.removeItem(at: url) }
    let factory = FakeTransportFactory(fileURL: url)
    let printer = try #require(factory.printers().first)
    #expect(printer.id == 1 && printer.model.productID == 0x20 && printer.serialNumber == "FAKE")
    let p = LabelPrinter(factory: factory, preferences: tmpPrefs(), formFeedClock: MemoryClock())
    #expect(await p.state(for: printer) == .ready(name: "LabelWriter 450"))
}
#endif

@Test func defaultIsUSB() {
    #expect(LabelPrinter.makeDefault(environment: [:]) is USBTransportFactory)
}
