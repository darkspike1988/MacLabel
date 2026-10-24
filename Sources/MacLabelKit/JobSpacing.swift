import Foundation

/// Remembers when a printer last received a form feed (`ESC E`).
public protocol FormFeedClock: Sendable {
    func lastFormFeed(serial: String?) -> Date?
    func recordFormFeed(serial: String?, at date: Date)
}

/// Persists form-feed times in user defaults, so separate CLI runs see each other.
public struct UserDefaultsFormFeedClock: FormFeedClock, @unchecked Sendable {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func lastFormFeed(serial: String?) -> Date? {
        defaults.object(forKey: key(serial)) as? Date
    }
    public func recordFormFeed(serial: String?, at date: Date) {
        defaults.set(date, forKey: key(serial))
    }
    private func key(_ serial: String?) -> String { "maclabel.lastFormFeed.\(serial ?? "default")" }

    /// Uses the suite named by `MACLABEL_DEFAULTS_SUITE` when set (tests), like `RollPreferences`.
    public static func standard() -> UserDefaultsFormFeedClock {
        if let suite = ProcessInfo.processInfo.environment["MACLABEL_DEFAULTS_SUITE"],
           !suite.isEmpty, let defaults = UserDefaults(suiteName: suite) {
            return UserDefaultsFormFeedClock(defaults: defaults)
        }
        return UserDefaultsFormFeedClock()
    }
}

/// Minimum pause between the previous job's form feed and the next job on the same printer.
///
/// On the LW450 a job that starts within seconds of the previous `ESC E` lands too low on the
/// label (the reverse feed after a tear-off feed is inaccurate); after a longer pause it is
/// correct. DYMO Connect avoids this by sending all labels of one print in a single job.
public struct JobSpacing: Sendable {
    /// Provisional value until measured on hardware (docs/research/lw450-protocol.md §13.2).
    public static let defaultMinimumPause: Duration = .seconds(10)

    public var clock: any FormFeedClock
    public var serial: String?
    public var minimumPause: Duration

    public init(clock: any FormFeedClock, serial: String?, minimumPause: Duration = JobSpacing.defaultMinimumPause) {
        self.clock = clock
        self.serial = serial
        self.minimumPause = minimumPause
    }

    /// Time still to wait before a new job may start, or `.zero`.
    func remainingPause(now: Date = Date()) -> Duration {
        guard let last = clock.lastFormFeed(serial: serial) else { return .zero }
        let elapsed = now.timeIntervalSince(last)
        let pause = Double(minimumPause.components.seconds) + Double(minimumPause.components.attoseconds) / 1e18
        let remaining = pause - elapsed
        return remaining > 0 ? .milliseconds(Int(remaining * 1000)) : .zero
    }
}
