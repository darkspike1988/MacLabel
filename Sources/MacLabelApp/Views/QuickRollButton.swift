import LabelMedia
import SwiftUI

/// A large button for one common roll in `FirstRunRollSheet`: size first, then article number and name.
struct QuickRollButton: View {
    let articleNumber: String
    let roll: LabelRoll
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(roll.sizeText)
                    .font(.headline)
                Text(articleNumber)
                    .monospacedDigit()
                Text(roll.displayName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .controlSize(.large)
        .accessibilityLabel(Text(verbatim: "\(articleNumber), \(roll.displayName), \(roll.sizeText)"))
    }
}
