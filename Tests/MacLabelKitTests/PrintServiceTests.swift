import Foundation
import Testing
import LabelMedia
import LabelProtocol
import LabelRender
import LabelTransport
@testable import MacLabelKit

actor ScriptedTransport: PrinterTransport {
    private var statuses: [UInt8]
    private(set) var written: [UInt8] = []
    private(set) var writtenRasterBytes = 0
    private var writeCount = 0

    init(statuses: [UInt8]) { self.statuses = statuses }

    func write(_ bytes: [UInt8]) {
        writeCount += 1
        written += bytes
        if writeCount > 1 { writtenRasterBytes += bytes.count }
    }
    func read(maxLength: Int, timeout: Duration) -> [UInt8] { [] }
    func transact(_ request: [UInt8], maxLength: Int, timeout: Duration) throws -> [UInt8] {
        guard request == LWClassicEncoder.statusRequest, !statuses.isEmpty else { throw TransportError.timeout }
        return [statuses.removeFirst()]
    }
    func close() {}
}

private let lw450 = PrinterModel.lookup(productID: 0x20)!
private let r11354 = MediaCatalog.bundled.roll(sku: "11354")!
private func text(_ s: String) -> LabelContent { .text(.init(text: s)) }
private func req(_ n: Int) -> PrintRequest {
    .init(contents: (0..<n).map { text("L\($0)") }, roll: r11354, model: lw450)
}
private func contains(_ hay: [UInt8], _ needle: [UInt8]) -> Bool {
    guard hay.count >= needle.count else { return false }
    return (0...(hay.count - needle.count)).contains { Array(hay[$0..<$0 + needle.count]) == needle }
}

@Test func rejects4XLRollOn450() {
    let big = MediaCatalog.bundled.roll(sku: "S0904980") ?? MediaCatalog.bundled.rolls.first { $0.minHeadDots == 1248 }!
    #expect(throws: PrintError.rollTooWide(rollID: big.id, needs: 1248, has: 672)) {
        try PrintService.prepare(.init(contents: [text("x")], roll: big, model: lw450))
    }
}
@Test func emptyAndUnsupported() {
    #expect(throws: PrintError.nothingToPrint) { try PrintService.prepare(.init(contents: [], roll: r11354, model: lw450)) }
    let v2 = PrinterModel.lookup(productID: 0x28)!
    #expect(throws: PrintError.unsupportedPrinter(v2.name)) { try PrintService.prepare(.init(contents: [text("x")], roll: r11354, model: v2)) }
}
@Test func overflowBlocksUnlessAllowed() throws {
    var r = PrintRequest(contents: [.barcode(.init(symbology: .code128, value: String(repeating: "A", count: 80)))], roll: r11354, model: lw450)
    #expect(throws: PrintError.overflow(labelIndex: 0)) { try PrintService.prepare(r) }
    r.allowOverflow = true
    _ = try PrintService.prepare(r)
}
@Test func invalidContinuousLength() throws {
    let cont = try #require(MediaCatalog.bundled.rolls.first { $0.kind == .continuous && $0.minHeadDots <= 672 })
    for mm in [5.0, 1500.0] {
        #expect(throws: PrintError.invalidLength) {
            try PrintService.prepare(.init(contents: [text("x")], roll: cont, model: lw450, continuousLengthMM: mm))
        }
    }
    _ = try PrintService.prepare(.init(contents: [text("x")], roll: cont, model: lw450, continuousLengthMM: 50))
}
@Test func autoQualityGraphicsForQR() throws {
    let job = try PrintService.prepare(.init(contents: [.qr(.init(payload: "x"))], roll: r11354, model: lw450))
    #expect(contains(job.bytes, [0x1B, 0x69]))
    let t = try PrintService.prepare(req(1))
    #expect(contains(t.bytes, [0x1B, 0x68]))
}
@Test func durableGetsDark() throws {
    let durable = try #require(MediaCatalog.bundled.rolls.first { $0.material == "durable" && $0.minHeadDots <= 672 })
    let job = try PrintService.prepare(.init(contents: [text("x")], roll: durable, model: lw450))
    #expect(contains(job.bytes, [0x1B, 0x67]))
    #expect(!contains(try PrintService.prepare(req(1)).bytes, [0x1B, 0x67]))
}
@Test func notReadyBeforeStart() async {
    let t = ScriptedTransport(statuses: [0xA0])
    await #expect(throws: PrintError.printerNotReady(LWStatus(raw: 0xA0))) { try await PrintService.print(req(1), using: t) }
    #expect(await t.writtenRasterBytes == 0)
    #expect(await t.written.isEmpty)
}
@Test func interruptedAfterSecondLabel() async {
    let t = ScriptedTransport(statuses: [0x03, 0x03, 0xA0])
    await #expect(throws: PrintError.interrupted(printed: 2, total: 3, status: LWStatus(raw: 0xA0))) {
        try await PrintService.print(req(3), using: t)
    }
    let w = await t.written
    #expect(Array(w.suffix(158)) == LWClassicEncoder.resync + LWClassicEncoder.reset)
}
@Test func happyPathEndsWithEndOfJobAndReportsProgress() async throws {
    let t = ScriptedTransport(statuses: [0x03, 0x03, 0x03])
    let log = Counter()
    try await PrintService.print(req(2), using: t) { p, n in log.add((p, n)) }
    #expect(await t.written.suffix(2) == [0x1B, 0x45])
    #expect(log.values.map(\.0) == [1, 2] && log.values.allSatisfy { $0.1 == 2 })
}
@Test func statusQueueExhaustedBecomesTransportError() async {
    let t = ScriptedTransport(statuses: [0x03])
    await #expect(throws: PrintError.transport(.timeout)) { try await PrintService.print(req(2), using: t) }
}
@Test func errorTextsGermanAndEnglish() {
    let de = PrintError.transport(.busy).text(bundle: localizedBundle(preferred: ["de-DE"]))
    #expect(de == "Drucker wird gerade von einer anderen App benutzt.")
    let en = PrintError.transport(.busy).text(bundle: localizedBundle(preferred: ["en"]))
    #expect(en == "The printer is currently in use by another app.")
    let deWide = PrintError.rollTooWide(rollID: "x", needs: 1248, has: 672).text(bundle: localizedBundle(preferred: ["de"]))
    #expect(deWide.hasPrefix("Diese Rolle ist zu breit für den Druckkopf (") && deWide.hasSuffix(" statt 672 Punkte)."))
    #expect(PrintError.printerNotReady(LWStatus(raw: 0x23)).text(bundle: localizedBundle(preferred: ["de"])).contains("kein Papier"))
}

actor CancelAwareTransport: PrinterTransport {
    private(set) var written: [[UInt8]] = []
    private var statusCount = 0
    var isWaiting: Bool { statusCount >= 2 }
    func write(_ bytes: [UInt8]) throws {
        if Task.isCancelled { throw CancellationError() }
        written.append(bytes)
    }
    func read(maxLength: Int, timeout: Duration) -> [UInt8] { [] }
    func transact(_ request: [UInt8], maxLength: Int, timeout: Duration) async throws -> [UInt8] {
        statusCount += 1
        if statusCount == 2 { try? await Task.sleep(for: .seconds(30)) } // after label 1: wait for cancel
        return [0x03]
    }
    func close() {}
}

@Test func cancellationStillSendsResync() async throws {
    let t = CancelAwareTransport()
    let task = Task { try await PrintService.print(req(3), using: t) }
    // Wait until the print is blocked after label 1 (robust under parallel test load), then cancel.
    for _ in 0..<500 where !(await t.isWaiting) { try await Task.sleep(for: .milliseconds(10)) }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    let w = await t.written
    #expect(w.last == LWClassicEncoder.resync + LWClassicEncoder.reset)
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(Int, Int)] = []
    func add(_ v: (Int, Int)) { lock.lock(); items.append(v); lock.unlock() }
    var values: [(Int, Int)] { lock.lock(); defer { lock.unlock() }; return items }
}

@Test func batchAndCSVErrorTextsGermanAndEnglish() {
    let de = localizedBundle(preferred: ["de"]), en = localizedBundle(preferred: ["en"])
    #expect(BatchError.unknownPlaceholder("ort").text(bundle: de) == "Unbekannter Platzhalter {ort}.")
    #expect(BatchError.unknownPlaceholder("ort").text(bundle: en) == "Unknown placeholder {ort}.")
    #expect(CSVError.unterminatedQuote(line: 3).text(bundle: de) == "CSV: Anführungszeichen in Zeile 3 nicht geschlossen.")
    #expect(CSVError.unterminatedQuote(line: 3).text(bundle: en) == "CSV: unterminated quote on line 3.")
}

@Test func continuousRollSendsFFFFLength() throws {
    let cont = try #require(MediaCatalog.bundled.roll(sku: "30270"))
    #expect(cont.kind == .continuous)
    let job = try PrintService.prepare(.init(contents: [text("x")], roll: cont, model: lw450, continuousLengthMM: 50))
    #expect(contains(job.bytes, [0x1B, 0x4C, 0xFF, 0xFF]))
    #expect(job.renders[0].bitmap.height > 0)
    #expect(!contains(try PrintService.prepare(req(1)).bytes, [0x1B, 0x4C, 0xFF, 0xFF]))
}

// Hardware finding (LW450, 24.10.2026): after a job's final ESC E the printer reports 0x01
// (ready, not top-of-form) for ~1.3 s while the label is still moving. Starting the next job
// in that window shifts it down the label. DYMO's language monitor (CheckStatusAndReprint)
// polls ESC A until the TOF bit is set before the first label; MacLabel must do the same.
@Test func waitsForTopOfFormBeforeFirstLabel() async throws {
    let t = ScriptedTransport(statuses: [0x01, 0x01, 0x03, 0x03])
    try await PrintService.print(req(1), using: t, topOfFormTimeout: .seconds(1), pollInterval: .zero)
    #expect(await t.written.prefix(156) == ArraySlice(LWClassicEncoder.resync))
    #expect(await t.written.suffix(2) == [0x1B, 0x45])
}
@Test func topOfFormTimeoutIsNotReady() async {
    let t = ScriptedTransport(statuses: Array(repeating: 0x01, count: 500))
    await #expect(throws: PrintError.printerNotReady(LWStatus(raw: 0x01))) {
        try await PrintService.print(req(1), using: t, topOfFormTimeout: .milliseconds(30), pollInterval: .milliseconds(5))
    }
    #expect(await t.written.isEmpty)
}
@Test func continuousRollDoesNotWaitForTopOfForm() async throws {
    let cont = MediaCatalog.bundled.roll(sku: "30270")!
    let t = ScriptedTransport(statuses: [0x01, 0x01])
    try await PrintService.print(.init(contents: [text("x")], roll: cont, model: lw450, continuousLengthMM: 50),
                                 using: t, topOfFormTimeout: .milliseconds(30), pollInterval: .zero)
    #expect(await t.written.suffix(2) == [0x1B, 0x45])
}

// After the TOF bit appears the LW450 still advances the label to the tear bar; DYMO's CUPS
// pipeline adds ≥1 s between jobs. If MacLabel had to wait for TOF, it settles before printing.
@Test func settlesAfterWaitingForTopOfForm() async throws {
    let t = ScriptedTransport(statuses: [0x01, 0x03, 0x03])
    let start = ContinuousClock.now
    try await PrintService.print(req(1), using: t, topOfFormTimeout: .seconds(1), pollInterval: .zero,
                                 settleAfterTopOfForm: .milliseconds(200))
    #expect(ContinuousClock.now - start >= .milliseconds(200))
}
@Test func noSettleWhenAlreadyAtTopOfForm() async throws {
    let t = ScriptedTransport(statuses: [0x03, 0x03])
    let start = ContinuousClock.now
    try await PrintService.print(req(1), using: t, topOfFormTimeout: .seconds(1), pollInterval: .zero,
                                 settleAfterTopOfForm: .seconds(2))
    #expect(ContinuousClock.now - start < .seconds(1))
}

// Hardware finding (24.10.2026): a job that starts within seconds of the previous job's
// form feed (ESC E) lands too low, regardless of status waits, print mode or compression;
// after a longer pause it is correct. MacLabel therefore keeps a minimum pause after the
// last form feed of the same printer (Weg A, docs/research/lw450-protocol.md §13.2).
final class MemoryFormFeedClock: FormFeedClock, @unchecked Sendable {
    var stamps: [String: Date] = [:]
    func lastFormFeed(serial: String?) -> Date? { stamps[serial ?? "default"] }
    func recordFormFeed(serial: String?, at date: Date) { stamps[serial ?? "default"] = date }
}
@Test func waitsForMinimumPauseAfterPreviousFormFeed() async throws {
    let clock = MemoryFormFeedClock(); clock.recordFormFeed(serial: "A", at: Date())
    let t = ScriptedTransport(statuses: [0x03, 0x03])
    let start = ContinuousClock.now
    try await PrintService.print(req(1), using: t, spacing: .init(clock: clock, serial: "A", minimumPause: .milliseconds(300)))
    #expect(ContinuousClock.now - start >= .milliseconds(280))
}
@Test func noPauseWhenPreviousFormFeedIsOld() async throws {
    let clock = MemoryFormFeedClock(); clock.recordFormFeed(serial: "A", at: Date().addingTimeInterval(-60))
    let t = ScriptedTransport(statuses: [0x03, 0x03])
    let start = ContinuousClock.now
    try await PrintService.print(req(1), using: t, spacing: .init(clock: clock, serial: "A", minimumPause: .seconds(5)))
    #expect(ContinuousClock.now - start < .seconds(1))
}
@Test func recordsFormFeedAfterJob() async throws {
    let clock = MemoryFormFeedClock()
    let t = ScriptedTransport(statuses: [0x03, 0x03])
    try await PrintService.print(req(1), using: t, spacing: .init(clock: clock, serial: "B", minimumPause: .seconds(5)))
    let stamp = try #require(clock.lastFormFeed(serial: "B"))
    #expect(abs(stamp.timeIntervalSinceNow) < 2)
}
@Test func pauseIsPerPrinter() async throws {
    let clock = MemoryFormFeedClock(); clock.recordFormFeed(serial: "A", at: Date())
    let t = ScriptedTransport(statuses: [0x03, 0x03])
    let start = ContinuousClock.now
    try await PrintService.print(req(1), using: t, spacing: .init(clock: clock, serial: "B", minimumPause: .seconds(5)))
    #expect(ContinuousClock.now - start < .seconds(1))
}
@Test func userDefaultsClockRoundTrip() {
    let c = UserDefaultsFormFeedClock(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    #expect(c.lastFormFeed(serial: "X") == nil)
    let now = Date(); c.recordFormFeed(serial: "X", at: now)
    #expect(abs(c.lastFormFeed(serial: "X")!.timeIntervalSince(now)) < 0.01)
}

@Test func renderMatchesPrepareRenders() throws {
    let a = try PrintService.render(req(3))
    let b = try PrintService.prepare(req(3)).renders
    #expect(a.count == 3 && a.map(\.bitmap) == b.map(\.bitmap))
}

@Test func renderStopsWhenTaskCancelled() async {
    let task = Task.detached { () -> Bool in
        while !Task.isCancelled { await Task.yield() }
        do { _ = try PrintService.render(req(5)); return false } catch is CancellationError { return true } catch { return false }
    }
    task.cancel()
    #expect(await task.value)
}
