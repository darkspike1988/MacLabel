import AppKit
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

    /// A print is waiting for the printer or running.
    public var isActive: Bool {
        switch self {
        case .positioning, .printing: true
        default: false
        }
    }

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
    /// The last failed import (shown in an alert); a successful import clears it.
    public private(set) var importError: String?
    public var showsImportError = false
    public private(set) var printPhase: PrintPhase = .idle
    /// The roll popover in the window's toolbar (⌘L, Label › Choose Roll…).
    public var showsRollPicker = false
    /// The "Print anyway?" question before an overflowing print (Print button and File › Print…).
    public var confirmsOverflowPrint = false
    /// The main window's undo manager (set by the window). Replacing the document with
    /// `load(text:)` registers there, so Edit › Undo brings the previous document back.
    @ObservationIgnored public weak var undoManager: UndoManager? {
        didSet { registerPendingUndo() }
    }
    /// The document a `load(text:)` replaced while no window (undo manager) was there yet.
    @ObservationIgnored private var pendingUndo: LabelDocument?
    public let monitor: PrinterMonitor

    @ObservationIgnored private let printer: LabelPrinter
    @ObservationIgnored private let preview: PreviewEngine
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var rollTask: Task<Void, Never>?
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var printTask: Task<Void, any Error>?
    @ObservationIgnored private var askedRollFor: Set<String> = []
    @ObservationIgnored private var printedSoFar = 0

    private static let fallbackModel = PrinterModel.lookup(productID: 0x20)!

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var settingsObserver: (any NSObjectProtocol)?
    /// The default-printer setting last applied; only a change of this value moves the selection.
    @ObservationIgnored private var appliedDefaultSerial: String?

    public init(printer: LabelPrinter = .shared, preview: PreviewEngine = PreviewEngine(), defaults: UserDefaults = .standard) {
        self.printer = printer
        self.preview = preview
        self.defaults = defaults
        self.appliedDefaultSerial = AppSettings(defaults: defaults).defaultPrinterSerial
        self.monitor = PrinterMonitor(printer: printer)
        monitor.rediscover = { [weak self] in await self?.refreshPrinters() }
        schedulePreview()
        applySettings()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        }
    }

    /// Applies the Settings: status polling on/off and the default printer.
    func applySettings() {
        let settings = AppSettings(defaults: defaults)
        monitor.pollingEnabled = settings.statusPolling
        // Any key of the defaults domain posts the notification; act only on this setting's change.
        let serial = settings.defaultPrinterSerial
        guard serial != appliedDefaultSerial else { return }
        appliedDefaultSerial = serial
        guard let serial, selectedPrinter?.serialNumber != serial,
              let wanted = printers.first(where: { $0.serialNumber == serial }) else { return }
        selectedPrinter = wanted
    }

    isolated deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    /// Imports the first supported file of a drop or file choice. A newer import cancels the one in flight.
    public func startImport(_ urls: [URL]) {
        importTask?.cancel()
        importTask = Task {
            do {
                if try await ImportHelpers.importFiles(urls, into: self) { importError = nil }
            } catch is CancellationError {
            } catch where Task.isCancelled {
                // A newer import replaced this one; its outcome wins.
            } catch {
                importError = error.localizedDescription
                showsImportError = true
            }
        }
    }

    /// Waits for the import started last.
    public func finishImport() async { await importTask?.value }

    /// Reads the attached printers and keeps or picks the selection (first LW-Classic printer).
    public func refreshPrinters() async {
        let list = await printer.availablePrinters()
        printers = list
        if let current = selectedPrinter, let same = list.first(where: { Self.key($0) == Self.key(current) }) {
            if same != current { selectedPrinter = same }
        } else {
            let preferred = AppSettings(defaults: defaults).defaultPrinterSerial
            selectedPrinter = list.first { preferred != nil && $0.serialNumber == preferred }
                ?? list.first { $0.model.family == .lwClassic } ?? list.first
        }
        await rollTask?.value
    }

    /// The window or the menu bar panel opened: reads the printers and asks the status once,
    /// also when automatic polling is off (one rule for both).
    public func surfaceOpened() async {
        await refreshPrinters()
        await monitor.refreshNow()
    }

    /// Uses `roll` and remembers it for the selected printer.
    public func chooseRoll(_ roll: LabelRoll) {
        self.roll = roll
        needsRollChoice = false
        if let selected = selectedPrinter {
            Task { [printer] in await printer.remember(roll, for: selected) }
        }
    }

    /// Text from the Service or "Text too long – open in window". Replaces the window's text label;
    /// Edit › Undo restores the previous document (registered as soon as the window is there).
    public func load(text: String) {
        var updated = document
        updated.layout = .text
        updated.text = text
        guard updated != document else { return }
        endEditingInWindow()
        let previous = document
        document = updated
        if let undoManager {
            registerUndo(restoring: previous, on: undoManager)
        } else {
            pendingUndo = previous
        }
    }

    /// Ends typing in the main window (the window whose undo manager is ours), so the text view's
    /// typing undo group is closed before the replacement is registered as its own step.
    private func endEditingInWindow() {
        guard let undoManager, let app = NSApp,
              let window = app.windows.first(where: { $0.undoManager === undoManager }) else { return }
        (window.firstResponder as? NSTextView)?.breakUndoCoalescing()
        window.makeFirstResponder(nil)
    }

    private func registerPendingUndo() {
        guard let undoManager, let previous = pendingUndo else { return }
        pendingUndo = nil
        registerUndo(restoring: previous, on: undoManager)
    }

    /// Registers "restore `previous`" as one undo step.
    private func registerUndo(restoring previous: LabelDocument, on undoManager: UndoManager) {
        undoManager.beginUndoGrouping()
        registerRestore(previous, on: undoManager)
        undoManager.endUndoGrouping()
    }

    /// Undoing restores `previous` and registers the way back (redo, and undo again after a redo).
    private func registerRestore(_ previous: LabelDocument, on undoManager: UndoManager) {
        // Weak: the undo manager owns this action; a strong capture would keep it alive forever.
        undoManager.registerUndo(withTarget: self) { [weak undoManager] model in
            MainActor.assumeIsolated {
                let current = model.document
                model.document = previous
                if let undoManager { model.registerRestore(current, on: undoManager) }
            }
        }
        undoManager.setActionName(L10n.string("Replace Label Text"))
    }

    /// Print can start now (File › Print…, the Print button).
    public var canRequestPrint: Bool {
        printBlockReason == nil && !isPrinting && previewResult?.error == nil
    }

    /// File › Print… and the Print button: asks "Print anyway?" first when content overflows, else prints.
    public func requestPrint() {
        guard canRequestPrint else { return }
        if previewResult?.overflowIndices.isEmpty == false {
            confirmsOverflowPrint = true
        } else {
            // The preview covers at most the first 50 labels; a later overflow is caught by the print.
            Task { await print(document: document, allowOverflow: false, asksOnOverflow: true) }
        }
    }

    /// Prints the whole series on the selected printer. Returns when the print ended.
    public func print(allowOverflow: Bool) async {
        await print(document: document, allowOverflow: allowOverflow)
    }

    /// Prints `document` (the window's, or the menu bar panel's text) on the selected printer.
    public func print(document: LabelDocument, allowOverflow: Bool) async {
        await print(document: document, allowOverflow: allowOverflow, asksOnOverflow: false)
    }

    /// `asksOnOverflow`: an overflow found while printing (beyond the previewed labels) asks
    /// "Print anyway?" instead of failing.
    private func print(document: LabelDocument, allowOverflow: Bool, asksOnOverflow: Bool) async {
        guard printTask == nil else { return }
        guard let target = selectedPrinter else {
            printPhase = .failed(L10n.string("No printer connected."))
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
            } else if asksOnOverflow, !allowOverflow, case PrintError.overflow = error {
                printPhase = .idle
                confirmsOverflowPrint = true
            } else {
                printPhase = .failed(error.localizedDescription)
            }
        }
    }

    /// Whether a print is waiting for the printer or running.
    public var isPrinting: Bool { printPhase.isActive }

    /// Forgets the result of the last print (finished, cancelled, failed); a running print stays.
    public func clearPrintOutcome() {
        if !isPrinting { printPhase = .idle }
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
        // The old printer's roll must not outlive the switch while the new printer's roll is looked up.
        if let old, selectedPrinter.map(Self.key) != Self.key(old) { roll = nil }
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

    /// The selected LW-Classic model, or the LabelWriter 450 for previews without a printer.
    var effectiveModel: PrinterModel {
        selectedPrinter.flatMap { $0.model.family == .lwClassic ? $0.model : nil } ?? Self.fallbackModel
    }

    private func schedulePreview() {
        previewTask?.cancel()
        let document = document
        let roll = roll
        let model = effectiveModel
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
