import SwiftUI

/// The bottom bar: copies, print progress or result, and the prominent Print button.
/// ⌘P belongs to File › Print…, which takes the same path (`AppModel.requestPrint`); Return never prints.
/// Overflow asks "Print anyway?" first.
struct PrintBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let blocked = model.printBlockReason
        HStack(spacing: 16) {
            CopiesControl()

            PrintStatusView(blockReason: blocked)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(L10n.string("Print"), systemImage: "printer", action: model.requestPrint)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canRequestPrint)
                .help(blocked ?? L10n.string("Print the label (⌘P)"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .alert(L10n.string("Print anyway?"), isPresented: $model.confirmsOverflowPrint) {
            Button(L10n.string("Print")) { start(allowOverflow: true) }
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("The content doesn't fit on the label and will be cut off."))
        }
    }

    private func start(allowOverflow: Bool) {
        Task { await model.print(allowOverflow: allowOverflow) }
    }
}
