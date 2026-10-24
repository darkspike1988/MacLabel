import Testing
import LabelProtocol
@testable import LabelSimulator

/// The encoder's real output, replayed through the simulator: consecutive graphics jobs
/// (QR/barcode) must stay put under every reverse-feed hypothesis that fits the owner's
/// real prints (see docs/simulator.md, docs/research/lw450-protocol.md §13).
@Suite struct EncoderPositioningTests {
    static let hypotheses: [ReverseFeedHypothesis] = [
        .exact, .inLinesOfCurrentMode, .inLinesOfModeAtFormFeed, .linesAtFormFeedInCurrentMode,
        ReverseFeedHypothesis(name: "auto-retract:60:current-mode")!,
        ReverseFeedHypothesis(name: "auto-retract:60:mode-at-ff")!,
    ]

    static func qrLikeBitmap() -> MonochromeBitmap {
        var b = MonochromeBitmap(width: 672, height: 750)
        for y in 85..<665 { for x in 40..<330 { b[x, y] = true } }
        return b
    }

    @Test(arguments: hypotheses.indices)
    func consecutiveGraphicsJobsStayCentered(_ i: Int) throws {
        let hypothesis = Self.hypotheses[i]
        let job = LWClassicJob(labels: [Self.qrLikeBitmap()], labelLengthLines: 750, quality: .graphics, density: .normal)
        let bytes = LWClassicEncoder.encode(job)
        for tear in [8.0, 10.0, 12.0, 14.0] {
            let sim = LW450Simulator(model: MechanicalModel(headToTearBarMM: tear), hypothesis: hypothesis)
            for (n, pause) in [600.0, 0, 1.7].enumerated() {
                let labels = try sim.run(bytes, pauseBefore: pause, name: "job\(n)")
                let m = try #require(labels.first)
                #expect(!m.clipped, "\(hypothesis.name) tear \(tear) job \(n) clipped")
                #expect(abs(m.shiftMM ?? 99) < 0.1, "\(hypothesis.name) tear \(tear) job \(n) shift \(m.shiftMM ?? .nan)")
            }
        }
    }

    @Test(arguments: hypotheses.indices)
    func twoLabelGraphicsJobBothCentered(_ i: Int) throws {
        let job = LWClassicJob(labels: [Self.qrLikeBitmap(), Self.qrLikeBitmap()], labelLengthLines: 750, quality: .graphics, density: .normal)
        let sim = LW450Simulator(model: MechanicalModel(headToTearBarMM: 10), hypothesis: Self.hypotheses[i])
        _ = try sim.run(LWClassicEncoder.encode(job), pauseBefore: 600)
        let labels = try sim.run(LWClassicEncoder.encode(job), pauseBefore: 0)
        #expect(labels.count == 2)
        for m in labels { #expect(abs(m.shiftMM ?? 99) < 0.1 && !m.clipped) }
    }
}
