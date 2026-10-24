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

    /// `openWindow(id: "main")`, captured from the main window's environment.
    static var openMainWindowAction: OpenWindowAction?

    /// Opens the main window (or brings it to the front) and activates the app.
    static func showMainWindow() {
        if let openMainWindowAction {
            openMainWindowAction(id: mainWindowID)
        } else {
            // Before any scene captured the action, the window is being built at launch anyway.
            NSApp.windows.first { $0.identifier?.rawValue == mainWindowID }?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
    }
}

/// Hands the scene's `openWindow` to `AppEnvironment`, so non-view code (the Service) can open the window.
struct MainWindowOpenerCapture: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
            .onAppear { AppEnvironment.openMainWindowAction = openWindow }
    }
}
