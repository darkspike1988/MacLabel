import SwiftUI

/// Coloured dot plus text for the printer state ("LabelWriter 450 · ready").
/// The text carries the meaning, so the colour is never the only signal.
struct PrinterStatusIndicator: View {
    let state: PrinterState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.tint)
                .frame(width: 8, height: 8)
            Text(state.statusText)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("Printer status"))
        .accessibilityValue(state.statusText)
    }
}
