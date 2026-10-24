import SwiftUI

/// What the print bar says between copies and the Print button: why printing is not possible,
/// the positioning pause, progress with Cancel, or the outcome of the last print.
struct PrintStatusView: View {
    @Environment(AppModel.self) private var model
    let blockReason: String?

    var body: some View {
        let phase = model.printPhase
        switch phase {
        case .positioning(let remaining):
            PositioningProgress(remaining: remaining, message: phase.message ?? "")
                .id(remaining)
        case .printing(let done, let total):
            HStack(spacing: 12) {
                ProgressView(value: Double(done), total: Double(max(total, 1))) {
                    Text(phase.message ?? "")
                }
                .frame(maxWidth: 260)
                Button(L10n.string("Cancel"), action: model.cancelPrint)
                    .keyboardShortcut(.cancelAction)
            }
        case .finished:
            Label {
                Text(phase.message ?? "")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .cancelled:
            Label(phase.message ?? "", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
                .lineLimit(2)
        case .failed:
            Label {
                Text(phase.message ?? "").lineLimit(2)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        case .idle:
            if let blockReason {
                Label(blockReason, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            } else {
                // Keeps the bar's middle flexible, so Print stays at the trailing edge.
                Color.clear.frame(height: 0)
            }
        }
    }
}
