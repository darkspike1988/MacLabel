import LabelMedia
import SwiftUI

/// One roll in `RollPicker`: id, name, material and the checkmark for the roll in use.
struct RollRow: View {
    let roll: LabelRoll
    let isCurrent: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(roll.id).bold()
                Text(roll.displayName)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let material = roll.materialText {
                Text(material)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if isCurrent {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(roll.spokenName(articleNumber: roll.id)))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
