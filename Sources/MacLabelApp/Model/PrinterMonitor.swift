import Foundation
import LabelTransport
import Observation

/// Polls the status of `target` every `interval`, but only while polling is enabled and at least one window or panel is
/// visible and no print is running. After "busy" (another app holds the printer) it waits `busyBackoff`.
@MainActor @Observable
public final class PrinterMonitor {
    public private(set) var state: PrinterState = .noPrinter
    /// The printer to query; set by `AppModel` when the selection changes.
    public var target: DiscoveredPrinter?
    /// Called before a poll when no printer is known or the last poll found it disconnected,
    /// so a re-plugged printer (new registry id) is picked up again.
    @ObservationIgnored public var rediscover: (@MainActor () async -> Void)?

    /// The "poll the printer status automatically" setting; `false` stops the loop even while visible.
    public var pollingEnabled = true {
        didSet { if pollingEnabled != oldValue { updateLoop() } }
    }

    /// Whether the polling loop is running.
    public var isPolling: Bool { loop != nil }

    @ObservationIgnored private let printer: LabelPrinter
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let busyBackoff: Duration
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var visibleCount = 0
    @ObservationIgnored private var paused = false
    private var loop: Task<Void, Never>?

    public init(
        printer: LabelPrinter, interval: Duration = .seconds(5), busyBackoff: Duration = .seconds(15),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.printer = printer
        self.sleep = sleep
        self.interval = interval
        self.busyBackoff = busyBackoff
    }

    /// Counts visible windows and panels; polling runs while the count is above zero.
    public func visibilityChanged(visible: Bool) {
        visibleCount = visible ? visibleCount + 1 : max(0, visibleCount - 1)
        updateLoop()
    }

    /// Stops polling (during a print) and shows the target as printing; `resume()` restarts
    /// polling if something is visible.
    public func pause() {
        paused = true
        if let target { state = .printing(name: target.model.name) }
        updateLoop()
    }

    public func resume() {
        paused = false
        updateLoop()
    }

    /// One poll right away, independent of visibility.
    public func refreshNow() async {
        _ = await poll()
    }

    private func updateLoop() {
        let shouldRun = visibleCount > 0 && !paused && pollingEnabled
        if shouldRun, loop == nil {
            let sleep = sleep
            loop = Task { [weak self] in
                while !Task.isCancelled {
                    guard let wait = await self?.poll() else { return }
                    try? await sleep(wait)
                }
            }
        } else if !shouldRun, let running = loop {
            running.cancel()
            loop = nil
        }
    }

    /// Queries the status once and returns the wait until the next poll.
    private func poll() async -> Duration {
        if target == nil || state == .disconnected, let rediscover {
            await rediscover()
        }
        let result = await printer.state(for: target)
        // A poll that was already running when the print paused us must not overwrite "printing".
        if paused, let target {
            state = .printing(name: target.model.name)
        } else {
            state = result
        }
        // Only "busy" backs off; `.printing` is answered without opening the device.
        if case .busy = state { return busyBackoff }
        return interval
    }
}
