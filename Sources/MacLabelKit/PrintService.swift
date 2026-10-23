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
    public var errorDescription: String? {
        switch self {
        case .nothingToPrint:
            String(localized: "There is nothing to print.", bundle: .module)
        case .unsupportedPrinter(let name):
            String(localized: "The printer \(name) is not supported.", bundle: .module)
        case .rollTooWide(_, let needs, let has):
            String(localized: "This roll is too wide for the print head (\(needs) instead of \(has) dots).", bundle: .module)
        case .invalidLength:
            String(localized: "The label length is not valid (10 to 1000 mm).", bundle: .module)
        case .overflow(let index):
            String(localized: "Content does not fit on label \(index + 1).", bundle: .module)
        case .printerNotReady(let status):
            String(localized: "The printer is not ready: \(Self.reason(status)).", bundle: .module)
        case .interrupted(let printed, let total, let status):
            String(localized: "Printing interrupted after \(printed) of \(total) labels: \(Self.reason(status)).", bundle: .module)
        case .render(let error):
            switch error {
            case .emptyContent: String(localized: "A label has no content.", bundle: .module)
            case .barcode: String(localized: "The barcode value is not valid for this barcode type.", bundle: .module)
            }
        case .transport(let error):
            switch error {
            case .busy: String(localized: "The printer is currently in use by another app.", bundle: .module)
            case .notFound: String(localized: "No printer found.", bundle: .module)
            case .timeout: String(localized: "The printer did not respond in time.", bundle: .module)
            case .disconnected: String(localized: "The printer was disconnected.", bundle: .module)
            case .ioFailure(let code): String(localized: "USB communication error (\(Int(code))).", bundle: .module)
            }
        }
    }

    static func reason(_ status: LWStatus) -> String {
        if status.isPaperOut { return String(localized: "out of paper", bundle: .module) }
        if status.isJammed { return String(localized: "paper jam", bundle: .module) }
        if status.hasError { return String(localized: "printer error", bundle: .module) }
        return String(localized: "not ready", bundle: .module)
    }
}

public struct PreparedJob: Sendable {
    public let renders: [RenderResult]
    public let bytes: [UInt8]
}

public enum PrintService {
    public static func prepare(_ request: PrintRequest) throws -> PreparedJob {
        let (renders, job) = try build(request)
        return PreparedJob(renders: renders, bytes: LWClassicEncoder.encode(job))
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
            labels: renders.map(\.bitmap), labelLengthLines: geometry.lengthLines,
            quality: quality, density: density, twinRoll: request.twinRoll
        )
        return (renders, job)
    }

    public static func print(
        _ request: PrintRequest,
        using transport: any PrinterTransport,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws {
        let (_, job) = try build(request)
        let total = job.labels.count
        var headerSent = false
        do {
            let before = try await transport.status()
            guard before.canPrint else { throw PrintError.printerNotReady(before) }

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
        } catch {
            if headerSent {
                // Discard partial data; resync + ESC @ never moves paper.
                try? await transport.write(LWClassicEncoder.resync + [0x1B, 0x40])
            }
            if let error = error as? TransportError { throw PrintError.transport(error) }
            throw error
        }
    }
}
