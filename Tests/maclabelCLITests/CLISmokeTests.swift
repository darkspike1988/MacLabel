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

    static func run(_ args: [String], suite: String = "maclabel.test.\(UUID().uuidString)") throws -> Result {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["MACLABEL_DEFAULTS_SUITE"] = suite
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

    @Test func noRollIsUsageError() throws {
        let r = try Self.run(["print", "Test"])
        #expect(r.status == 64)
        #expect(r.err.contains("11354"))
    }

    @Test func dryRunDoesNotRememberRoll() throws {
        let suite = "maclabel.test.\(UUID().uuidString)"
        let url = Self.tempURL("x.bin")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try Self.run(["print", "Test", "--roll", "11354", "--dry-run", url.path], suite: suite).status == 0)
        #expect(try Self.run(["print", "Test"], suite: suite).status == 64)
    }

    @Test func ambiguousRollListsCandidates() throws {
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

        // End to end through the binary (dry run without printer uses the "default" key).
        let url = Self.tempURL("x.bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let r = try Self.run(["print", "T", "--dry-run", url.path], suite: suite)
        if USBPrinterDiscovery.printers().isEmpty { #expect(r.status == 0, "\(r.err)") }
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
