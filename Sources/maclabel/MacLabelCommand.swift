import ArgumentParser
import Foundation
import LabelProtocol
import LabelTransport
import MacLabelKit

@main
struct MacLabel: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "maclabel",
        abstract: "Print labels on a DYMO LabelWriter.",
        subcommands: [PrintCommand.self, StatusCommand.self, RollsCommand.self, PrintersCommand.self]
    )
}

/// Documented exit codes.
enum Exit {
    static let notReady: Int32 = 1
    static let usage: Int32 = 64
    static let overflow: Int32 = 65
    static let noPrinter: Int32 = 69
    static let internalError: Int32 = 70
    static let busy: Int32 = 75
}

/// Small de/en switch for the CLI's own texts (errors from the kit localize themselves).
enum CLIText {
    static var german: Bool { Locale.preferredLanguages.first?.hasPrefix("de") == true }
    static func tr(_ de: String, _ en: String) -> String { german ? de : en }
}

func writeStderr(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

/// Prints `message` to stderr and exits with `code`.
func fail(_ message: String, code: Int32) -> ExitCode {
    writeStderr(message)
    return ExitCode(code)
}

func exitCode(for error: any Error) -> Int32 {
    switch error {
    case let e as PrintError:
        switch e {
        case .overflow: Exit.overflow
        case .printerNotReady, .interrupted: Exit.notReady
        case .nothingToPrint, .rollTooWide, .invalidLength, .render: Exit.usage
        case .unsupportedPrinter: Exit.noPrinter
        case .transport(let t): exitCode(for: t)
        }
    case let e as TransportError:
        switch e {
        case .busy: Exit.busy
        case .notFound: Exit.noPrinter
        default: Exit.internalError
        }
    case is BatchError, is CSVError: Exit.usage
    default: Exit.internalError
    }
}

func message(for error: any Error) -> String {
    if let t = error as? TransportError { return PrintError.transport(t).localizedDescription }
    if let b = error as? BatchError {
        switch b {
        case .unknownPlaceholder(let name):
            return CLIText.tr("Unbekannter Platzhalter {\(name)}.", "Unknown placeholder {\(name)}.")
        case .invalidCopies:
            return CLIText.tr("Die Anzahl der Kopien muss mindestens 1 sein.", "Copies must be at least 1.")
        }
    }
    if let c = error as? CSVError {
        switch c {
        case .noHeader: return CLIText.tr("Die CSV-Datei ist leer.", "The CSV file is empty.")
        case .unterminatedQuote(let line):
            return CLIText.tr("CSV: Anführungszeichen in Zeile \(line) nicht geschlossen.", "CSV: unterminated quote on line \(line).")
        }
    }
    return error.localizedDescription
}

/// Converts any thrown error into message + exit code.
func exitFailure(_ error: any Error) -> ExitCode {
    if error is ExitCode { return error as! ExitCode }
    return fail(message(for: error), code: exitCode(for: error))
}

enum PrinterSelection {
    /// The printer named by `serial`, or else the first LW-Classic printer.
    /// Throws `ExitCode` (69) with a message when none is usable.
    static func select(serial: String?, printers: [DiscoveredPrinter] = USBPrinterDiscovery.printers()) throws -> DiscoveredPrinter {
        if let serial {
            guard let match = printers.first(where: { $0.serialNumber == serial }) else {
                throw fail(CLIText.tr("Kein Drucker mit Seriennummer \(serial) gefunden.", "No printer with serial number \(serial) found."), code: Exit.noPrinter)
            }
            guard match.model.family == .lwClassic else { throw unsupported(match) }
            return match
        }
        if let classic = printers.first(where: { $0.model.family == .lwClassic }) { return classic }
        if let other = printers.first { throw unsupported(other) }
        throw fail(PrintError.transport(.notFound).localizedDescription, code: Exit.noPrinter)
    }

    private static func unsupported(_ printer: DiscoveredPrinter) -> ExitCode {
        fail(PrintError.unsupportedPrinter(printer.model.name).localizedDescription, code: Exit.noPrinter)
    }
}
