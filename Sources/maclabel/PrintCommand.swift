import ArgumentParser
import CoreGraphics
import Foundation
import ImageIO
import LabelMedia
import LabelProtocol
import LabelRender
import LabelTransport
import MacLabelKit
import UniformTypeIdentifiers

enum LayoutOption: String, ExpressibleByArgument, CaseIterable {
    case text, qr, barcode
}

enum DensityOption: String, ExpressibleByArgument, CaseIterable {
    case light, medium, normal, dark
    var density: PrintDensity {
        switch self {
        case .light: .light
        case .medium: .medium
        case .normal: .normal
        case .dark: .dark
        }
    }
}

struct PrintCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "print", abstract: "Print one label or a series."
    )

    @Argument(help: "Label text (\\n = line break). QR payload or barcode value with --layout qr/barcode.")
    var text: String

    @Option(help: "Roll: article number, ID or size (e.g. 11354). Default: the last used roll.")
    var roll: String?

    @Option(help: "Number of copies per label.")
    var copies: Int = 1

    @Option(help: "text, qr or barcode.")
    var layout: LayoutOption = .text

    @Option(help: "Barcode type: code128, ean13, ean8, upca, code39, itf14.")
    var symbology: String = "code128"

    @Option(help: "Caption below a QR code.")
    var caption: String?

    @Option(help: "Start value of the counter {n}.")
    var counter: String?

    @Option(help: "CSV file; {column} placeholders are filled per row.")
    var csv: String?

    @Option(help: "light, medium, normal or dark. Default: automatic.")
    var density: DensityOption?

    @Option(help: "Label length in mm for continuous rolls (10 to 1000).")
    var length: Double?

    @Option(help: "Serial number of the printer to use.")
    var printer: String?

    @Flag(help: "Print even if the content does not fit.")
    var force = false

    @Option(name: .customLong("dry-run"), help: "Do not print; write a preview (.png) or the printer bytes (.bin).")
    var dryRun: String?

    func validate() throws {
        if copies < 1 { throw ValidationError(CLIText.tr("--copies muss mindestens 1 sein.", "--copies must be at least 1.")) }
        if let dryRun {
            let ext = URL(fileURLWithPath: dryRun).pathExtension.lowercased()
            if ext != "png" && ext != "bin" {
                throw ValidationError(CLIText.tr("--dry-run erwartet eine .png- oder .bin-Datei.", "--dry-run expects a .png or .bin file."))
            }
        }
    }

    func run() async throws {
        do {
            try await execute()
        } catch {
            throw exitFailure(error)
        }
    }

    private func execute() async throws {
        let body = text.replacingOccurrences(of: "\\n", with: "\n")
        let template = try makeTemplate(body)
        let counterSpec = try counter.map(Self.counterSpec)
        let table = try csv.map(Self.loadCSV)

        let batch = try LabelBatch.expand(template, copies: copies, counter: counterSpec, table: table)
        if table != nil, batch.isEmpty {
            throw fail(CLIText.tr("CSV enthält keine Datenzeilen", "CSV contains no data rows"), code: Exit.usage)
        }

        // Passive discovery only (IORegistry); no device is opened for a dry run.
        let discovered: DiscoveredPrinter?
        if dryRun != nil {
            discovered = try? PrinterSelection.select(serial: printer)
        } else {
            discovered = nil
        }
        let preferences = RollPreferences.standard()
        let serialForRoll = discovered?.serialNumber ?? printer
        let resolvedRoll = try resolveRoll(preferences: preferences, serial: serialForRoll)

        var request = PrintRequest(
            contents: batch, roll: resolvedRoll,
            model: discovered?.model ?? PrinterModel.lookup(productID: 0x20)!,
            density: density?.density, continuousLengthMM: length, allowOverflow: force
        )

        if let dryRun {
            try writeDryRun(request, to: URL(fileURLWithPath: dryRun))
            return
        }

        let found = try PrinterSelection.select(serial: printer)
        request.model = found.model
        // Render before opening the device so content errors never touch the printer.
        _ = try PrintService.prepare(request)
        let connection = try USBPrinterConnection(printer: found)
        do {
            try await PrintService.print(request, using: connection) { done, total in
                writeStderr(CLIText.tr("Etikett \(done)/\(total)…", "Label \(done)/\(total)…"))
            }
        } catch {
            await connection.close()
            throw error
        }
        await connection.close()
        RollPreferences.standard().setLastRollID(resolvedRoll.id, forPrinterSerial: found.serialNumber)
    }

    // MARK: Content

    private func makeTemplate(_ body: String) throws -> LabelContent {
        switch layout {
        case .text:
            return .text(TextContent(text: body))
        case .qr:
            return .qr(QRContent(payload: body, caption: caption?.replacingOccurrences(of: "\\n", with: "\n")))
        case .barcode:
            let wanted = symbology.lowercased()
            guard let kind = BarcodeSymbology.allCases.first(where: { $0.rawValue.lowercased() == wanted }) else {
                let names = BarcodeSymbology.allCases.map { $0.rawValue.lowercased() }.joined(separator: ", ")
                throw fail(CLIText.tr("Unbekannte Symbologie \(symbology). Möglich: \(names).", "Unknown symbology \(symbology). Options: \(names)."), code: Exit.usage)
            }
            return .barcode(BarcodeContent(symbology: kind, value: body))
        }
    }

    static func counterSpec(_ raw: String) throws -> CounterSpec {
        guard let start = Int(raw) else {
            throw fail(CLIText.tr("--counter erwartet eine ganze Zahl.", "--counter expects an integer."), code: Exit.usage)
        }
        // "007" keeps its leading zeros.
        return CounterSpec(start: start, step: 1, minimumDigits: raw.hasPrefix("-") ? 1 : raw.count)
    }

    static func loadCSV(_ path: String) throws -> CSVTable {
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw fail(CLIText.tr("CSV-Datei nicht lesbar: \(path)", "Cannot read CSV file: \(path)"), code: Exit.usage)
        }
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
        guard let text else {
            throw fail(CLIText.tr("CSV-Datei hat eine unbekannte Zeichenkodierung.", "The CSV file has an unknown text encoding."), code: Exit.usage)
        }
        return try CSVTable(parsing: text)
    }

    // MARK: Roll

    private func resolveRoll(preferences: RollPreferences, serial: String?) throws -> LabelRoll {
        let catalog = MediaCatalog.bundled
        guard let query = roll else {
            if let id = preferences.lastRollID(forPrinterSerial: serial), let remembered = catalog.roll(id: id) {
                return remembered
            }
            throw fail(
                CLIText.tr(
                    "Keine Rolle gewählt. Beispiel: maclabel print \"Text\" --roll 11354",
                    "No roll selected. Example: maclabel print \"Text\" --roll 11354"),
                code: Exit.usage)
        }
        if let exact = catalog.roll(id: query) ?? catalog.roll(sku: query) { return exact }
        let matches = catalog.search(query)
        switch matches.count {
        case 0:
            throw fail(CLIText.tr("Keine Rolle gefunden für \"\(query)\".", "No roll found for \"\(query)\"."), code: Exit.usage)
        case 1:
            return matches[0]
        default:
            let head = CLIText.tr(
                "Rolle \"\(query)\" ist mehrdeutig. Bitte genauer angeben:",
                "Roll \"\(query)\" is ambiguous. Please be more specific:")
            throw fail(head + "\n" + rollTable(Array(matches.prefix(10))), code: Exit.usage)
        }
    }

    // MARK: Dry run

    private func writeDryRun(_ request: PrintRequest, to url: URL) throws {
        let job = try PrintService.prepare(request)
        if url.pathExtension.lowercased() == "bin" {
            try Data(job.bytes).write(to: url)
            return
        }
        guard let preview = job.renders.first?.preview,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw PrintError.nothingToPrint }
        CGImageDestinationAddImage(destination, preview, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw fail(CLIText.tr("Vorschau konnte nicht geschrieben werden.", "Could not write the preview."), code: Exit.internalError)
        }
    }
}
