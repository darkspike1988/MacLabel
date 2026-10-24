import Foundation
import LabelTransport

public enum PrinterSelectionError: Error, Equatable {
    case noPrinter
    case unsupported(modelName: String)
    case serialNotFound(String)
}

extension PrinterSelectionError: LocalizedError {
    public var errorDescription: String? {
        let bundle = L10n.bundle
        switch self {
        case .noPrinter: return String(localized: "No printer found.", bundle: bundle)
        case .unsupported(let name): return String(localized: "The printer \(name) is not supported.", bundle: bundle)
        case .serialNotFound(let serial): return String(localized: "No printer with serial number \(serial) found.", bundle: bundle)
        }
    }
}

public enum PrinterSelection {
    /// The printer with `serial`, or else the first LW-Classic printer.
    public static func select(serial: String?, from printers: [DiscoveredPrinter]) throws -> DiscoveredPrinter {
        if let serial {
            guard let match = printers.first(where: { $0.serialNumber == serial }) else {
                throw PrinterSelectionError.serialNotFound(serial)
            }
            guard match.model.family == .lwClassic else { throw PrinterSelectionError.unsupported(modelName: match.model.name) }
            return match
        }
        if let classic = printers.first(where: { $0.model.family == .lwClassic }) { return classic }
        if let other = printers.first { throw PrinterSelectionError.unsupported(modelName: other.model.name) }
        throw PrinterSelectionError.noPrinter
    }
}
