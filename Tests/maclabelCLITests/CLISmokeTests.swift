import Foundation
import LabelMedia
import LabelTransport
import MacLabelKit
import Testing
@testable import maclabel

/// Runs the built `maclabel` binary. Never touches a printer: only `--dry-run`, `rolls` and usage errors.
@Suite struct CLISmokeTests {
    struct Result {
        let status: Int32
        let out: String
        let err: String
    }

    static var binaryURL: URL {
        if let bundle = Bundle.allBundles.first(where: { $0.bundlePath.hasSuffix(".xctest") }) {
            let url = bundle.bundleURL.deletingLastPathComponent().appendingPathComponent("maclabel")
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/debug/maclabel")
    }

    /// Runs the CLI against the debug-only fake printer (`MACLABEL_FAKE_PRINTER`, Ruling A25): it
    /// discovers one "LabelWriter 450" (serial FAKE) and writes print data to `fakePrinter`, never
    /// to a USB device; tests do not depend on connected hardware.
    static func run(
        _ args: [String], suite: String = "maclabel.test.\(UUID().uuidString)",
        fakePrinter: URL = tempURL("fake-printer.bin")
    ) throws -> Result {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["MACLABEL_DEFAULTS_SUITE"] = suite
        env["MACLABEL_FAKE_PRINTER"] = fakePrinter.path
        process.environment = env
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(
            status: process.terminationStatus,
            out: String(decoding: outData, as: UTF8.self),
            err: String(decoding: errData, as: UTF8.self)
        )
    }

    static func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("maclabel-\(UUID().uuidString)-\(name)")
    }

    /// The CLI inside an app bundle (`Contents/Helpers` in MacLabel.app, `Contents/MacOS` also supported),
    /// started by bare name through a symlink on PATH, must find its resources.
    @Test(arguments: ["Helpers", "MacOS"]) func resourcesFoundViaSymlinkOnPath(_ folder: String) throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("maclabel-app-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let macOS = root.appendingPathComponent("X.app/Contents/\(folder)")
        let resources = root.appendingPathComponent("X.app/Contents/Resources")
        let bin = root.appendingPathComponent("bin")
        for dir in [macOS, resources, bin] { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        try fm.copyItem(at: Self.binaryURL, to: macOS.appendingPathComponent("maclabel"))
        let built = Self.binaryURL.deletingLastPathComponent()
        let bundles = try fm.contentsOfDirectory(atPath: built.path).filter {
            $0.hasPrefix("MacLabelKit_") && $0.hasSuffix(".bundle") && !$0.contains("Tests")
        }
        #expect(!bundles.isEmpty)
        for name in bundles { try fm.copyItem(at: built.appendingPathComponent(name), to: resources.appendingPathComponent(name)) }
        // Mark the copy so the test proves the bundle beside the executable is used, not the build directory's.
        let copiedJSON = try #require(fm.enumerator(at: resources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.first { $0.lastPathComponent == "media.json" })
        let json = try String(contentsOf: copiedJSON, encoding: .utf8)
        try json.replacingOccurrences(of: "\"Vielzweck\"", with: "\"Vielzweck-COPY\"").write(to: copiedJSON, atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: bin.appendingPathComponent("maclabel"), withDestinationURL: macOS.appendingPathComponent("maclabel"))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["maclabel", "rolls", "search", "32x57"]
        process.environment = ["PATH": bin.path, "MACLABEL_DEFAULTS_SUITE": "maclabel.test.\(UUID().uuidString)"]
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let outText = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errText = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "\(errText)")
        #expect(outText.contains("11354"))
        #expect(outText.contains("Vielzweck-COPY"), "resources came from elsewhere:\n\(outText)")
    }

    @Test func rollsSearchFindsRoll() throws {
        let r = try Self.run(["rolls", "search", "32x57"])
        #expect(r.status == 0)
        #expect(r.out.contains("11354"))
        #expect(r.out.contains("57 × 32 mm"))
    }

    @Test func dryRunBinWritesJob() throws {
        let url = Self.tempURL("x.bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let r = try Self.run(["print", "Test", "--roll", "S0722540", "--dry-run", url.path])
        #expect(r.status == 0, "\(r.err)")
        let bytes = [UInt8](try Data(contentsOf: url))
        #expect(bytes.count > 156)
        #expect(Array(bytes.prefix(156)) == [UInt8](repeating: 0x1B, count: 156))
    }

    @Test func dryRunPNGWritesPreview() throws {
        let url = Self.tempURL("x.png")
        defer { try? FileManager.default.removeItem(at: url) }
        let r = try Self.run(["print", "Hallo\\nWelt", "--roll", "11354", "--dry-run", url.path])
        #expect(r.status == 0, "\(r.err)")
        let data = try Data(contentsOf: url)
        #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    /// Non-dry `print` calls may only run when the binary honours the fake printer;
    /// otherwise a regression could send a job to a real, connected LabelWriter.
    static func requireFakePrinter() throws {
        try #require(try run(["printers"]).out.contains("FAKE"), "binary ignores MACLABEL_FAKE_PRINTER; refusing to print")
    }

    @Test func noRollIsUsageError() throws {
        try Self.requireFakePrinter()
        let r = try Self.run(["print", "Test"])
        #expect(r.status == 64)
        #expect(r.err.contains("11354"))
    }

    @Test func dryRunDoesNotRememberRoll() throws {
        try Self.requireFakePrinter()
        let suite = "maclabel.test.\(UUID().uuidString)"
        let url = Self.tempURL("x.bin")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try Self.run(["print", "Test", "--roll", "11354", "--dry-run", url.path], suite: suite).status == 0)
        #expect(try Self.run(["print", "Test"], suite: suite).status == 64)
    }

    @Test func ambiguousRollListsCandidates() throws {
        try Self.requireFakePrinter()
        let r = try Self.run(["print", "Test", "--roll", "label"])
        #expect(r.status == 64)
        let catalog = MediaCatalog.bundled
        let candidates = catalog.search("label")
        #expect(candidates.count > 1)
        for roll in candidates.prefix(10) { #expect(r.err.contains(roll.id)) }
    }

    @Test func sameSizeRollsAreNotAmbiguous() throws {
        let url = Self.tempURL("x.bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let r = try Self.run(["print", "T", "--roll", "32x57", "--dry-run", url.path])
        #expect(r.status == 0, "\(r.err)")
        #expect(r.err.contains("11354"))
        #expect(r.err.contains("1933084"))
    }

    @Test func rememberedRollIsUsedWithoutRollOption() throws {
        let suite = "maclabel.test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = RollPreferences(defaults: defaults)
        prefs.setLastRollID("11354", forPrinterSerial: "SER1")
        prefs.setLastRollID("1933084", forPrinterSerial: nil)

        let withSerial = try RollResolver.resolve(query: nil, catalog: .bundled, preferences: prefs, serial: "SER1")
        #expect(withSerial.roll.id == "11354")
        let fallback = try RollResolver.resolve(query: nil, catalog: .bundled, preferences: prefs, serial: nil)
        #expect(fallback.roll.id == "1933084")
        #expect(throws: (any Error).self) {
            try RollResolver.resolve(query: nil, catalog: .bundled, preferences: prefs, serial: "OTHER")
        }

        // End to end through the binary: the (fake) printer's remembered roll is used.
        prefs.setLastRollID("11354", forPrinterSerial: "FAKE")
        let url = Self.tempURL("x.bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let r = try Self.run(["print", "T", "--dry-run", url.path], suite: suite)
        #expect(r.status == 0, "\(r.err)")
    }

    /// `printers` and `status` see the fake printer, so these paths run without hardware.
    @Test func fakePrinterIsDiscovered() throws {
        let printers = try Self.run(["printers"])
        #expect(printers.status == 0, "\(printers.err)")
        #expect(printers.out.contains("LabelWriter 450") && printers.out.contains("FAKE"))
        let status = try Self.run(["status"])
        #expect(status.status == 0, "\(status.err)")
        #expect(status.out.contains("LabelWriter 450"))
    }

    /// A real (non-dry) print goes to the fake printer's file. Only runs when the binary is a debug
    /// build that honours `MACLABEL_FAKE_PRINTER`; otherwise it stops before printing.
    @Test func printGoesToFakePrinterFile() throws {
        let fake = Self.tempURL("fake.bin")
        defer { try? FileManager.default.removeItem(at: fake) }
        let probe = try Self.run(["printers"], fakePrinter: fake)
        try #require(probe.out.contains("FAKE"), "binary ignores MACLABEL_FAKE_PRINTER; refusing to print")
        let r = try Self.run(["print", "Fake", "--roll", "11354"], fakePrinter: fake)
        #expect(r.status == 0, "\(r.err)")
        let bytes = [UInt8](try Data(contentsOf: fake))
        #expect(bytes.count > 156)
        #expect(bytes.suffix(2) == [0x1B, 0x45])
    }

    @Test func overflowWithoutForceExits65() throws {
        let url = Self.tempURL("x.bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let long = String(repeating: "Lorem ipsum dolor sit amet\\n", count: 40)
        let r = try Self.run(["print", long, "--roll", "11354", "--dry-run", url.path])
        #expect(r.status == 65)
        #expect(r.err.contains("passt nicht") || r.err.contains("does not fit"))
        let forced = try Self.run(["print", long, "--roll", "11354", "--force", "--dry-run", url.path])
        #expect(forced.status == 0)
    }

    @Test func invalidBarcodeValueExits64() throws {
        let url = Self.tempURL("x.bin")
        let r = try Self.run(["print", "12345", "--layout", "barcode", "--symbology", "ean13", "--roll", "11354", "--dry-run", url.path])
        #expect(r.status == 64)
    }

    @Test func csvWithoutRowsExits64() throws {
        let csv = Self.tempURL("rows.csv")
        let out = Self.tempURL("x.bin")
        try "name;ort\n".write(to: csv, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: csv) }
        let r = try Self.run(["print", "{name}", "--csv", csv.path, "--roll", "11354", "--dry-run", out.path])
        #expect(r.status == 64)
        #expect(r.err.contains("CSV"))
    }

    @Test func csvWindows1252AndCounter() throws {
        let csv = Self.tempURL("de.csv")
        let out = Self.tempURL("x.bin")
        defer { try? FileManager.default.removeItem(at: csv); try? FileManager.default.removeItem(at: out) }
        try "name;ort\nMüller;Köln\nSchön;Bonn\n".data(using: .windowsCP1252)!.write(to: csv)
        let r = try Self.run(["print", "{name} {n}", "--csv", csv.path, "--counter", "1", "--roll", "11354", "--dry-run", out.path])
        #expect(r.status == 0, "\(r.err)")
    }

    @Test func rotateOptionChangesJob() throws {
        func job(_ extra: [String]) throws -> [UInt8] {
            let url = Self.tempURL("rot.bin")
            defer { try? FileManager.default.removeItem(at: url) }
            let r = try Self.run(["print", "Regal 4", "--roll", "11354", "--dry-run", url.path] + extra)
            #expect(r.status == 0, "\(r.err)")
            return [UInt8](try Data(contentsOf: url))
        }
        let standard = try job([])
        #expect(try job(["--rotate", "upright"]) == standard) // 11354 reads upright by default
        let cw = try job(["--rotate", "cw"]), ccw = try job(["--rotate", "ccw"]), flipped = try job(["--rotate", "180"])
        #expect(cw != standard && ccw != standard && flipped != standard)
        #expect(cw != ccw)
        let bad = try Self.run(["print", "x", "--roll", "11354", "--rotate", "sideways", "--dry-run", Self.tempURL("x.bin").path])
        #expect(bad.status == 64)
    }
}
