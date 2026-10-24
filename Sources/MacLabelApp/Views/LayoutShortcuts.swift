import SwiftUI

/// ⌘1 … ⌘5 switch the layout. Segmented pickers cannot carry per-segment shortcuts, so these
/// invisible buttons provide them; VoiceOver uses the visible picker instead.
struct LayoutShortcuts: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            ForEach(LabelLayout.allCases) { layout in
                Button(layout.title) { model.document.layout = layout }
                    .keyboardShortcut(layout.shortcut, modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}
