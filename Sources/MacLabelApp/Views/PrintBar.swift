import SwiftUI

/// The bottom bar: copies, print progress or result, and the prominent Print button (⌘P).
/// Overflow asks "Print anyway?" first.
struct PrintBar: View {
    @Environment(AppModel.self) private var model
    @State private var confirmOverflow = false

    var body: some View {
        let blocked = model.printBlockReason
        HStack(spacing: 16) {
            CopiesControl()

            PrintStatusView(blockReason: blocked)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(L10n.string("Print"), systemImage: "printer", action: printTapped)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("p", modifiers: .command)
                .disabled(blocked != nil || model.isPrinting || model.previewResult?.error != nil)
                .help(blocked ?? L10n.string("Print the label (⌘P)"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .alert(L10n.string("Print anyway?"), isPresented: $confirmOverflow) {
            Button(L10n.string("Print")) { start(allowOverflow: true) }
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("The content doesn't fit on the label and will be cut off."))
        }
    }

    private func printTapped() {
        if model.previewResult?.overflowIndices.isEmpty == false {
            confirmOverflow = true
        } else {
            start(allowOverflow: false)
        }
    }

    private func start(allowOverflow: Bool) {
        Task { await model.print(allowOverflow: allowOverflow) }
    }
}
