import ArgumentParser
import Foundation
import LabelSimulator

/// Replays .bin jobs in the LW450 simulator. Never opens a printer.
struct SimulateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "simulate",
        abstract: "Simulate LabelWriter 450 jobs (.bin) and render the printed label strip.",
        discussion: "Hypotheses: exact, none, current-mode, mode-at-ff, ff-lines-current-mode, constant:<mm>, auto-retract:<s>:<hypothesis>, offset:<mm>:<hypothesis>. See docs/simulator.md."
    )

    @Argument(help: "Job files as written by `print --dry-run x.bin`, in print order.")
    var files: [String]

    @Option(help: "Seconds before each job (repeat per file; missing values are 0).")
    var pause: [Double] = []

    @Option(help: "Reverse-feed hypothesis.")
    var hypothesis: String = "exact"

    @Option(help: "Gap between labels in mm.")
    var gap: Double = 4.5

    @Option(help: "Print line to tear bar in mm.")
    var tear: Double = 12

    @Option(help: "PNG of the simulated strip.")
    var out: String

    func run() throws {
        guard let h = ReverseFeedHypothesis(name: hypothesis) else {
            throw fail("Unknown hypothesis \(hypothesis).", code: Exit.usage)
        }
        let model = MechanicalModel(gapMM: gap, headToTearBarMM: tear)
        let sim = LW450Simulator(model: model, hypothesis: h)
        for (i, file) in files.enumerated() {
            let bytes: [UInt8]
            do { bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: file))) } catch {
                throw fail("\(file): \(error.localizedDescription)", code: Exit.usage)
            }
            do {
                try sim.run(bytes, pauseBefore: i < pause.count ? pause[i] : 0, name: (file as NSString).lastPathComponent)
            } catch let e as SimulatorError {
                throw fail("\(file): \(e.description)", code: Exit.overflow)
            }
        }
        let result = sim.result
        func mm(_ v: Double?, sign: Bool = false) -> String {
            guard let v else { return "–" }
            return String(format: sign ? "%+.2f" : "%.2f", v)
        }
        let header = ["Job", "Label", "Phys.", "Top mm", "Bottom mm", "Content mm", "Shift mm", "Clipped"]
        let rows = result.labels.map {
            [$0.jobName, "\($0.pageIndex + 1)", "\($0.physicalLabelIndex + 1)", mm($0.topMarginMM), mm($0.bottomMarginMM),
             mm($0.contentHeightMM), mm($0.shiftMM, sign: true), $0.clipped ? "yes" : "no"]
        }
        print("Hypothesis \(h.name), gap \(gap) mm, tear \(tear) mm")
        print(formatTable([header] + rows))
        for w in result.warnings { writeStderr(w) }
        do {
            try StripRenderer.writePNG(result.renderStrip(), to: URL(fileURLWithPath: out))
        } catch {
            throw fail("\(out): \(error.localizedDescription)", code: Exit.internalError)
        }
    }
}
