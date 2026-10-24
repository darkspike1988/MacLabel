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

    /// How the command line tool can be linked into the PATH.
    public enum CLIInstall: Equatable, Sendable {
        /// `/opt/homebrew/bin` exists and is writable: no administrator rights needed.
        case homebrew(String)
        /// `/usr/local/bin` needs `sudo` (asks for the administrator password).
        case systemWide(String)
        /// The app runs translocated (straight from the download); a link would break.
        case moveFirst
    }

    /// Whether `/opt/homebrew/bin` exists and the user may write there.
    public static var homebrewBinWritable: Bool {
        var isDirectory: ObjCBool = false
        let path = "/opt/homebrew/bin"
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue && FileManager.default.isWritableFile(atPath: path)
    }

    /// The Terminal command that links the bundled command line tool into the PATH.
    public static func cliInstall(
        bundlePath: String = Bundle.main.bundlePath, homebrewBinWritable: Bool = AppSettings.homebrewBinWritable
    ) -> CLIInstall {
        if bundlePath.contains("/AppTranslocation/") { return .moveFirst }
        let tool = "'" + (bundlePath + "/Contents/MacOS/maclabel").replacing("'", with: "'\\''") + "'"
        if homebrewBinWritable {
            return .homebrew("ln -sf \(tool) /opt/homebrew/bin/maclabel")
        }
        return .systemWide("sudo mkdir -p /usr/local/bin && sudo ln -sf \(tool) /usr/local/bin/maclabel")
    }
}
