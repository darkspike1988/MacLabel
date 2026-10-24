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
        subcommands: [PrintCommand.self, StatusCommand.self, RollsCommand.self, PrintersCommand.self, SimulateCommand.self]
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
    return error.localizedDescription
}

/// Converts any thrown error into message + exit code.
func exitFailure(_ error: any Error) -> ExitCode {
    if error is ExitCode { return error as! ExitCode }
    return fail(message(for: error), code: exitCode(for: error))
}

/// The printer named by `serial`, or else the first LW-Classic printer.
/// Throws `ExitCode` (69) with a message when none is usable.
func selectPrinter(serial: String?, printers: [DiscoveredPrinter] = USBPrinterDiscovery.printers()) throws -> DiscoveredPrinter {
    do {
        return try PrinterSelection.select(serial: serial, from: printers)
    } catch let error as PrinterSelectionError {
        throw fail(error.localizedDescription, code: Exit.noPrinter)
    }
}
