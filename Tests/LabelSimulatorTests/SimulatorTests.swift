import Foundation
import LabelMedia
import LabelProtocol
import Testing
@testable import LabelSimulator

private let step300 = 25.4 / 300
private let step600 = 25.4 / 600

@Suite struct MechanicalModelTests {
    @Test func defaultsMatch11354() {
        let m = MechanicalModel()
        #expect(m.labelLengthMM == 31.75)
        #expect(m.gapMM == 4.5)
        #expect(m.senseHoleOffsetMM == 0)
        #expect(m.headToSensorMM == 0)
        #expect(m.headToTearBarMM == 12)
        #expect(abs(m.stepMM(.text) - step300) < 1e-12)
        #expect(abs(m.stepMM(.graphics) - step600) < 1e-12)
        #expect(abs(m.pitchMM - 36.25) < 1e-12)
    }

    @Test func modelFromCatalogRollUsesFeedDots() throws {
        let roll = try #require(MediaCatalog.bundled.roll(id: "11354"))
        let m = MechanicalModel(roll: roll)
        #expect(abs(m.labelLengthMM - 31.75) < 1e-9) // 375 dots, not the rounded 31.8 mm
        #expect(m.labelWidthMM == 57.1)
    }
}

@Suite struct ExactModelTests {
    func simulate(_ files: [String], hypothesis: ReverseFeedHypothesis = .exact, model: MechanicalModel = MechanicalModel()) throws -> SimulationResult {
        let sim = LW450Simulator(model: model, hypothesis: hypothesis)
        for file in files { try sim.run(try Fixtures.bytes(file), pauseBefore: 600, name: file) }
        return sim.result
    }

    @Test func test1MarginsMatchRaster() throws {
        let label = try #require(try simulate(["test1.bin"]).labels.first)
        // Ink rows 157...221 of 375 at 300 lpi.
        #expect(abs(try #require(label.topMarginMM) - 157 * step300) < 1e-6)
        #expect(abs(try #require(label.bottomMarginMM) - (31.75 - 222 * step300)) < 1e-6)
        #expect(abs(try #require(label.contentHeightMM) - 65 * step300) < 1e-6)
        #expect(abs(try #require(label.shiftMM)) < 1e-9)
        #expect(!label.clipped)
        #expect(label.physicalLabelIndex == 0)
    }

    @Test func step4QRHasEqualMargins() throws {
        let label = try #require(try simulate(["step4.bin"]).labels.first)
        #expect(abs(try #require(label.topMarginMM) - 3.6) <= 0.1)
        #expect(abs(try #require(label.bottomMarginMM) - 3.6) <= 0.1)
        #expect(!label.clipped)
    }

    @Test func rulerSecondLabelEndsAboutOneMillimetreAboveBottom() throws {
        let result = try simulate(["ruler_graphics_2.bin"])
        #expect(result.labels.count == 2)
        let second = result.labels[1]
        #expect(second.physicalLabelIndex == 1)
        #expect(abs(try #require(second.bottomMarginMM) - 1.1) < 0.05)
        #expect(abs(try #require(second.topMarginMM)) < 1e-6)
    }

    @Test func formFeedEndsAtTearBarAndNextJobReturnsToTopOfForm() throws {
        let result = try simulate(["test1.bin", "test1.bin"])
        #expect(result.labels.map(\.physicalLabelIndex) == [0, 1])
        #expect(abs(try #require(result.labels[1].shiftMM)) < 1e-9)
        #expect(abs(result.finalPositionMM - (2 * 36.25 + 12)) < 1e-9)
    }

    @Test func shortFormFeedAdvancesToNextTopOfForm() throws {
        let result = try simulate(["step7.bin"])
        #expect(result.labels.map(\.physicalLabelIndex) == [0, 1])
        #expect(result.labels.allSatisfy { abs($0.shiftMM ?? 99) < 1e-9 })
    }

    @Test func skipLinesUseCurrentLinePitch() throws {
        // ESC h, ESC f 1 10, one black line → top margin 10 lines at 300 lpi; same at 600 lpi.
        for (quality, step) in [(UInt8(0x68), step300), (0x69, step600)] {
            let job: [UInt8] = [0x1B, quality, 0x1B, 0x4C, 0x01, 0x77, 0x1B, 0x44, 0x01, 0x1B, 0x66, 0x01, 10, 0x16, 0xFF, 0x1B, 0x45]
            let sim = LW450Simulator()
            try sim.run(job)
            let label = try #require(sim.result.labels.first)
            #expect(abs(try #require(label.topMarginMM) - 10 * step) < 1e-9)
            #expect(abs(try #require(label.contentHeightMM) - step) < 1e-9)
        }
    }

    @Test func statusAndVersionAreAnswered() throws {
        let sim = LW450Simulator()
        try sim.run([0x1B, 0x41, 0x1B, 0x56])
        #expect(sim.result.responses == [[0x03], Array("1750111f0J".utf8)])
    }

    @Test func protocolErrorsPropagate() {
        let sim = LW450Simulator()
        #expect(throws: SimulatorError.self) { try sim.run([0x1B, 0x45, 0x00]) }
    }
}

@Suite struct HypothesisTests {
    /// Shift of the second job's label after `first`, with the given hypothesis.
    func secondShift(_ first: String, _ second: String, _ h: ReverseFeedHypothesis, pause: TimeInterval = 3) throws -> LabelMeasurement {
        let sim = LW450Simulator(hypothesis: h)
        try sim.run(try Fixtures.bytes(first), pauseBefore: 600)
        try sim.run(try Fixtures.bytes(second), pauseBefore: pause)
        return try #require(sim.result.labels.last)
    }

    @Test func currentModeReversesHalfInGraphicsMode() throws {
        let label = try secondShift("step4.bin", "step4.bin", .inLinesOfCurrentMode)
        #expect(abs(try #require(label.shiftMM) - 6) < 1e-6)
        #expect(label.clipped)
    }

    @Test func currentModeIsExactInTextMode() throws {
        let label = try secondShift("step4.bin", "test1.bin", .inLinesOfCurrentMode)
        #expect(abs(try #require(label.shiftMM)) < 1e-6)
    }

    @Test func modeAtFormFeedUsesModeWhenEscEWasExecuted() throws {
        // e_hE switches to ESC h before ESC E → full reverse.
        #expect(abs(try #require(try secondShift("e_hE.bin", "step4.bin", .inLinesOfModeAtFormFeed).shiftMM)) < 1e-6)
        #expect(abs(try #require(try secondShift("e.bin", "test1.bin", .inLinesOfModeAtFormFeed).shiftMM) - 6) < 1e-6)
    }

    @Test func linesCountedAtFormFeedExecutedInCurrentMode() throws {
        // FF in text (N = tear/step300), executed at 600 lpi → half reverse.
        #expect(abs(try #require(try secondShift("e_hE.bin", "step4.bin", .linesAtFormFeedInCurrentMode).shiftMM) - 6) < 1e-6)
        // FF in graphics (N = tear/step600), executed at 600 lpi → exact.
        #expect(abs(try #require(try secondShift("e.bin", "step4.bin", .linesAtFormFeedInCurrentMode).shiftMM)) < 1e-6)
    }

    @Test func constantErrorShiftsDown() throws {
        let label = try secondShift("step4.bin", "step4.bin", .constantError(mm: 1.5))
        #expect(abs(try #require(label.shiftMM) - 1.5) < 1e-6)
        #expect(!label.clipped)
        #expect(try secondShift("step4.bin", "step4.bin", .constantError(mm: 4)).clipped)
    }

    @Test func noReverseLeavesTearDistance() throws {
        #expect(abs(try #require(try secondShift("test1.bin", "test1.bin", .none).shiftMM) - 12) < 1e-6)
    }

    @Test func offsetCombinesWithBase() throws {
        let label = try secondShift("step4.bin", "step4.bin", .offset(mm: 0.5, .constantError(mm: 1)))
        #expect(abs(try #require(label.shiftMM) - 1.5) < 1e-6)
    }

    @Test func autoRetractDependsOnPause() throws {
        let h = ReverseFeedHypothesis.autoRetractAfter(seconds: 30, otherwise: .constantError(mm: 2))
        #expect(abs(try #require(try secondShift("step4.bin", "step4.bin", h, pause: 600).shiftMM)) < 1e-6)
        #expect(abs(try #require(try secondShift("step4.bin", "step4.bin", h, pause: 3).shiftMM) - 2) < 1e-6)
    }

    @Test func customHypothesisSeesContext() throws {
        let h = ReverseFeedHypothesis.custom(name: "poll") { ctx in
            ctx.transport == .poll ? ctx.tearMM - 3 : ctx.tearMM
        }
        let sim = LW450Simulator(hypothesis: h)
        try sim.run(try Fixtures.bytes("step4.bin"), pauseBefore: 600)
        try sim.run(try Fixtures.bytes("step4.bin"), pauseBefore: 600, transport: .poll)
        try sim.run(try Fixtures.bytes("step4.bin"), pauseBefore: 600, transport: .raw)
        let shifts = sim.result.labels.compactMap(\.shiftMM)
        #expect(shifts.count == 3)
        #expect(abs(shifts[1] - 3) < 1e-6)
        #expect(abs(shifts[2]) < 1e-6)
    }

    @Test(arguments: ["exact", "none", "current-mode", "mode-at-ff", "ff-lines-current-mode",
                      "constant:1.5", "auto-retract:30:current-mode", "offset:0.5:mode-at-ff"])
    func namesRoundTrip(name: String) throws {
        let h = try #require(ReverseFeedHypothesis(name: name))
        #expect(h.name == name)
    }

    @Test func unknownNameIsNil() {
        #expect(ReverseFeedHypothesis(name: "magic")?.name == nil)
    }
}

@Suite struct RenderingTests {
    @Test func stripShowsInkOnWhiteLabel() throws {
        let sim = LW450Simulator()
        try sim.run(try Fixtures.bytes("step4.bin"))
        let image = sim.result.renderStrip()
        let scale = StripRenderer.pixelsPerMM
        // Width covers the label width plus margins; height covers at least one label pitch.
        #expect(Double(image.width) >= 57.1 * scale)
        #expect(Double(image.height) >= 36.25 * scale)
        let pixels = try #require(StripRenderer.grayPixels(image))
        func gray(xMM: Double, yMM: Double) -> UInt8 {
            let x = Int(xMM * scale) + StripRenderer.marginPixels
            let y = Int(yMM * scale) + StripRenderer.marginPixels
            return pixels[y * image.width + x]
        }
        #expect(gray(xMM: 28, yMM: 1) > 240)            // white label margin
        #expect(gray(xMM: 28, yMM: 31.75 + 2) < 240)    // grey gap
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sim-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try StripRenderer.writePNG(image, to: url)
        #expect(Array(try Data(contentsOf: url).prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    @Test func graphicsRowsAreHalfAsTallAsTextRows() throws {
        func blackRows(_ quality: UInt8) throws -> Int {
            let job: [UInt8] = [0x1B, quality, 0x1B, 0x4C, 0x01, 0x77, 0x1B, 0x44, 0x54, 0x16] + [UInt8](repeating: 0xFF, count: 84) + [0x1B, 0x45]
            let sim = LW450Simulator()
            try sim.run(job)
            let image = sim.result.renderStrip()
            let pixels = try #require(StripRenderer.grayPixels(image))
            let x = StripRenderer.marginPixels + Int(20 * StripRenderer.pixelsPerMM)
            return (0..<image.height).filter { pixels[$0 * image.width + x] < 50 }.count
        }
        #expect(try blackRows(0x68) == 2 * (try blackRows(0x69)))
    }

    @Test func inkOnBackingIsDrawnAsLostInk() throws {
        // A full black line 33 mm below top of form lies in the gap (label is 31.75 mm).
        let job: [UInt8] = [0x1B, 0x68, 0x1B, 0x4C, 0x01, 0x77, 0x1B, 0x44, 0x54, 0x1B, 0x66, 0x01, 0xFF, 0x1B, 0x66, 0x01, 135,
                            0x16] + [UInt8](repeating: 0xFF, count: 84) + [0x1B, 0x45]
        let sim = LW450Simulator()
        try sim.run(job)
        #expect(sim.result.labels.first?.clipped == true)
        let image = sim.result.renderStrip()
        let pixels = try #require(StripRenderer.grayPixels(image))
        let x = StripRenderer.marginPixels + Int(20 * StripRenderer.pixelsPerMM)
        let y = StripRenderer.marginPixels + Int((390 * 25.4 / 300 + 0.04) * StripRenderer.pixelsPerMM)
        let v = pixels[y * image.width + x]
        #expect(v > 100 && v < 180, "lost ink should be faint grey, got \(v)")
    }
}
