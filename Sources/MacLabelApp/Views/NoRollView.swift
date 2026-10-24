import SwiftUI

/// Shown instead of the preview until a roll is chosen; says whether a printer is missing too.
struct NoRollView: View {
    let hasPrinter: Bool
    let chooseRoll: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(
                hasPrinter ? L10n.string("No Roll Chosen Yet") : L10n.string("No LabelWriter Connected"),
                systemImage: hasPrinter ? "questionmark.square.dashed" : "printer"
            )
        } description: {
            Text(hasPrinter
                ? L10n.string("Choose the roll that is loaded in the printer.")
                : L10n.string("Connect a DYMO LabelWriter. You can already choose a roll and design the label."))
        } actions: {
            Button(L10n.string("Choose Roll …"), action: chooseRoll)
        }
    }
}
