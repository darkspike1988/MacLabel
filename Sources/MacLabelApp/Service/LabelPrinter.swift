import Foundation
import LabelMedia
import LabelProtocol
import LabelTransport
import MacLabelKit

/// What the UI shows about the selected printer.
public enum PrinterState: Equatable, Sendable {
    case noPrinter
    case unsupported(String)
    case ready(name: String)
    case notReady(name: String, reason: String)
    case busy(name: String)
    case disconnected
    case error(String)
    /// A print to this printer is active or waiting; the device is not queried meanwhile.
    case printing(name: String)
}

/// Progress of one `LabelPrinter.print` call.
public enum PrintPhaseEvent: Sendable, Equatable {
    case positioning(remaining: Duration)
    case label(done: Int, total: Int)
}

/// UI-independent print service: printer discovery, status, remembered roll and printing.
/// Used by the window, the menu bar extra, the Service and App Intents.
///
/// Device access (`print`, `state`) goes through a FIFO gate: actor isolation alone does not
/// serialize it, because the actor is reentrant at every `await`.
public actor LabelPrinter {
    /// The process-wide instance all entry points share, so they also share the gate.
    public static let shared = LabelPrinter()
    private let factory: any TransportFactory
    private let preferences: RollPreferences
    private let formFeedClock: any FormFeedClock
    private var gateHeld = false
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []
    /// Prints started (waiting or running) per printer id.
    private var activePrints: [UInt64: Int] = [:]

    public init(
        factory: any TransportFactory = LabelPrinter.makeDefault(),
        preferences: RollPreferences = .standard(),
        formFeedClock: any FormFeedClock = UserDefaultsFormFeedClock.standard()
    ) {
        self.factory = factory
        self.preferences = preferences
        self.formFeedClock = formFeedClock
    }

    public func availablePrinters() -> [DiscoveredPrinter] {
        factory.printers()
    }

    /// Opens the printer, asks `ESC A` once and closes it again.
    public func state(for printer: DiscoveredPrinter?) async -> PrinterState {
        guard let printer else { return .noPrinter }
        let name = printer.model.name
        guard printer.model.family == .lwClassic else { return .unsupported(name) }
        if activePrints[printer.id, default: 0] > 0 { return .printing(name: name) }

        await acquireGate()
        defer { releaseGate() }
        // A print may have started while this query waited for the gate.
        if activePrints[printer.id, default: 0] > 0 { return .printing(name: name) }
        let transport: any PrinterTransport
        do {
            transport = try factory.open(printer)
        } catch {
            return Self.state(for: error, name: name)
        }
        let result: PrinterState
        do {
            let status = try await transport.status()
            result = status.canPrint ? .ready(name: name) : .notReady(name: name, reason: Self.reason(status))
        } catch {
            result = Self.state(for: error, name: name)
        }
        await transport.close()
        return result
    }

    public func rememberedRoll(for printer: DiscoveredPrinter) -> LabelRoll? {
        preferences.lastRollID(forPrinterSerial: printer.serialNumber).flatMap { MediaCatalog.bundled.roll(id: $0) }
    }

    public func remember(_ roll: LabelRoll, for printer: DiscoveredPrinter) {
        preferences.setLastRollID(roll.id, forPrinterSerial: printer.serialNumber)
    }

    /// Prints all labels of `request` as one job. Waits for the gate (FIFO), then for the
    /// `JobSpacing` pause after the previous job's form feed (device not open meanwhile; reported
    /// once as `.positioning`), then prints. The transport is closed on success, error and cancellation.
    public func print(
        _ request: PrintRequest,
        on printer: DiscoveredPrinter,
        onPhase: @escaping @Sendable (PrintPhaseEvent) -> Void
    ) async throws {
        guard printer.model.family == .lwClassic, request.model == printer.model else {
            throw PrintError.unsupportedPrinter(printer.model.name)
        }
        activePrints[printer.id, default: 0] += 1
        defer { activePrints[printer.id, default: 0] -= 1 }
        await acquireGate()
        defer { releaseGate() }

        let spacing = JobSpacing(clock: formFeedClock, serial: printer.serialNumber)
        let pause = spacing.remainingPause()
        if pause > .zero {
            onPhase(.positioning(remaining: pause))
            try await Task.sleep(for: pause)
        }
        try Task.checkCancellation()

        let transport: any PrinterTransport
        do {
            transport = try factory.open(printer)
        } catch let error as TransportError {
            throw PrintError.transport(error)
        }
        do {
            try await PrintService.print(
                request, using: transport, spacing: spacing,
                progress: { onPhase(.label(done: $0, total: $1)) }
            )
        } catch {
            await transport.close()
            throw error
        }
        await transport.close()
        remember(request.roll, for: printer)
    }

    /// Waits until no other `print`/`state` uses a device; waiters are served in arrival order.
    private func acquireGate() async {
        guard gateHeld else {
            gateHeld = true
            return
        }
        await withCheckedContinuation { gateWaiters.append($0) }
        // Ownership was handed over by `releaseGate`; `gateHeld` is still true.
    }

    private func releaseGate() {
        if gateWaiters.isEmpty {
            gateHeld = false
        } else {
            gateWaiters.removeFirst().resume()
        }
    }

    private static func state(for error: any Error, name: String) -> PrinterState {
        switch error as? TransportError {
        case .busy: .busy(name: name)
        case .disconnected, .notFound: .disconnected
        case .some(let transportError): .error(PrintError.transport(transportError).localizedDescription)
        case nil: .error(error.localizedDescription)
        }
    }

    private static func reason(_ status: LWStatus) -> String {
        if status.isPaperOut { return localizedString("out of paper") }
        if status.isJammed { return localizedString("paper jam") }
        if status.hasError { return localizedString("printer error") }
        return localizedString("not ready")
    }
}
