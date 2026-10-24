import Foundation

/// The keys and defaults of the Settings. The views bind them with `@AppStorage`;
/// `AppModel` reads them through this type and reacts to changes.
public struct AppSettings {
    public static let showMenuBarExtraKey = "showMenuBarExtra"
    public static let statusPollingKey = "statusPolling"
    public static let defaultPrinterSerialKey = "defaultPrinterSerial"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Show the menu bar extra (default `true`).
    public var showMenuBarExtra: Bool { defaults.object(forKey: Self.showMenuBarExtraKey) as? Bool ?? true }

    /// Poll the printer status automatically (default `true`).
    public var statusPolling: Bool { defaults.object(forKey: Self.statusPollingKey) as? Bool ?? true }

    /// The serial number of the printer to select first; `nil` or empty means automatic.
    public var defaultPrinterSerial: String? {
        defaults.string(forKey: Self.defaultPrinterSerialKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The Terminal command that links the bundled command line tool into `/usr/local/bin`.
    public static func cliInstallCommand(bundlePath: String = Bundle.main.bundlePath) -> String {
        "ln -sf \"\(bundlePath)/Contents/MacOS/maclabel\" /usr/local/bin/maclabel"
    }
}
