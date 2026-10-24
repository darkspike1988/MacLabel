import Foundation
import LabelMedia
import LabelProtocol
import LabelRender
import MacLabelKit

public struct PreviewResult: Sendable {
    public let pages: [RenderResult]
    public let totalLabels: Int
    public let overflowIndices: [Int]
    public let error: String?

    public init(pages: [RenderResult], totalLabels: Int, overflowIndices: [Int], error: String?) {
        self.pages = pages
        self.totalLabels = totalLabels
        self.overflowIndices = overflowIndices
        self.error = error
    }
}

/// Renders the live preview: debounced, off the main actor, capped at `maxPages`,
/// and with the same automatic density/quality/rotation as printing (via `PrintService`).
@MainActor
public final class PreviewEngine {
    private let debounce: Duration
    private let maxPages: Int
    private var generation = 0

    public init(debounce: Duration = .milliseconds(100), maxPages: Int = 50) {
        self.debounce = debounce
        self.maxPages = maxPages
    }

    /// Returns `nil` when a newer call superseded this one.
    public func update(document: LabelDocument, roll: LabelRoll?, model: PrinterModel) async -> PreviewResult? {
        generation += 1
        let mine = generation
        if debounce > .zero {
            try? await Task.sleep(for: debounce)
        }
        guard mine == generation, !Task.isCancelled else { return nil }

        let limit = maxPages
        let result = await Task.detached(priority: .userInitiated) {
            Self.render(document: document, roll: roll, model: model, limit: limit)
        }.value
        return mine == generation ? result : nil
    }

    private nonisolated static func render(document: LabelDocument, roll: LabelRoll?, model: PrinterModel, limit: Int) -> PreviewResult {
        func failure(_ message: String, total: Int = 0) -> PreviewResult {
            PreviewResult(pages: [], totalLabels: total, overflowIndices: [], error: message)
        }
        guard let roll else {
            return failure(String(localized: "No roll selected.", bundle: L10n.bundle))
        }
        do {
            let total = try document.labelCount()
            let request = PrintRequest(
                contents: try document.contents(limit: limit), roll: roll, model: model,
                density: document.density, quality: document.quality, rotation: document.rotation,
                continuousLengthMM: document.continuousLengthMM, allowOverflow: true
            )
            let pages = try PrintService.prepare(request).renders
            let overflow = pages.indices.filter { pages[$0].overflow }
            return PreviewResult(pages: pages, totalLabels: total, overflowIndices: overflow, error: nil)
        } catch {
            return failure(error.localizedDescription)
        }
    }
}
