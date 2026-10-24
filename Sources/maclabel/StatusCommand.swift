import ArgumentParser
import MacLabelKit
import LabelProtocol
import LabelTransport

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status", abstract: "Show printer model, firmware and readiness (read-only)."
    )

    @Option(name: .long, help: "Serial number of the printer to use.")
    var printer: String?

    func run() async throws {
        let found = try selectPrinter(serial: printer)
        let status: LWStatus
        let version: LWVersion?
        do {
            let connection = try USBPrinterConnection(printer: found)
            do {
                status = try await connection.status()
                version = try await connection.version()
            } catch {
                await connection.close()
                throw error
            }
            await connection.close()
        } catch {
            throw exitFailure(error)
        }

        var line = found.model.name
        if let version { line += " (\(version.modelNumber), FW \(version.firmware))" }
        let ready = status.canPrint
        line += " · " + Self.describe(status)
        print(line)
        if !ready { throw ExitCode(Exit.notReady) }
    }

    static func describe(_ status: LWStatus) -> String {
        if status.isPaperOut { return localizedString("out of paper") }
        if status.isJammed { return localizedString("paper jam") }
        if status.hasError { return localizedString("printer error") }
        if !status.isReady { return localizedString("not ready") }
        return localizedString("ready")
    }
}
