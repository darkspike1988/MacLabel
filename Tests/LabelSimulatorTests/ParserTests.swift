import LabelProtocol
import Testing
@testable import LabelSimulator

@Suite struct ParserTests {
    let esc: UInt8 = 0x1B

    @Test func resyncRunIsOneCommandAndEndsBeforeFollowingCommand() throws {
        let bytes = [UInt8](repeating: esc, count: 156) + [esc, 0x51, 0x00, 0x00]
        let commands = try LWClassicParser.parse(bytes).map(\.command)
        #expect(commands == [.resync(count: 156), .lineTab(0)])
    }

    @Test func resyncAtEndOfStreamIsAccepted() throws {
        let commands = try LWClassicParser.parse([UInt8](repeating: esc, count: 90)).map(\.command)
        #expect(commands == [.resync(count: 90)])
    }

    @Test func shortEscapeRunThrows() {
        #expect(throws: SimulatorError.self) {
            try LWClassicParser.parse([esc, esc, esc, 0x47])
        }
    }

    @Test(arguments: [
        ([UInt8]([0x1B, 0x40]), LWCommand.reset),
        ([0x1B, 0x2A], .restoreDefaults),
        ([0x1B, 0x41], .statusRequest),
        ([0x1B, 0x56], .versionRequest),
        ([0x1B, 0x42, 0x05], .dotTab(5)),
        ([0x1B, 0x44, 0x20], .bytesPerLine(32)),
        ([0x1B, 0x51, 0x01, 0x02], .lineTab(0x0102)),
        ([0x1B, 0x4C, 0x01, 0x77], .labelLength(375)),
        ([0x1B, 0x45], .formFeed),
        ([0x1B, 0x47], .shortFormFeed),
        ([0x1B, 0x66, 0x01, 0x55], .skipLines(85)),
        ([0x1B, 0x68], .quality(.text)),
        ([0x1B, 0x69], .quality(.graphics)),
        ([0x1B, 0x63], .density(.light)),
        ([0x1B, 0x64], .density(.medium)),
        ([0x1B, 0x65], .density(.normal)),
        ([0x1B, 0x67], .density(.dark)),
        ([0x1B, 0x71, 0x31], .rollSelect(.left)),
    ])
    func singleCommand(bytes: [UInt8], expected: LWCommand) throws {
        let parsed = try LWClassicParser.parse(bytes)
        #expect(parsed.map(\.command) == [expected])
        #expect(parsed.first?.offset == 0)
    }

    @Test func synLineHasBytesPerLineData() throws {
        let bytes: [UInt8] = [esc, 0x44, 0x02, 0x16, 0xF0, 0x0F, esc, 0x45]
        let commands = try LWClassicParser.parse(bytes).map(\.command)
        #expect(commands == [.bytesPerLine(2), .rasterLine([0xF0, 0x0F], compressed: false), .formFeed])
    }

    @Test func etbLineIsDecodedToBits() throws {
        // BPL 2 = 16 pixels: 4 white, 8 black, 4 white.
        let bytes: [UInt8] = [esc, 0x44, 0x02, 0x17, 0x03, 0x87, 0x03]
        let commands = try LWClassicParser.parse(bytes).map(\.command)
        #expect(commands == [.bytesPerLine(2), .rasterLine([0x0F, 0xF0], compressed: true)])
    }

    @Test func etbWithTooManyPixelsThrows() {
        // 4 + 8 + 5 = 17 pixels for BPL 2.
        let bytes: [UInt8] = [esc, 0x44, 0x02, 0x17, 0x03, 0x87, 0x04]
        #expect {
            try LWClassicParser.parse(bytes)
        } throws: { error in
            guard case SimulatorError.rlePixelCount(offset: 3, expected: 16, actual: 17) = error else { return false }
            return true
        }
    }

    @Test func truncatedEtbThrows() {
        #expect(throws: SimulatorError.self) {
            try LWClassicParser.parse([esc, 0x44, 0x02, 0x17, 0x03])
        }
    }

    @Test func truncatedSynThrows() {
        #expect(throws: SimulatorError.self) {
            try LWClassicParser.parse([esc, 0x44, 0x02, 0x16, 0x00])
        }
    }

    @Test func unknownByteThrowsWithOffset() {
        #expect {
            try LWClassicParser.parse([esc, 0x45, 0x42])
        } throws: { error in
            guard case SimulatorError.unknownByte(offset: 2, byte: 0x42) = error else { return false }
            return true
        }
    }

    @Test func unknownEscapeThrows() {
        #expect(throws: SimulatorError.self) { try LWClassicParser.parse([esc, 0x7E]) }
    }

    @Test(arguments: [
        [UInt8]([0x1B, 0x42, 84]),          // dot tab out of range
        [0x1B, 0x44, 0],                     // BPL 0
        [0x1B, 0x44, 85],                    // BPL > 84
        [0x1B, 0x42, 80, 0x1B, 0x44, 10, 0x16] + [UInt8](repeating: 0, count: 10), // dot tab + BPL > 84
        [0x1B, 0x66, 0x02, 0x10],            // ESC f needs 1
        [0x1B, 0x4C, 0x00, 0x00],            // label length 0
        [0x1B, 0x71, 0x35],                  // bad roll
        [0x1B, 0x79],                        // ESC y: SE450 only
        [0x1B, 0x7A],                        // ESC z: SE450 only
        [0x1B, 0x4C, 0x01],                  // truncated
    ])
    func invalidCommandThrows(bytes: [UInt8]) {
        #expect(throws: SimulatorError.self) { try LWClassicParser.parse(bytes) }
    }

    @Test func resetRestoresBytesPerLine() throws {
        // After ESC @ BPL is 84 again, so a SYN consumes 84 bytes.
        let bytes: [UInt8] = [esc, 0x44, 0x01, esc, 0x40, 0x16] + [UInt8](repeating: 0, count: 84) + [esc, 0x45]
        let commands = try LWClassicParser.parse(bytes).map(\.command)
        #expect(commands.count == 4)
        #expect(commands.last == .formFeed)
    }

    @Test func allFixturesParse() throws {
        let names = ["test1.bin", "step4.bin", "step4_noskip.bin", "step4_allsyn.bin", "step5.bin", "step6.bin",
                     "step7.bin", "ruler_graphics_2.bin", "ruler_text_1.bin", "fix4.bin", "e.bin", "e_L.bin",
                     "e_hE.bin", "q.bin", "q_L.bin", "q_hE.bin", "ref.bin", "ts_mod.bin"]
        for name in names {
            let commands = try LWClassicParser.parse(try Fixtures.bytes(name)).map(\.command)
            #expect(commands.first == .resync(count: 156), "\(name)")
            #expect(commands.last == .formFeed, "\(name)")
        }
    }

    @Test func encoderOutputRoundTrips() throws {
        var bitmap = MonochromeBitmap(width: 672, height: 10)
        for x in 100..<300 { bitmap[x, 4] = true }
        bitmap[0, 9] = true
        let job = LWClassicJob(labels: [bitmap, bitmap], labelLengthLines: 375, quality: .text, density: .normal)
        let commands = try LWClassicParser.parse(LWClassicEncoder.encode(job)).map(\.command)
        let lines = commands.compactMap { cmd -> [UInt8]? in
            if case .rasterLine(let bits, _) = cmd { return bits }
            return nil
        }
        #expect(lines.count == 4)
        #expect(lines[0] == Array(bitmap.row(4)))
        #expect(lines[1] == Array(bitmap.row(9)))
    }
}
