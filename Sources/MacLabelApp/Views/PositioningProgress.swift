import SwiftUI

/// The `JobSpacing` pause before a print: a determinate bar counting down `remaining`.
/// The parent gives it a new identity per pause, so `start` is the moment the pause was announced.
struct PositioningProgress: View {
    let remaining: Duration
    let message: String
    @State private var start = Date.now

    var body: some View {
        let seconds = max(Double(remaining.components.seconds) + Double(remaining.components.attoseconds) / 1e18, 0.1)
        ProgressView(timerInterval: start...start.addingTimeInterval(seconds), countsDown: true) {
            Text(message)
        }
        .frame(maxWidth: 260)
    }
}
