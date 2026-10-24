import Foundation

/// A coarse statement of the owner about one printed label, as a checkable constraint.
/// Shift = printed position − intended position, positive = lower.
public enum ObservationConstraint: Sendable, Equatable, CustomStringConvertible {
    /// "ok/gut/passt": |shift| ≤ 0.5 mm and not clipped.
    case ok
    /// "abgeschnitten/cut".
    case clipped
    /// "nicht abgeschnitten/vollständig" without a stronger statement.
    case notClipped
    /// "(deutlich) zu tief": shift ≥ 1 mm and not clipped.
    case tooLow
    /// "nicht mittig/passt nicht": |shift| > 0.5 mm.
    case notCentered
    /// Photo measurement: shift within ±0.7 mm of the value.
    case shift(Double)

    public static let shiftTolerance = 0.7

    public func isSatisfied(shiftMM s: Double, clipped: Bool) -> Bool {
        switch self {
        case .ok: abs(s) <= 0.5 && !clipped
        case .clipped: clipped
        case .notClipped: !clipped
        case .tooLow: s >= 1 && !clipped
        case .notCentered: abs(s) > 0.5
        case .shift(let v): abs(s - v) <= Self.shiftTolerance
        }
    }

    public var description: String {
        switch self {
        case .ok: "ok"
        case .clipped: "clipped"
        case .notClipped: "not clipped"
        case .tooLow: "≥1 mm low"
        case .notCentered: "|shift|>0.5"
        case .shift(let v): String(format: "shift %+.1f±0.7", v)
        }
    }

    /// Constraints in one observed string, and the label (1-based) it names, if any.
    public static func parse(_ raw: String) -> (label: Int?, constraints: [ObservationConstraint]) {
        let text = raw.lowercased()
        var label: Int?
        if let m = text.firstMatch(of: /^label (\d+)/) { label = Int(m.1) }

        for ignore in ["keine aussage", "unklar", "nicht beurteilbar", "vermutlich"] where text.contains(ignore) {
            return (label, [])
        }

        var out: [ObservationConstraint] = []
        // Photo measurements: "→ ~+0,8 mm", or "letzter Strich ~a mm vor Unterkante (Soll b mm)" (shift = b − a).
        var measured: Double?
        if let m = text.firstMatch(of: /→\s*~?([+-]?\d+(?:[.,]\d+)?)\s*mm/) {
            measured = number(m.1)
        } else if let m = text.firstMatch(of: /~?(\d+(?:[.,]\d+)?)\s*mm vor unterkante \(soll (\d+(?:[.,]\d+)?)\s*mm\)/),
                  let a = number(m.1), let b = number(m.2) {
            measured = ((b - a) * 10).rounded() / 10
        }

        let notClipped = text.contains("nicht abgeschnitten") || text.contains("vollständig")
        let clipped = !notClipped && (text.contains("abgeschnitten") || text.contains(/\bcut\b/))
        let tooLow = text.contains("zu tief")
        let notCentered = text.contains("nicht mittig") || text.contains("passt nicht")
        let ok = !notCentered && text.contains(/\b(ok|gut|passt)\b/)

        if clipped { out.append(.clipped) }
        if tooLow {
            out.append(.tooLow)
        } else if notCentered {
            out.append(.notCentered)
        } else if ok && measured == nil {
            out.append(.ok)
        } else if notClipped {
            out.append(.notClipped)
        }
        if let measured { out.append(.shift(measured)) }
        return (label, out)
    }

    private static func number(_ s: Substring) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "."))
    }
}

/// observations.json: the owner's real print jobs in print order.
public struct ObservationLog: Sendable {
    public struct Job: Sendable {
        public let id: String
        public let file: String?
        /// Seconds; "long" = 600 s.
        public let pauseBefore: TimeInterval
        public let transport: Transport?
        public let labels: Int
        public let observed: [String]
    }

    public let jobs: [Job]
    public static let longPause: TimeInterval = 600

    public static func decode(_ data: Data) throws -> ObservationLog {
        struct RawJob: Decodable {
            let id: String
            let file: String?
            let pauseBefore: Pause
            let transport: String?
            let labels: Int
            let observed: [String]
        }
        struct Pause: Decodable {
            let seconds: TimeInterval
            init(from decoder: any Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let s = try? c.decode(String.self) {
                    guard s == "long" else {
                        throw DecodingError.dataCorruptedError(in: c, debugDescription: "pauseBefore \(s)")
                    }
                    seconds = ObservationLog.longPause
                } else {
                    seconds = try c.decode(Double.self)
                }
            }
        }
        struct File: Decodable { let jobs: [RawJob] }
        let file = try JSONDecoder().decode(File.self, from: data)
        return ObservationLog(jobs: file.jobs.map {
            Job(id: $0.id, file: $0.file, pauseBefore: $0.pauseBefore.seconds,
                transport: $0.transport.flatMap(Transport.init(rawValue:)), labels: $0.labels, observed: $0.observed)
        })
    }
}

/// Replays observations against the simulator and scores hypotheses. It reports; it does not decide.
public enum ObservationHarness {
    /// Stand-in for jobs whose bytes were not kept (`file: null`): one text-mode job per label.
    public static let placeholderFile = "test1.bin"

    public struct Row: Sendable {
        public let jobID: String
        public let file: String
        public let pauseBefore: TimeInterval
        public let transport: Transport?
        /// 1-based label within the observed job.
        public let label: Int
        public let observed: [String]
        public let constraints: [ObservationConstraint]
        public let measurement: LabelMeasurement

        public var shiftMM: Double? { measurement.shiftMM }

        /// Satisfied / total constraints for this label.
        public var hits: (satisfied: Int, total: Int) {
            guard let s = measurement.shiftMM else { return (0, constraints.count) }
            return (constraints.filter { $0.isSatisfied(shiftMM: s, clipped: measurement.clipped) }.count, constraints.count)
        }
    }

    public struct Score: Sendable {
        public let hypothesisName: String
        public let gapMM: Double
        public let tearMM: Double
        public let satisfied: Int
        public let total: Int
        /// RMS error over the photo measurements, mm.
        public let measurementRMS: Double
        public var score: Double { total == 0 ? 0 : Double(satisfied) / Double(total) }
    }

    /// Hypotheses shown in the report and swept in the ranking.
    public static let reportHypotheses: [ReverseFeedHypothesis] =
        ReverseFeedHypothesis.standard
        + [0.5, 1, 2, 3, 4, 5].map { .constantError(mm: $0) }
        + ([.none, .inLinesOfCurrentMode, .inLinesOfModeAtFormFeed, .linesAtFormFeedInCurrentMode,
            .constantError(mm: 2), .constantError(mm: 4)] as [ReverseFeedHypothesis])
            .map { .autoRetractAfter(seconds: 60, otherwise: $0) }

    public static func replay(
        _ log: ObservationLog, hypothesis: ReverseFeedHypothesis, model: MechanicalModel = MechanicalModel(),
        loader: (String) throws -> [UInt8]
    ) throws -> [Row] {
        try replay(log, hypothesis: hypothesis, model: model, jobs: try parseJobs(log, loader: loader))
    }

    /// Parses every file referenced by `log` once.
    public static func parseJobs(_ log: ObservationLog, loader: (String) throws -> [UInt8]) throws -> [String: [ParsedCommand]] {
        var cache: [String: [ParsedCommand]] = [:]
        for name in Set(log.jobs.map { $0.file ?? placeholderFile }) {
            cache[name] = try LWClassicParser.parse(try loader(name))
        }
        return cache
    }

    static func replay(
        _ log: ObservationLog, hypothesis: ReverseFeedHypothesis, model: MechanicalModel, jobs: [String: [ParsedCommand]]
    ) throws -> [Row] {
        let sim = LW450Simulator(model: model, hypothesis: hypothesis)
        var rows: [Row] = []
        for job in log.jobs {
            var measured: [LabelMeasurement] = []
            let commands = jobs[job.file ?? placeholderFile] ?? []
            if job.file != nil {
                measured = sim.run(parsed: commands, pauseBefore: job.pauseBefore, transport: job.transport, name: job.id)
            } else {
                for i in 0..<job.labels {
                    measured += sim.run(parsed: commands, pauseBefore: i == 0 ? job.pauseBefore : 0, transport: job.transport, name: job.id)
                }
            }
            let parsed = job.observed.map { ($0, ObservationConstraint.parse($0)) }
            for (i, m) in measured.enumerated() {
                let applicable = parsed.filter { $0.1.label == nil || $0.1.label == i + 1 }
                rows.append(Row(
                    jobID: job.id, file: job.file ?? "(\(placeholderFile))", pauseBefore: job.pauseBefore,
                    transport: job.transport, label: i + 1, observed: applicable.map(\.0),
                    constraints: applicable.flatMap(\.1.constraints), measurement: m
                ))
            }
        }
        return rows
    }

    public static func score(_ rows: [Row], hypothesisName: String, model: MechanicalModel) -> Score {
        var satisfied = 0, total = 0, sq = 0.0, n = 0
        for row in rows {
            let h = row.hits
            satisfied += h.satisfied
            total += h.total
            for case .shift(let v) in row.constraints {
                sq += pow((row.shiftMM ?? 99) - v, 2)
                n += 1
            }
        }
        return Score(hypothesisName: hypothesisName, gapMM: model.gapMM, tearMM: model.headToTearBarMM,
                     satisfied: satisfied, total: total, measurementRMS: n == 0 ? 0 : (sq / Double(n)).squareRoot())
    }

    /// Scores every hypothesis × gap × tear combination; best first (score, then measurement RMS).
    public static func bestHypotheses(
        _ log: ObservationLog, hypotheses: [ReverseFeedHypothesis],
        gaps: [Double] = [4.5], tears: [Double] = [12], base: MechanicalModel = MechanicalModel(),
        loader: (String) throws -> [UInt8]
    ) throws -> [Score] {
        let parsed = try parseJobs(log, loader: loader)
        var scores: [Score] = []
        for h in hypotheses {
            for gap in gaps {
                for tear in tears {
                    var model = base
                    model.gapMM = gap
                    model.headToTearBarMM = tear
                    let rows = try replay(log, hypothesis: h, model: model, jobs: parsed)
                    scores.append(score(rows, hypothesisName: h.name, model: model))
                }
            }
        }
        return scores.enumerated().sorted { a, b in
            if a.element.score != b.element.score { return a.element.score > b.element.score }
            if a.element.measurementRMS != b.element.measurementRMS { return a.element.measurementRMS < b.element.measurementRMS }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// The best-ranked entry for each hypothesis name, in ranking order.
    public static func bestPerHypothesis(_ ranked: [Score]) -> [Score] {
        var seen = Set<String>()
        return ranked.filter { seen.insert($0.hypothesisName).inserted }
    }

    // MARK: - Tables (Markdown)

    public static func table(_ rows: [Row]) -> String {
        var out = "| Job | Datei | Pause s | Transport | Label | Beobachtung | Shift mm | Clipped | Oben mm | Unten mm | Checks |\n"
        out += "|---|---|---|---|---|---|---|---|---|---|---|\n"
        for r in rows {
            let m = r.measurement
            let checks = r.constraints.isEmpty ? "–" : "\(r.hits.satisfied)/\(r.hits.total) (\(r.constraints.map(\.description).joined(separator: ", ")))"
            out += "| \(r.jobID) | \(r.file) | \(fmt(r.pauseBefore, 1)) | \(r.transport?.rawValue ?? "–") | \(r.label) | "
            out += "\(r.observed.joined(separator: " / ").replacingOccurrences(of: "|", with: "/")) | "
            out += "\(m.shiftMM.map { fmt($0, 2, sign: true) } ?? "–") | \(m.clipped ? "ja" : "nein") | "
            out += "\(m.topMarginMM.map { fmt($0, 2) } ?? "–") | \(m.bottomMarginMM.map { fmt($0, 2) } ?? "–") | \(checks) |\n"
        }
        return out
    }

    public static func rankingTable(_ scores: [Score]) -> String {
        var out = "| # | Hypothese | Gap mm | Tear mm | Treffer | Score | RMS Foto mm |\n|---|---|---|---|---|---|---|\n"
        for (i, s) in scores.enumerated() {
            out += "| \(i + 1) | \(s.hypothesisName) | \(fmt(s.gapMM, 1)) | \(fmt(s.tearMM, 1)) | \(s.satisfied)/\(s.total) | \(fmt(s.score, 2)) | \(fmt(s.measurementRMS, 2)) |\n"
        }
        return out
    }

    static func fmt(_ v: Double, _ digits: Int, sign: Bool = false) -> String {
        String(format: sign ? "%+.\(digits)f" : "%.\(digits)f", v)
    }
}
