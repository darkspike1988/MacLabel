import AppKit
import MacLabelApp
import SwiftUI

/// Process-wide objects shared by the scenes, the Service and the App Intents.
@MainActor
enum AppEnvironment {
    static let mainWindowID = "main"

    /// Created on first use, so a Service call that arrives before any scene is built still has a
    /// model: the text lands in its document and the window shows it when it appears.
    static let model = AppModel(printer: .shared)

    /// `openWindow`, captured from SwiftUI (see `OpenWindowCapture`). SwiftUI evaluates the app's
    /// commands to build the main menu while the app launches, before AppKit delivers Service
    /// requests or reopen events, so this is set whenever non-view code needs it.
    static var openWindowAction: OpenWindowAction?

    /// Opens the main window, or brings the existing one to the front, and activates the app.
    /// Without a captured action (not expected after launch) it only activates the app.
    static func showMainWindow() {
        openWindowAction?(id: mainWindowID)
        NSApp.activate()
    }
}

/// Hands SwiftUI's `openWindow` to `AppEnvironment`. Commands, unlike views, exist without any open
/// window (the main menu is always built), so the action is available even when the window is closed.
struct OpenWindowCapture: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Re-evaluated with the menu; storing the same action again is harmless.
        let _ = (AppEnvironment.openWindowAction = openWindow)
        EmptyCommands()
    }
}
