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
    private var renderTask: Task<PreviewResult, Never>?

    public init(debounce: Duration = .milliseconds(100), maxPages: Int = 50) {
        self.debounce = debounce
        self.maxPages = maxPages
    }

    /// Returns `nil` when a newer call superseded this one or the caller's task was cancelled.
    /// A newer call also cancels the render in flight.
    /// `onFirstPage` receives page 1 alone (with the full `totalLabels`) before the capped series is rendered.
    public func update(
        document: LabelDocument, roll: LabelRoll?, model: PrinterModel,
        onFirstPage: (@MainActor (PreviewResult) -> Void)? = nil
    ) async -> PreviewResult? {
        generation += 1
        let mine = generation
        renderTask?.cancel()
        if debounce > .zero {
            try? await Task.sleep(for: debounce)
        }
        guard mine == generation, !Task.isCancelled else { return nil }

        if let onFirstPage, maxPages > 1 {
            let first = await run(document: document, roll: roll, model: model, limit: 1)
            guard mine == generation, !Task.isCancelled else { return nil }
            if first.error == nil { onFirstPage(first) }
        }
        let result = await run(document: document, roll: roll, model: model, limit: maxPages)
        return mine == generation && !Task.isCancelled ? result : nil
    }

    private func run(document: LabelDocument, roll: LabelRoll?, model: PrinterModel, limit: Int) async -> PreviewResult {
        let task = Task.detached(priority: .userInitiated) {
            Self.render(document: document, roll: roll, model: model, limit: limit)
        }
        renderTask = task
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    // All labels of a series share the template layout, so the automatic quality/density chosen over the
    // capped set equals the one chosen for the full series (Ruling A12).
    private nonisolated static func render(document: LabelDocument, roll: LabelRoll?, model: PrinterModel, limit: Int) -> PreviewResult {
        let total = (try? document.labelCount()) ?? 0
        func failure(_ message: String) -> PreviewResult {
            PreviewResult(pages: [], totalLabels: total, overflowIndices: [], error: message)
        }
        guard let roll else {
            return failure(String(localized: "No roll selected.", bundle: L10n.bundle))
        }
        do {
            let request = PrintRequest(
                contents: try document.contents(limit: limit), roll: roll, model: model,
                density: document.density, quality: document.quality, rotation: document.rotation,
                continuousLengthMM: document.continuousLengthMM, allowOverflow: true
            )
            let pages = try PrintService.render(request)
            let overflow = pages.indices.filter { pages[$0].overflow }
            return PreviewResult(pages: pages, totalLabels: total, overflowIndices: overflow, error: nil)
        } catch {
            return failure(error.localizedDescription)
        }
    }
}
