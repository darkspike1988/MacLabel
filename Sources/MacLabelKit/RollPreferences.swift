import Foundation

/// Remembers the last used roll per printer serial number.
public struct RollPreferences: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Uses the suite named by `MACLABEL_DEFAULTS_SUITE` when set (tests, CLI tests).
    public static func standard() -> RollPreferences {
        if let suite = ProcessInfo.processInfo.environment["MACLABEL_DEFAULTS_SUITE"],
           !suite.isEmpty, let defaults = UserDefaults(suiteName: suite) {
            return RollPreferences(defaults: defaults)
        }
        return RollPreferences()
    }

    private func key(_ serial: String?) -> String { "maclabel.lastRoll.\(serial ?? "default")" }

    public func lastRollID(forPrinterSerial serial: String?) -> String? {
        defaults.string(forKey: key(serial))
    }

    public func setLastRollID(_ id: String, forPrinterSerial serial: String?) {
        defaults.set(id, forKey: key(serial))
    }
}
