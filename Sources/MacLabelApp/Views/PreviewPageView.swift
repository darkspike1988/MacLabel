import LabelMedia
import SwiftUI

/// The shown page of a rendered series: the paper, the overflow warning or the roll's size,
/// and paging for series. `page` may point past a page-1-only result and is clamped here.
struct PreviewPageView: View {
    @Environment(AppModel.self) private var model
    let result: PreviewResult
    let roll: LabelRoll
    @Binding var page: Int

    var body: some View {
        let index = min(max(page, 0), result.pages.count - 1)
        let shown = result.pages[index]
        LabelPaper(
            image: shown.preview,
            roll: roll,
            feed: FeedDirection(rotation: model.document.effectiveRotation(for: roll)),
            overflow: shown.overflow,
            spokenText: model.document.spokenText(at: index)
        )

        if shown.overflow {
            Label(L10n.string("Doesn't fit on the label"), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else {
            Text(verbatim: "\(roll.sizeText) · \(roll.displayName)")
                .foregroundStyle(.secondary)
        }

        if result.totalLabels > 1 {
            PreviewPager(page: $page, renderedPages: result.pages.count, totalLabels: result.totalLabels)
        }
    }
}
