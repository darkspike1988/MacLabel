import Foundation
import Testing

/// `maclabel simulate` never touches a printer: it only reads .bin files.
@Suite struct SimulateCommandTests {
    static func fixture(_ name: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("LabelSimulatorTests/Fixtures/\(name)").path
    }

    @Test func simulatePrintsTableAndWritesPNG() throws {
        let png = CLISmokeTests.tempURL("strip.png")
        defer { try? FileManager.default.removeItem(at: png) }
        let r = try CLISmokeTests.run(["simulate", Self.fixture("test1.bin"), Self.fixture("step4.bin"),
                                       "--pause", "600", "--pause", "3", "--out", png.path])
        #expect(r.status == 0, "\(r.err)")
        #expect(r.out.contains("13.29"))   // test1 top margin
        #expect(r.out.contains("3.60"))    // step4 QR margin
        #expect(r.out.contains("exact"))
        #expect(Array(try Data(contentsOf: png).prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    @Test func hypothesisAndTearChangeShift() throws {
        let png = CLISmokeTests.tempURL("strip.png")
        defer { try? FileManager.default.removeItem(at: png) }
        let r = try CLISmokeTests.run(["simulate", Self.fixture("step4.bin"), Self.fixture("step4.bin"),
                                       "--hypothesis", "current-mode", "--tear", "10", "--gap", "5", "--out", png.path])
        #expect(r.status == 0, "\(r.err)")
        #expect(r.out.contains("+5.00"))
        #expect(r.out.contains("yes")) // clipped
    }

    @Test func unknownHypothesisIsUsageError() throws {
        let r = try CLISmokeTests.run(["simulate", Self.fixture("test1.bin"), "--hypothesis", "magic",
                                       "--out", CLISmokeTests.tempURL("x.png").path])
        #expect(r.status == 64)
        #expect(r.err.contains("magic"))
    }

    @Test func protocolErrorIsReported() throws {
        let bin = CLISmokeTests.tempURL("bad.bin")
        defer { try? FileManager.default.removeItem(at: bin) }
        try Data([0x1B, 0x45, 0x42]).write(to: bin)
        let r = try CLISmokeTests.run(["simulate", bin.path, "--out", CLISmokeTests.tempURL("x.png").path])
        #expect(r.status == 65)
        #expect(r.err.contains("offset 2"))
    }
}
