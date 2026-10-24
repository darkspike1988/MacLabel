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
}

/// UI-independent print service: printer discovery, status, remembered roll and printing.
/// Used by the window, the menu bar extra and App Intents.
public actor LabelPrinter {
    private let factory: any TransportFactory
    private let preferences: RollPreferences
    private let formFeedClock: any FormFeedClock

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

    /// Prints all labels of `request` as one job. Waits the `JobSpacing` pause after the previous
    /// job's form feed first. The transport is closed on success, error and cancellation.
    public func print(
        _ request: PrintRequest,
        on printer: DiscoveredPrinter,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws {
        let transport: any PrinterTransport
        do {
            transport = try factory.open(printer)
        } catch let error as TransportError {
            throw PrintError.transport(error)
        }
        do {
            try await PrintService.print(
                request, using: transport,
                spacing: JobSpacing(clock: formFeedClock, serial: printer.serialNumber),
                progress: progress
            )
        } catch {
            await transport.close()
            throw error
        }
        await transport.close()
        remember(request.roll, for: printer)
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
