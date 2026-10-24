import LabelMedia
import SwiftUI

/// The one sheet MacLabel shows: "Which roll is loaded?" for a printer without a remembered roll.
struct FirstRunRollSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let headDots = model.selectedPrinter?.model.headDots ?? Self.defaultHeadDots
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("Which roll is loaded?"))
                    .font(.title2)
                    .bold()
                Text(L10n.string("MacLabel remembers the roll for this printer. You can change it any time with ⌘L."))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(Self.quickChoices(catalog: .bundled, headDots: headDots)) { choice in
                    QuickRollButton(articleNumber: choice.id, roll: choice.roll) { choose(choice.roll) }
                }
            }

            GroupBox(L10n.string("Other roll")) {
                RollPicker(current: model.roll, headDots: headDots, onSelect: choose)
                    .frame(minHeight: 180)
            }

            HStack {
                Spacer()
                Button(L10n.string("Later"), action: later)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 540, height: 600)
    }

    private func choose(_ roll: LabelRoll) {
        model.chooseRoll(roll)
        dismiss()
    }

    private func later() {
        model.needsRollChoice = false
        dismiss()
    }

    nonisolated static let defaultHeadDots = 672

    /// A common roll under the article number people know it by.
    struct QuickChoice: Identifiable {
        /// The article number shown on the button.
        let id: String
        let roll: LabelRoll
    }

    /// The most common rolls that are in the catalog and fit the print head.
    nonisolated static func quickChoices(catalog: MediaCatalog, headDots: Int) -> [QuickChoice] {
        var seen = Set<String>()
        return ["11354", "99010", "99012", "11352", "99014", "S0904980"].compactMap { number in
            guard let roll = catalog.roll(id: number) ?? catalog.roll(sku: number),
                  roll.minHeadDots <= headDots, seen.insert(roll.id).inserted
            else { return nil }
            return QuickChoice(id: number, roll: roll)
        }
    }
}
