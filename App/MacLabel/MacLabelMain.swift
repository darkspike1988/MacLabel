import MacLabelApp
import SwiftUI

/// MacLabel: one main window (`Window`, not `WindowGroup`: a single-document utility, so
/// `openWindow(id: "main")` from the menu bar panel, Settings or the Service brings the existing
/// window to the front instead of opening a second document), the menu bar extra and Settings.
/// All scenes share one `AppModel` on `LabelPrinter.shared`.
@main
struct MacLabelMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppSettings.showMenuBarExtraKey) private var showMenuBarExtra = true
    private let model = AppEnvironment.model

    var body: some Scene {
        Window(Text(verbatim: "MacLabel"), id: AppEnvironment.mainWindowID) {
            MainWindow()
                .environment(model)
        }
        .defaultLaunchBehavior(.presented)
        .commands {
            MacLabelCommands()
            OpenWindowCapture()
        }

        MenuBarExtra("MacLabel", systemImage: "printer", isInserted: $showMenuBarExtra) {
            MenuBarPanel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
