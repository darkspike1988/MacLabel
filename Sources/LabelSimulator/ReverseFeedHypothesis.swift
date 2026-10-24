import Foundation
import LabelProtocol

/// How a job reached the printer (status traffic may or may not influence motion).
public enum Transport: String, Sendable, CaseIterable {
    /// MacLabel CLI: `ESC A` before the job and after each label.
    case cli
    /// Bytes only, no status requests.
    case raw
    /// Bytes plus `ESC A` every 250 ms during the job.
    case poll
}

/// Everything a hypothesis may use to decide the reverse feed before the next job.
public struct ReverseContext: Sendable {
    /// Forward feed done after `ESC E` (print line → tear bar), mm.
    public let tearMM: Double
    /// Quality (lpi) active when `ESC E` executed.
    public let qualityAtFormFeed: PrintQuality
    /// Quality active when the reverse is executed (first motion of the next job).
    public let currentQuality: PrintQuality
    /// Seconds between the end of the previous job and this job.
    public let pauseBefore: TimeInterval
    public let transport: Transport?
    public let model: MechanicalModel

    /// A distance expressed in lines of `quality` (not rounded: the tear distance is itself an estimate).
    public func lines(_ distanceMM: Double, in quality: PrintQuality) -> Double {
        distanceMM / model.stepMM(quality)
    }
}

/// Hypotheses for the reverse feed the LW450 performs after an `ESC E` before printing again.
/// The simulator applies the result at the first motion of the next job. Positive shift = print lower.
public indirect enum ReverseFeedHypothesis: Sendable {
    /// Reverse feed returns exactly to top of form.
    case exact
    /// No reverse at all (the label starts `tear` mm too low).
    case none
    /// Reverse = tear distance counted in 300-lpi lines, executed with the step of the CURRENT mode
    /// (only half the distance in 600-lpi mode).
    case inLinesOfCurrentMode
    /// Reverse = tear distance counted in 300-lpi lines, executed with the step of the mode active at `ESC E`.
    case inLinesOfModeAtFormFeed
    /// Reverse = tear distance counted in lines of the mode at `ESC E`, executed with the step of the current mode.
    case linesAtFormFeedInCurrentMode
    /// Reverse falls `mm` short of exact (positive = label printed lower).
    case constantError(mm: Double)
    /// The printer retracts by itself (exactly) after `seconds` idle; a job that arrives earlier gets `otherwise`.
    case autoRetractAfter(seconds: TimeInterval, otherwise: ReverseFeedHypothesis)
    /// `base` plus a constant shift of `mm` (positive = lower).
    case offset(mm: Double, ReverseFeedHypothesis)
    /// Free-form hypothesis: returns the reverse distance in mm.
    case custom(name: String, reverse: @Sendable (ReverseContext) -> Double)

    /// Reverse distance in mm for this context.
    public func reverseMM(_ c: ReverseContext) -> Double {
        switch self {
        case .exact:
            return c.tearMM
        case .none:
            return 0
        case .inLinesOfCurrentMode:
            return c.lines(c.tearMM, in: .text) * c.model.stepMM(c.currentQuality)
        case .inLinesOfModeAtFormFeed:
            return c.lines(c.tearMM, in: .text) * c.model.stepMM(c.qualityAtFormFeed)
        case .linesAtFormFeedInCurrentMode:
            return c.lines(c.tearMM, in: c.qualityAtFormFeed) * c.model.stepMM(c.currentQuality)
        case .constantError(let mm):
            return c.tearMM - mm
        case let .autoRetractAfter(seconds, otherwise):
            return c.pauseBefore >= seconds ? c.tearMM : otherwise.reverseMM(c)
        case let .offset(mm, base):
            return base.reverseMM(c) - mm
        case let .custom(_, reverse):
            return reverse(c)
        }
    }

    /// Short name, parseable by `init?(name:)` (except `.custom`).
    public var name: String {
        switch self {
        case .exact: "exact"
        case .none: "none"
        case .inLinesOfCurrentMode: "current-mode"
        case .inLinesOfModeAtFormFeed: "mode-at-ff"
        case .linesAtFormFeedInCurrentMode: "ff-lines-current-mode"
        case .constantError(let mm): "constant:\(Self.format(mm))"
        case let .autoRetractAfter(s, otherwise): "auto-retract:\(Self.format(s)):\(otherwise.name)"
        case let .offset(mm, base): "offset:\(Self.format(mm)):\(base.name)"
        case .custom(let name, _): name
        }
    }

    /// Parses `exact`, `none`, `current-mode`, `mode-at-ff`, `ff-lines-current-mode`, `constant:<mm>`,
    /// `auto-retract:<s>:<hypothesis>`, `offset:<mm>:<hypothesis>`.
    public init?(name: String) {
        let parts = name.split(separator: ":", maxSplits: 2).map(String.init)
        switch parts[0] {
        case "exact" where parts.count == 1: self = .exact
        case "none" where parts.count == 1: self = .none
        case "current-mode" where parts.count == 1: self = .inLinesOfCurrentMode
        case "mode-at-ff" where parts.count == 1: self = .inLinesOfModeAtFormFeed
        case "ff-lines-current-mode" where parts.count == 1: self = .linesAtFormFeedInCurrentMode
        case "constant" where parts.count == 2:
            guard let mm = Double(parts[1]) else { return nil }
            self = .constantError(mm: mm)
        case "auto-retract" where parts.count == 3:
            guard let s = Double(parts[1]), let base = ReverseFeedHypothesis(name: parts[2]) else { return nil }
            self = .autoRetractAfter(seconds: s, otherwise: base)
        case "offset" where parts.count == 3:
            guard let mm = Double(parts[1]), let base = ReverseFeedHypothesis(name: parts[2]) else { return nil }
            self = .offset(mm: mm, base)
        default:
            return nil
        }
    }

    /// The fixed hypotheses (without parameter sweeps).
    public static let standard: [ReverseFeedHypothesis] = [
        .exact, .none, .inLinesOfCurrentMode, .inLinesOfModeAtFormFeed, .linesAtFormFeedInCurrentMode,
    ]

    static func format(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }
}
