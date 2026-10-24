import Foundation
import Testing
@testable import LabelSimulator

@Suite struct ObservationConstraintTests {
    static let parseCases: [(String, [ObservationConstraint])] = [
        ("ok (Text mittig, Feinversatz nicht beurteilbar)", [ObservationConstraint]()),
        ("unklar: 'QR abgeschnitten unten oder sehr knapp bei fast allen'", []),
        ("keine Aussage", []),
        ("vermutlich ok (nur Fix 2 bemängelt)", []),
        ("'wie vorher, keine Veränderung'", []),
        ("Ziffern unten abgeschnitten", [.clipped]),
        ("gut (nicht abgeschnitten)", [.ok]),
        ("abgeschnitten", [.clipped]),
        ("deutlich zu tief, nicht abgeschnitten", [.tooLow]),
        ("Ziffern unten, nicht abgeschnitten", [.notClipped]),
        ("passt nicht genau", [.notCentered]),
        ("nicht mittig", [.notCentered]),
        ("'passt'; Foto IMG_5319: Rand oben ~4,4 mm, unten ~1,9 mm (Soll 3,6/3,6) → ~+0,8 mm", [.shift(0.8)]),
        ("Foto IMG_5319: Rand oben ~5,7 mm, unten ~0 → ~+2 mm", [.shift(2)]),
        ("Foto IMG_5319: Striche beginnen ~6,3 mm (Soll 1,5) → ~+4,8 mm, Ziffern abgeschnitten", [.clipped, .shift(4.8)]),
        ("Foto IMG_5318: beide Lineale vollständig, letzter Strich ~0,9 mm vor Unterkante (Soll 1,1 mm)", [.notClipped, .shift(0.2)]),
    ]

    @Test(arguments: parseCases)
    func parse(text: String, expected: [ObservationConstraint]) {
        #expect(ObservationConstraint.parse(text).constraints == expected)
    }

    @Test func labelPrefixSelectsLabel() {
        #expect(ObservationConstraint.parse("Label 2 Position ok").label == 2)
        #expect(ObservationConstraint.parse("Label 2 Position ok").constraints == [.ok])
        #expect(ObservationConstraint.parse("abgeschnitten").label == nil)
    }

    static let satisfactionCases: [(ObservationConstraint, Double, Bool, Bool)] = [
        (.ok, 0.3, false, true),
        (.ok, 0.6, false, false),
        (.ok, 0.1, true, false),
        (.clipped, 0, true, true),
        (.notClipped, 0, true, false),
        (.tooLow, 1.2, false, true),
        (.tooLow, 1.2, true, false),
        (.notCentered, -0.6, false, true),
        (.shift(2), 2.6, false, true),
        (.shift(2), 2.8, false, false),
    ]

    @Test(arguments: satisfactionCases)
    func satisfaction(c: ObservationConstraint, shift: Double, clipped: Bool, expected: Bool) {
        #expect(c.isSatisfied(shiftMM: shift, clipped: clipped) == expected)
    }
}

@Suite struct ObservationHarnessTests {
    static func log() throws -> ObservationLog {
        try ObservationLog.decode(Data(contentsOf: Fixtures.directory.appendingPathComponent("observations.json")))
    }

    @Test func logDecodesWithLongPause() throws {
        let log = try Self.log()
        #expect(log.jobs.count == 27)
        #expect(log.jobs[0].pauseBefore == 600)
        #expect(log.jobs[2].pauseBefore == 3)
        #expect(log.jobs[5].file == nil)
        #expect(log.jobs[0].transport == .cli)
    }

    @Test func replayProducesOneRowPerObservedLabel() throws {
        let rows = try ObservationHarness.replay(try Self.log(), hypothesis: .exact, loader: Fixtures.bytes)
        #expect(rows.count == 31) // step6, step7, step8, ruler have 2 labels
        #expect(rows.allSatisfy { ($0.shiftMM ?? 0).magnitude < 1e-6 })
    }

    @Test func bestHypothesesRanksSweep() throws {
        let ranked = try ObservationHarness.bestHypotheses(
            try Self.log(), hypotheses: [.exact, .constantError(mm: 2)], gaps: [4, 5], tears: [12], loader: Fixtures.bytes)
        #expect(ranked.count == 4)
        #expect(ranked.first!.score >= ranked.last!.score)
        #expect(ranked.allSatisfy { $0.total > 0 && $0.satisfied <= $0.total })
    }

    /// Fitting harness: replays observations.json for every hypothesis and reports, never asserts which is right.
    /// Set SIM_REPORT_PATH to also write the report to a file.
    @Test func observationsReport() throws {
        let log = try Self.log()
        var text = ""
        for h in ObservationHarness.reportHypotheses {
            text += "\n### \(h.name)\n\n"
            text += ObservationHarness.table(try ObservationHarness.replay(log, hypothesis: h, loader: Fixtures.bytes))
        }
        let ranked = try ObservationHarness.bestHypotheses(
            log, hypotheses: ObservationHarness.reportHypotheses,
            gaps: [3, 4, 5, 6], tears: [8, 10, 12, 14, 16], loader: Fixtures.bytes)
        text += "\n### Ranking (gap × tear sweep, top 25)\n\n" + ObservationHarness.rankingTable(Array(ranked.prefix(25)))
        text += "\n### Best combination per hypothesis\n\n" + ObservationHarness.rankingTable(ObservationHarness.bestPerHypothesis(ranked))
        print(text)
        if let path = ProcessInfo.processInfo.environment["SIM_REPORT_PATH"] {
            try text.write(toFile: path, atomically: true, encoding: .utf8)
        }
        #expect(!ranked.isEmpty)
    }
}
