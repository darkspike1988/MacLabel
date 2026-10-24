import Foundation
import LabelProtocol

/// One raster line that put ink on the paper.
public struct PrintedRow: Sendable {
    /// Paper coordinate of the line's leading side, mm.
    public let positionMM: Double
    /// Line pitch (300 or 600 lpi), mm.
    public let heightMM: Double
    /// Index of the first dot (dot tab × 8).
    public let firstDot: Int
    /// Raster bytes (MSB = left dot, 1 = black).
    public let bits: [UInt8]
}

/// Measurement of one page (= one label in the byte stream) on the physical strip.
public struct LabelMeasurement: Sendable {
    public let jobIndex: Int
    public let jobName: String
    /// Page within the job (0-based; pages are separated by `ESC G`).
    public let pageIndex: Int
    /// Physical label the page landed on (nearest top of form at the page start).
    public let physicalLabelIndex: Int
    /// Paper coordinate where the page started (after any reverse feed).
    public let pageStartMM: Double
    /// Leading edge → first ink, mm (`nil` without ink).
    public let topMarginMM: Double?
    /// Last ink → trailing edge, mm.
    public let bottomMarginMM: Double?
    /// First ink → last ink, mm.
    public let contentHeightMM: Double?
    /// The top margin the stream intends: lines before the first ink line, starting at the leading edge.
    public let nominalTopMarginMM: Double?
    /// `topMarginMM − nominalTopMarginMM` (positive = printed lower than intended).
    public var shiftMM: Double? {
        guard let t = topMarginMM, let n = nominalTopMarginMM else { return nil }
        return t - n
    }
    /// Ink outside the label (on the backing paper / in the gap, or on a neighbouring label).
    public let clipped: Bool
    public let inkRows: Int
}

/// Record of one fed job.
public struct JobRecord: Sendable {
    public let name: String
    public let pauseBefore: TimeInterval
    public let transport: Transport?
    public let startMM: Double
    public let endMM: Double
    /// Reverse feed applied at the start of this job (mm), `nil` if none was pending.
    public let reverseMM: Double?
}

public struct SimulationResult: Sendable {
    public let model: MechanicalModel
    public let hypothesisName: String
    public var labels: [LabelMeasurement] = []
    public var rows: [PrintedRow] = []
    public var jobs: [JobRecord] = []
    /// Replies to `ESC A` / `ESC V`, in order.
    public var responses: [[UInt8]] = []
    /// Non-fatal remarks (e.g. non-zero line tab, continuous length).
    public var warnings: [String] = []
    /// Paper coordinate under the print line after the last job.
    public var finalPositionMM: Double = 0
}

/// Simulates a LabelWriter 450 executing LW-Classic byte streams on die-cut labels.
///
/// Exact: command parsing, line pitch per mode, `ESC f`, `ESC G` (to the next top of form),
/// `ESC E` (next top of form, then `headToTearBarMM`). Hypothesised: the reverse feed before the
/// next job (`ReverseFeedHypothesis`) and the mechanical constants (`MechanicalModel`).
public final class LW450Simulator {
    public let model: MechanicalModel
    public let hypothesis: ReverseFeedHypothesis
    public private(set) var result: SimulationResult
    /// Firmware answer to `ESC V` (as read from the owner's device).
    public var versionString = "1750111f0J"

    // Printer state that persists across jobs.
    private var x: Double
    private var quality: PrintQuality = .text
    private var pending: (tearMM: Double, quality: PrintQuality)?

    public init(model: MechanicalModel = MechanicalModel(), hypothesis: ReverseFeedHypothesis = .exact) {
        self.model = model
        self.hypothesis = hypothesis
        self.x = model.topOfFormMM(label: 0)
        self.result = SimulationResult(model: model, hypothesisName: hypothesis.name)
        result.finalPositionMM = x
    }

    private struct Page {
        var startMM: Double?
        var nominalAdvanceMM = 0.0
        var firstInkNominal: Double?
        var inkStart: Double?
        var inkEnd: Double?
        var inkRows = 0
        var rowRange: Range<Int>
        var hasMotion: Bool { startMM != nil }
    }

    /// Executes one job. `pauseBefore`: seconds since the end of the previous job.
    @discardableResult
    public func run(_ bytes: [UInt8], pauseBefore: TimeInterval = 0, transport: Transport? = nil, name: String? = nil) throws -> [LabelMeasurement] {
        run(parsed: try LWClassicParser.parse(bytes), pauseBefore: pauseBefore, transport: transport, name: name)
    }

    /// Executes an already parsed job (lets callers parse a fixture once and replay it often).
    @discardableResult
    public func run(parsed commands: [ParsedCommand], pauseBefore: TimeInterval = 0, transport: Transport? = nil, name: String? = nil) -> [LabelMeasurement] {
        let jobIndex = result.jobs.count
        let jobName = name ?? "job\(jobIndex + 1)"
        let jobStart = x
        let firstLabel = result.labels.count
        var reverseApplied: Double?
        var page = Page(rowRange: result.rows.count..<result.rows.count)
        var pageIndex = 0
        var dotTab = 0

        func applyPendingReverse() {
            if let p = pending {
                let ctx = ReverseContext(tearMM: p.tearMM, qualityAtFormFeed: p.quality, currentQuality: quality,
                                         pauseBefore: pauseBefore, transport: transport, model: model)
                let r = hypothesis.reverseMM(ctx)
                x -= r
                reverseApplied = r
                pending = nil
            }
        }

        func beginMotion() {
            applyPendingReverse()
            if page.startMM == nil { page.startMM = x }
        }

        func closePage() {
            defer {
                pageIndex += 1
                page = Page(rowRange: result.rows.count..<result.rows.count)
            }
            guard let start = page.startMM else { return }
            let k = model.labelIndex(forPageStart: start)
            let lead = model.leadingEdgeMM(label: k)
            let trail = lead + model.labelLengthMM
            var top: Double?, bottom: Double?, height: Double?
            var clipped = false
            if let a = page.inkStart, let b = page.inkEnd {
                top = a - lead
                bottom = trail - b
                height = b - a
                clipped = a < lead - 1e-6 || b > trail + 1e-6
            }
            result.labels.append(LabelMeasurement(
                jobIndex: jobIndex, jobName: jobName, pageIndex: pageIndex, physicalLabelIndex: k,
                pageStartMM: start, topMarginMM: top, bottomMarginMM: bottom, contentHeightMM: height,
                nominalTopMarginMM: page.firstInkNominal, clipped: clipped, inkRows: page.inkRows
            ))
        }

        for parsed in commands {
            switch parsed.command {
            case .resync:
                break
            case .reset, .restoreDefaults:
                quality = .text
                dotTab = 0
            case .statusRequest:
                // Ready; top of form while idle at a hole or while the reverse is still pending.
                result.responses.append([pending != nil || model.isTopOfForm(x) ? 0x03 : 0x01])
            case .versionRequest:
                result.responses.append(Array(versionString.utf8))
            case .dotTab(let n):
                dotTab = n
            case .bytesPerLine:
                break
            case .lineTab(let n):
                if n != 0 { result.warnings.append("\(jobName): ESC Q \(n) (line tab) is not modelled") }
            case .labelLength(let n):
                if n >= 0x8000 { result.warnings.append("\(jobName): continuous length (ESC L \(n)) – strip still drawn as die-cut") }
            case .quality(let q):
                quality = q
            case .density, .rollSelect:
                break
            case .skipLines(let n):
                beginMotion()
                let d = Double(n) * model.stepMM(quality)
                x += d
                page.nominalAdvanceMM += d
            case .rasterLine(let bits, _):
                beginMotion()
                let h = model.stepMM(quality)
                if bits.contains(where: { $0 != 0 }) {
                    result.rows.append(PrintedRow(positionMM: x, heightMM: h, firstDot: dotTab * 8, bits: bits))
                    if page.inkStart == nil {
                        page.inkStart = x
                        page.firstInkNominal = page.nominalAdvanceMM
                    }
                    page.inkEnd = x + h
                    page.inkRows += 1
                }
                x += h
                page.nominalAdvanceMM += h
            case .shortFormFeed:
                applyPendingReverse()
                closePage()
                x = model.nextTopOfFormMM(after: x)
            case .formFeed:
                applyPendingReverse()
                closePage()
                x = model.nextTopOfFormMM(after: x) + model.headToTearBarMM
                pending = (model.headToTearBarMM, quality)
            }
        }
        // A job without ESC E/G still leaves its page measured.
        if page.hasMotion { closePage() }
        result.jobs.append(JobRecord(name: jobName, pauseBefore: pauseBefore, transport: transport,
                                     startMM: jobStart, endMM: x, reverseMM: reverseApplied))
        result.finalPositionMM = x
        return Array(result.labels[firstLabel...])
    }
}
