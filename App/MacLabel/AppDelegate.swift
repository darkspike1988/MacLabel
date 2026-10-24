import AppKit
import MacLabelApp

/// Registers the "Print with MacLabel" Service (`NSServices` in Info.plist, message `printLabel`).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    /// Services entry point (`printLabel:userData:error:`): the selected text becomes the window's
    /// text label (Edit › Undo restores the previous document); nothing is printed until the user clicks Print.
    @objc func printLabel(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = String(localized: "The selection contains no text.") as NSString
            return
        }
        AppEnvironment.model.load(text: text)
        AppEnvironment.showMainWindow()
    }
}
