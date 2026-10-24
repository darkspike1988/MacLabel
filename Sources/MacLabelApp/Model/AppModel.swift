import Foundation
import LabelMedia
import LabelProtocol
import LabelTransport
import MacLabelKit
import Observation

/// What the print bar shows.
public enum PrintPhase: Equatable, Sendable {
    case idle
    /// The `JobSpacing` pause after the previous job runs; the device is not open yet.
    case positioning(remaining: Duration)
    case printing(done: Int, total: Int)
    case finished(Int)
    case cancelled(printed: Int, total: Int)
    case failed(String)

    /// The user-facing text, `nil` while idle.
    public var message: String? { message(bundle: L10n.bundle) }

    func message(bundle: Bundle) -> String? {
        switch self {
        case .idle: nil
        case .positioning: String(localized: "The printer is positioning the label …", bundle: bundle)
        case .printing(let done, let total): String(localized: "Printing label \(min(done + 1, total)) of \(total) …", bundle: bundle)
        case .finished(let count): String(localized: "\(count) labels printed.", bundle: bundle)
        case .cancelled(let printed, let total):
            String(localized: "Cancelled after \(printed) of \(total) labels. If needed, press the feed button to eject a partly printed label.", bundle: bundle)
        case .failed(let text): text
        }
    }
}

/// The window's state: printers, roll, document, preview and print progress.
@MainActor @Observable
public final class AppModel {
    public var document = LabelDocument() {
        didSet { if document != oldValue { schedulePreview() } }
    }
    public var roll: LabelRoll? {
        didSet { if roll != oldValue { schedulePreview() } }
    }
    public private(set) var printers: [DiscoveredPrinter] = []
    public var selectedPrinter: DiscoveredPrinter? {
        didSet { selectionChanged(from: oldValue) }
    }
    public private(set) var previewResult: PreviewResult?
    public var previewPage = 0
    /// Set when a printer is selected for which no roll is remembered; asked at most once per printer.
    /// The roll sheet sets it back to `false` when dismissed.
    public var needsRollChoice = false
    public private(set) var printPhase: PrintPhase = .idle
    public let monitor: PrinterMonitor

    @ObservationIgnored private let printer: LabelPrinter
    @ObservationIgnored private let preview: PreviewEngine
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var rollTask: Task<Void, Never>?
    @ObservationIgnored private var printTask: Task<Void, any Error>?
    @ObservationIgnored private var askedRollFor: Set<String> = []
    @ObservationIgnored private var printedSoFar = 0

    private static let fallbackModel = PrinterModel.lookup(productID: 0x20)!

    public init(printer: LabelPrinter = .shared, preview: PreviewEngine = PreviewEngine()) {
        self.printer = printer
        self.preview = preview
        self.monitor = PrinterMonitor(printer: printer)
        monitor.rediscover = { [weak self] in await self?.refreshPrinters() }
        schedulePreview()
    }

    /// Reads the attached printers and keeps or picks the selection (first LW-Classic printer).
    public func refreshPrinters() async {
        let list = await printer.availablePrinters()
        printers = list
        if let current = selectedPrinter, let same = list.first(where: { Self.key($0) == Self.key(current) }) {
            if same != current { selectedPrinter = same }
        } else {
            selectedPrinter = list.first { $0.model.family == .lwClassic } ?? list.first
        }
        await rollTask?.value
    }

    /// Uses `roll` and remembers it for the selected printer.
    public func chooseRoll(_ roll: LabelRoll) {
        self.roll = roll
        needsRollChoice = false
        if let selected = selectedPrinter {
            Task { [printer] in await printer.remember(roll, for: selected) }
        }
    }

    /// Text from the Service or an App Intent.
    public func load(text: String) {
        var updated = document
        updated.layout = .text
        updated.text = text
        document = updated
    }

    /// Prints the whole series on the selected printer. Returns when the print ended.
    public func print(allowOverflow: Bool) async {
        guard printTask == nil else { return }
        guard let target = selectedPrinter else {
            printPhase = .failed(PrinterSelectionError.noPrinter.localizedDescription)
            return
        }
        guard target.model.family == .lwClassic else {
            printPhase = .failed(PrinterSelectionError.unsupported(modelName: target.model.name).localizedDescription)
            return
        }
        guard let roll else {
            printPhase = .failed(String(localized: "No roll selected.", bundle: L10n.bundle))
            return
        }
        let request: PrintRequest
        do {
            request = PrintRequest(
                contents: try document.contents(), roll: roll, model: target.model,
                density: document.density, quality: document.quality, rotation: document.rotation,
                continuousLengthMM: document.continuousLengthMM, allowOverflow: allowOverflow
            )
        } catch {
            printPhase = .failed(error.localizedDescription)
            return
        }

        let total = request.contents.count
        printedSoFar = 0
        printPhase = .printing(done: 0, total: total)
        monitor.pause()
        defer { monitor.resume() }

        // Events arrive from the printer actor; the stream keeps their order.
        let (events, continuation) = AsyncStream.makeStream(of: PrintPhaseEvent.self)
        let job = Task { [printer] in
            defer { continuation.finish() }
            try await printer.print(request, on: target) { continuation.yield($0) }
        }
        printTask = job
        defer { printTask = nil }

        for await event in events { apply(event) }
        do {
            try await withTaskCancellationHandler {
                try await job.value
            } onCancel: {
                job.cancel()
            }
            printPhase = .finished(total)
        } catch {
            if job.isCancelled {
                printPhase = .cancelled(printed: printedSoFar, total: total)
            } else {
                printPhase = .failed(error.localizedDescription)
            }
        }
    }

    /// Whether a print is waiting for the printer or running.
    public var isPrinting: Bool {
        switch printPhase {
        case .positioning, .printing: true
        default: false
        }
    }

    /// Why Print is unavailable before anything is sent, or `nil` when it can start.
    public var printBlockReason: String? {
        guard let target = selectedPrinter else { return L10n.string("No printer connected.") }
        guard target.model.family == .lwClassic else {
            return PrinterSelectionError.unsupported(modelName: target.model.name).localizedDescription
        }
        guard roll != nil else { return L10n.string("No roll selected.") }
        return nil
    }

    /// Stops the running print after the current label.
    public func cancelPrint() {
        printTask?.cancel()
    }

    private func apply(_ event: PrintPhaseEvent) {
        switch event {
        case .positioning(let remaining):
            printPhase = .positioning(remaining: remaining)
        case .label(let done, let total):
            printedSoFar = done
            printPhase = .printing(done: done, total: total)
        }
    }

    private func selectionChanged(from old: DiscoveredPrinter?) {
        monitor.target = selectedPrinter
        if selectedPrinter?.model != old?.model { schedulePreview() }
        guard let selected = selectedPrinter, old.map(Self.key) != Self.key(selected) else { return }
        rollTask = Task { [printer] in
            let remembered = await printer.rememberedRoll(for: selected)
            guard self.selectedPrinter.map(Self.key) == Self.key(selected) else { return }
            if let remembered {
                self.roll = remembered
                self.needsRollChoice = false
            } else if self.askedRollFor.insert(Self.key(selected)).inserted {
                self.needsRollChoice = true
            }
        }
    }

    /// Identifies a printer across re-plugging (the registry id changes, the serial does not).
    private static func key(_ printer: DiscoveredPrinter) -> String {
        printer.serialNumber.map { "sn:\($0)" } ?? "id:\(printer.id)"
    }

    private func schedulePreview() {
        previewTask?.cancel()
        let document = document
        let roll = roll
        let model = selectedPrinter.flatMap { $0.model.family == .lwClassic ? $0.model : nil } ?? Self.fallbackModel
        previewTask = Task { [weak self, preview] in
            let result = await preview.update(document: document, roll: roll, model: model) { first in
                self?.showPreview(first, final: false)
            }
            if let result { self?.showPreview(result, final: true) }
        }
    }

    /// The page-1 pass must not move the reader back to page 1; only the final result clamps
    /// `previewPage`. Views therefore clamp the index themselves when reading `pages`.
    private func showPreview(_ result: PreviewResult, final: Bool) {
        previewResult = result
        if final { previewPage = min(previewPage, max(result.pages.count - 1, 0)) }
    }
}
