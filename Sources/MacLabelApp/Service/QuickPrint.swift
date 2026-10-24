import Foundation
import LabelMedia
import LabelTransport
import MacLabelKit

/// Why a print without a window (App Intent) did not start. It never asks back; the text says what to do.
public enum QuickPrintError: Error, Equatable, Sendable {
    case emptyText
    case invalidCopies
    case noPrinter(String)
    /// No roll named and none remembered for the printer.
    case noRoll
    case noMatchingRoll(String)
    /// The query matches rolls of different sizes.
    case ambiguousRoll(String, [String])
    case overflow
    /// Busy, not ready, disconnected or printing: the printer's status text.
    case printerNotReady(String)
    case failed(String)
}

extension QuickPrintError: LocalizedError {
    public var errorDescription: String? { text(bundle: L10n.bundle) }

    func text(bundle: Bundle) -> String {
        switch self {
        case .emptyText:
            String(localized: "There is no text to print.", bundle: bundle)
        case .invalidCopies:
            String(localized: "The number of copies must be between 1 and 999.", bundle: bundle)
        case .noPrinter(let text), .failed(let text):
            text
        case .noRoll:
            String(localized: "No roll is chosen for this printer. Choose the loaded roll in MacLabel or name it in the shortcut.", bundle: bundle)
        case .noMatchingRoll(let query):
            String(localized: "No roll matches “\(query)”.", bundle: bundle)
        case .ambiguousRoll(let query, let ids):
            String(localized: "“\(query)” matches several rolls (\(ids.joined(separator: ", "))). Name the article number.", bundle: bundle)
        case .overflow:
            String(localized: "The text does not fit on the label. Open it in MacLabel to shorten it or choose another roll.", bundle: bundle)
        case .printerNotReady(let status):
            String(localized: "The printer cannot print right now: \(status).", bundle: bundle)
        }
    }
}

extension LabelPrinter {
    /// Prints `text` as `copies` text labels without any window: picks the default or first LW-Classic
    /// printer, the roll from `rollQuery` or the one remembered for that printer, refuses overflow and a
    /// printer that is not ready. Returns the number of labels printed.
    public func printText(
        _ text: String, copies: Int, rollQuery: String?, preferredSerial: String? = AppSettings().defaultPrinterSerial
    ) async throws -> Int {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw QuickPrintError.emptyText }
        guard (1...999).contains(copies) else { throw QuickPrintError.invalidCopies }
        let target = try selectPrinter(preferredSerial: preferredSerial)

        let query = rollQuery.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        let roll: LabelRoll
        switch RollChoice.choose(query: query, catalog: .bundled, remembered: rememberedRoll(for: target)?.id) {
        case .resolved(let chosen, _): roll = chosen
        case .ambiguous(let rolls): throw QuickPrintError.ambiguousRoll(query ?? "", rolls.map(\.id))
        case .none: throw query.map(QuickPrintError.noMatchingRoll) ?? .noRoll
        }

        var document = LabelDocument()
        document.text = text
        document.copies = copies
        let request: PrintRequest
        // Overflow and other content errors before the device is touched. All copies are the same label.
        do {
            request = PrintRequest(contents: try document.contents(), roll: roll, model: target.model, allowOverflow: false)
            var first = request
            first.contents = Array(request.contents.prefix(1))
            _ = try PrintService.render(first)
        } catch PrintError.overflow {
            throw QuickPrintError.overflow
        } catch {
            throw QuickPrintError.failed(error.localizedDescription)
        }

        let state = await state(for: target)
        guard case .ready = state else { throw QuickPrintError.printerNotReady(state.statusText) }
        do {
            try await print(request, on: target) { _ in }
        } catch PrintError.overflow {
            throw QuickPrintError.overflow
        } catch let error as PrintError {
            throw QuickPrintError.failed(error.localizedDescription)
        }
        return request.contents.count
    }

    /// "LabelWriter 450 · ready" for the printer an intent would use.
    public func statusText(preferredSerial: String? = AppSettings().defaultPrinterSerial) async -> String {
        let target = try? selectPrinter(preferredSerial: preferredSerial)
        if target == nil, let first = availablePrinters().first {
            return await state(for: first).statusText
        }
        return await state(for: target).statusText
    }

    /// The default printer when connected, otherwise the first LW-Classic printer.
    private func selectPrinter(preferredSerial: String?) throws -> DiscoveredPrinter {
        let printers = availablePrinters()
        do {
            if let preferredSerial, printers.contains(where: { $0.serialNumber == preferredSerial }) {
                return try PrinterSelection.select(serial: preferredSerial, from: printers)
            }
            return try PrinterSelection.select(serial: nil, from: printers)
        } catch {
            throw QuickPrintError.noPrinter(error.localizedDescription)
        }
    }
}
