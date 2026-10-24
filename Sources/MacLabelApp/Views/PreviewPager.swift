import SwiftUI

/// "2 of 10" with previous/next buttons for a series. Only the rendered pages can be shown.
struct PreviewPager: View {
    @Binding var page: Int
    let renderedPages: Int
    let totalLabels: Int

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                Button(L10n.string("Previous label"), systemImage: "chevron.left", action: previous)
                    .disabled(shown <= 0)
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Text(L10n.string("\(shown + 1) of \(totalLabels)"))
                    .monospacedDigit()
                    .accessibilityLabel(L10n.string("Label \(shown + 1) of \(totalLabels)"))
                Button(L10n.string("Next label"), systemImage: "chevron.right", action: next)
                    .disabled(shown >= renderedPages - 1)
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)

            if totalLabels > renderedPages {
                Text(L10n.string("The preview shows the first \(renderedPages) labels."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// `page` may briefly point past the pages of a page-1-only result.
    private var shown: Int { min(max(page, 0), max(renderedPages - 1, 0)) }

    private func previous() { page = max(shown - 1, 0) }
    private func next() { page = min(shown + 1, renderedPages - 1) }
}
