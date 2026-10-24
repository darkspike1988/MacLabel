import LabelMedia
import SwiftUI

/// One roll in `RollPicker`: id, name, material and the checkmark for the roll in use.
struct RollRow: View {
    let roll: LabelRoll
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(roll.id), \(roll.displayName), \(roll.sizeText)"))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
