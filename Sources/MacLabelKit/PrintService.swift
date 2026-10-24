import Foundation
import LabelMedia
import LabelProtocol
import LabelRender
import LabelTransport

public struct PrintRequest: Sendable {
    public var contents: [LabelContent]
    public var roll: LabelRoll
    public var model: PrinterModel
    /// `nil` = automatic (`.dark` for durable media, otherwise `.normal`).
    public var density: PrintDensity?
    /// `nil` = automatic (`.graphics` if any content prefers it, otherwise `.text`).
    public var quality: PrintQuality?
    public var rotation: ReadingRotation?
    public var twinRoll: TwinRoll?
    public var continuousLengthMM: Double?
    public var allowOverflow: Bool = false

    public init(
        contents: [LabelContent], roll: LabelRoll, model: PrinterModel,
        density: PrintDensity? = nil, quality: PrintQuality? = nil, rotation: ReadingRotation? = nil,
        twinRoll: TwinRoll? = nil, continuousLengthMM: Double? = nil, allowOverflow: Bool = false
    ) {
        self.contents = contents
        self.roll = roll
        self.model = model
        self.density = density
        self.quality = quality
        self.rotation = rotation
        self.twinRoll = twinRoll
        self.continuousLengthMM = continuousLengthMM
        self.allowOverflow = allowOverflow
    }
}

public enum PrintError: Error, Equatable {
    case nothingToPrint
    case unsupportedPrinter(String)
    case rollTooWide(rollID: String, needs: Int, has: Int)
    case invalidLength
    case overflow(labelIndex: Int)
    case printerNotReady(LWStatus)
    case interrupted(printed: Int, total: Int, status: LWStatus)
    case render(RenderError)
    case transport(TransportError)
}

extension PrintError: LocalizedError {
    public var errorDescription: String? { text(bundle: L10n.bundle) }

    func text(bundle: Bundle) -> String {
        switch self {
        case .nothingToPrint:
            String(localized: "There is nothing to print.", bundle: bundle)
        case .unsupportedPrinter(let name):
            String(localized: "The printer \(name) is not supported.", bundle: bundle)
        case .rollTooWide(_, let needs, let has):
            String(localized: "This roll is too wide for the print head (\(needs) instead of \(has) dots).", bundle: bundle)
        case .invalidLength:
            String(localized: "The label length is not valid (10 to 1000 mm).", bundle: bundle)
        case .overflow(let index):
            String(localized: "Content does not fit on label \(index + 1).", bundle: bundle)
        case .printerNotReady(let status):
            String(localized: "The printer is not ready: \(Self.reason(status, bundle: bundle)).", bundle: bundle)
        case .interrupted(let printed, let total, let status):
            String(localized: "Printing interrupted after \(printed) of \(total) labels: \(Self.reason(status, bundle: bundle)).", bundle: bundle)
        case .render(let error):
            switch error {
            case .emptyContent: String(localized: "A label has no content.", bundle: bundle)
            case .barcode: String(localized: "The barcode value is not valid for this barcode type.", bundle: bundle)
            }
        case .transport(let error):
            switch error {
            case .busy: String(localized: "The printer is currently in use by another app.", bundle: bundle)
            case .notFound: String(localized: "No printer found.", bundle: bundle)
            case .timeout: String(localized: "The printer did not respond in time.", bundle: bundle)
            case .disconnected: String(localized: "The printer was disconnected.", bundle: bundle)
            case .ioFailure(let code): String(localized: "USB communication error (\(Int(code))).", bundle: bundle)
            }
        }
    }

    /// Why the printer cannot print, as a short phrase ("out of paper"), in the user's language.
    public static func reason(_ status: LWStatus) -> String { reason(status, bundle: L10n.bundle) }

    static func reason(_ status: LWStatus, bundle: Bundle) -> String {
        if status.isPaperOut { return String(localized: "out of paper", bundle: bundle) }
        if status.isJammed { return String(localized: "paper jam", bundle: bundle) }
        if status.hasError { return String(localized: "printer error", bundle: bundle) }
        return String(localized: "not ready", bundle: bundle)
    }
}

public struct PreparedJob: Sendable {
    public let renders: [RenderResult]
    public let bytes: [UInt8]
}

/// A validated, rendered job that can be sent without rendering again.
public struct RenderedJob: Sendable {
    let job: LWClassicJob
    let needsTopOfForm: Bool
    /// The number of labels in the job.
    public var labelCount: Int { job.labels.count }
}

public enum PrintService {
    public static func prepare(_ request: PrintRequest) throws -> PreparedJob {
        let (renders, job) = try build(request)
        return PreparedJob(renders: renders, bytes: LWClassicEncoder.encode(job))
    }

    /// Renders without encoding printer bytes. Cooperatively cancellable: throws `CancellationError`
    /// between labels when the calling task is cancelled.
    public static func render(_ request: PrintRequest) throws -> [RenderResult] {
        try build(request).0
    }

    /// Validates and renders `request` without touching a device, so content errors (overflow,
    /// invalid barcode, …) surface before a printer is opened. Cooperatively cancellable.
    public static func renderJob(_ request: PrintRequest) throws -> RenderedJob {
        let (_, job) = try build(request)
        return RenderedJob(job: job, needsTopOfForm: request.roll.kind == .dieCut)
    }

    private static func build(_ request: PrintRequest) throws -> ([RenderResult], LWClassicJob) {
        guard !request.contents.isEmpty else { throw PrintError.nothingToPrint }
        let model = request.model, roll = request.roll
        guard model.family == .lwClassic else { throw PrintError.unsupportedPrinter(model.name) }
        guard roll.minHeadDots <= model.headDots else {
            throw PrintError.rollTooWide(rollID: roll.id, needs: roll.minHeadDots, has: model.headDots)
        }
        if roll.kind == .continuous, let mm = request.continuousLengthMM, !(10...1000).contains(mm) {
            throw PrintError.invalidLength
        }

        let quality = request.quality
            ?? (request.contents.contains { LabelRenderer.preferredQuality(for: $0, model: model) == .graphics } ? .graphics : .text)
        let density = request.density ?? (roll.material == "durable" ? .dark : .normal)
        let geometry = LabelGeometry(
            roll: roll, headDots: model.headDots, quality: quality,
            rotation: request.rotation, continuousLengthMM: request.continuousLengthMM
        )
        guard geometry.lengthLines > 0, geometry.lengthLines < 0x8000 else { throw PrintError.invalidLength }

        var renders: [RenderResult] = []
        for (index, content) in request.contents.enumerated() {
            try Task.checkCancellation()
            let result: RenderResult
            do {
                result = try LabelRenderer.render(content, geometry: geometry)
            } catch let error as RenderError {
                throw PrintError.render(error)
            }
            if result.overflow && !request.allowOverflow { throw PrintError.overflow(labelIndex: index) }
            renders.append(result)
        }
        let job = LWClassicJob(
            labels: renders.map(\.bitmap), labelLengthLines: roll.kind == .continuous ? nil : geometry.lengthLines,
            quality: quality, density: density, twinRoll: request.twinRoll
        )
        return (renders, job)
    }

    /// Renders and prints `request`. With `spacing`, waits for the `JobSpacing` pause first, unless
    /// `waitForSpacing` is `false` (the caller already waited, e.g. with the device closed), and records
    /// the form feed afterwards either way.
    public static func print(
        _ request: PrintRequest,
        using transport: any PrinterTransport,
        topOfFormTimeout: Duration = .seconds(10),
        pollInterval: Duration = .milliseconds(100),
        settleAfterTopOfForm: Duration = .seconds(1),
        spacing: JobSpacing? = nil,
        waitForSpacing: Bool = true,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws {
        try await print(
            try renderJob(request), using: transport, topOfFormTimeout: topOfFormTimeout, pollInterval: pollInterval,
            settleAfterTopOfForm: settleAfterTopOfForm, spacing: spacing, waitForSpacing: waitForSpacing, progress: progress
        )
    }

    /// Prints an already rendered job; see `print(_:using:…)` for `spacing` and `waitForSpacing`.
    public static func print(
        _ rendered: RenderedJob,
        using transport: any PrinterTransport,
        topOfFormTimeout: Duration = .seconds(10),
        pollInterval: Duration = .milliseconds(100),
        settleAfterTopOfForm: Duration = .seconds(1),
        spacing: JobSpacing? = nil,
        waitForSpacing: Bool = true,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws {
        let job = rendered.job
        let total = job.labels.count
        var headerSent = false
        if let spacing, waitForSpacing {
            let remaining = spacing.remainingPause()
            if remaining > .zero {
                debugLog("pause \(remaining) after previous form feed")
                try await Task.sleep(for: remaining)
            }
        }
        do {
            try await waitUntilReady(
                transport, needsTopOfForm: rendered.needsTopOfForm,
                timeout: topOfFormTimeout, pollInterval: pollInterval, settle: settleAfterTopOfForm
            )

            try await transport.write(LWClassicEncoder.jobHeader(job))
            headerSent = true
            for (index, bitmap) in job.labels.enumerated() {
                try Task.checkCancellation()
                try await transport.write(LWClassicEncoder.label(bitmap, lengthLines: job.labelLengthLines))
                let status = try await transport.status()
                progress?(index + 1, total)
                guard status.canPrint else {
                    throw PrintError.interrupted(printed: index + 1, total: total, status: status)
                }
                if index < total - 1 { try await transport.write(LWClassicEncoder.betweenLabels) }
            }
            try await transport.write(LWClassicEncoder.endOfJob)
            spacing?.clock.recordFormFeed(serial: spacing?.serial, at: Date())
        } catch {
            if headerSent {
                // Discard partial data; resync + ESC @ never moves paper. Unstructured task:
                // it must not inherit this task's cancellation, or the write would fail at once.
                await Task { try? await transport.write(LWClassicEncoder.resync + LWClassicEncoder.reset) }.value
            }
            if let error = error as? TransportError { throw PrintError.transport(error) }
            throw error
        }
    }

    /// Waits until the printer may take a new job. For die-cut labels that means the
    /// top-of-form bit is set: right after the previous job's form feed the LW450 reports
    /// 0x01 (ready, not at top of form) for about a second, and printing then would land
    /// too low on the label. DYMO's own language monitor waits the same way.
    /// If the printer was still moving (TOF not yet set), it also waits `settle` after TOF
    /// appears: the bit is raised when the sense hole passes, while the label is still being
    /// advanced to the tear bar. Set `MACLABEL_DEBUG=1` to log every poll to stderr.
    static func waitUntilReady(
        _ transport: any PrinterTransport, needsTopOfForm: Bool,
        timeout: Duration, pollInterval: Duration, settle: Duration
    ) async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let deadline = start + timeout
        var waited = false
        while true {
            let status = try await transport.status()
            debugLog(String(format: "+%.3fs status 0x%02X", (clock.now - start).seconds, status.raw))
            guard status.canPrint else { throw PrintError.printerNotReady(status) }
            if !needsTopOfForm || status.isTopOfForm {
                if waited {
                    debugLog("settle \(settle)")
                    try await Task.sleep(for: settle)
                }
                return
            }
            waited = true
            guard clock.now < deadline else { throw PrintError.printerNotReady(status) }
            try await Task.sleep(for: pollInterval)
        }
    }

    static func debugLog(_ message: @autoclosure () -> String) {
        guard ProcessInfo.processInfo.environment["MACLABEL_DEBUG"] == "1" else { return }
        FileHandle.standardError.write(Data("maclabel: \(message())\n".utf8))
    }
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
