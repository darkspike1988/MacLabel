import ArgumentParser
import MacLabelKit
import LabelProtocol
import LabelTransport

struct PrintersCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "printers", abstract: "List attached DYMO printers."
    )

    func run() throws {
        let printers = USBPrinterDiscovery.printers()
        guard !printers.isEmpty else {
            throw fail(PrintError.transport(.notFound).localizedDescription, code: Exit.noPrinter)
        }
        let rows = [[CLIText.tr("Modell", "Model"), CLIText.tr("Seriennummer", "Serial"), CLIText.tr("Unterstützung", "Support")]]
            + printers.map { p in
                [
                    p.model.name,
                    p.serialNumber ?? "-",
                    p.model.family == .lwClassic
                        ? CLIText.tr("unterstützt", "supported")
                        : CLIText.tr("nicht unterstützt", "not supported"),
                ]
            }
        print(formatTable(rows))
    }
}

/// Left-aligned columns separated by two spaces; the last column is not padded.
func formatTable(_ rows: [[String]]) -> String {
    guard let columns = rows.first?.count else { return "" }
    var widths = [Int](repeating: 0, count: columns)
    for row in rows { for (i, cell) in row.enumerated() { widths[i] = max(widths[i], cell.count) } }
    return rows.map { row in
        row.enumerated().map { i, cell in
            i == columns - 1 ? cell : cell + String(repeating: " ", count: widths[i] - cell.count)
        }.joined(separator: "  ")
    }.joined(separator: "\n")
}
