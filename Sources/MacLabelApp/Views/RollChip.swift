import LabelMedia
import SwiftUI

/// The toolbar chip "11354 · 57 × 32 mm" (⌘L) that opens the roll search in a popover.
struct RollChip: View {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool

    var body: some View {
        let title = model.roll.map(RollPicker.chipText) ?? L10n.string("Choose Roll …")
        Button(action: toggle) {
            Label(title, systemImage: "tag")
                .labelStyle(.titleAndIcon)
                .monospacedDigit()
        }
        .keyboardShortcut("l", modifiers: .command)
        .help(L10n.string("Choose the loaded roll (⌘L)"))
        .accessibilityLabel(model.roll.map { L10n.string("Roll: \($0.id), \($0.sizeText)") } ?? L10n.string("No roll selected."))
        .accessibilityHint(L10n.string("Opens the roll search."))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            RollPicker(
                current: model.roll,
                headDots: model.selectedPrinter?.model.headDots ?? FirstRunRollSheet.defaultHeadDots,
                onSelect: choose
            )
            .frame(width: 360, height: 420)
        }
    }

    private func toggle() { isPresented.toggle() }

    private func choose(_ roll: LabelRoll) {
        model.chooseRoll(roll)
        isPresented = false
    }
}
