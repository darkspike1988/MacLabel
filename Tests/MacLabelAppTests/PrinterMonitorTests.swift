import Foundation
import Testing
import LabelMedia
import LabelProtocol
import LabelTransport
import MacLabelKit
@testable import MacLabelApp

@Suite struct PrinterMonitorTests {
    @MainActor
    private func monitor(
        _ factory: AppStubFactory, interval: Duration = .milliseconds(20), busyBackoff: Duration = .seconds(15),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) -> PrinterMonitor {
        let printer = LabelPrinter(factory: factory, preferences: appPrefs(), formFeedClock: AppNoStampClock())
        let m = PrinterMonitor(printer: printer, interval: interval, busyBackoff: busyBackoff, sleep: sleep)
        m.target = appLW450Printer
        return m
    }

    @Test @MainActor func monitorPollsOnlyWhenVisible() async throws {
        let factory = AppStubFactory(list: [appLW450Printer])
        let sleeper = ManualSleeper()
        let m = monitor(factory, sleep: { try await sleeper.sleep($0) })
        #expect(!m.isPolling)
        #expect(factory.log.statusQueries == 0)
        m.visibilityChanged(visible: true)
        await waitForAsync { await sleeper.sleepCount == 1 }
        #expect(factory.log.statusQueries == 1)
        await sleeper.advance()
        await waitForAsync { await sleeper.sleepCount == 2 }
        #expect(factory.log.statusQueries == 2)
        #expect(m.state == .ready(name: "LabelWriter 450"))
        m.visibilityChanged(visible: false)
        #expect(!m.isPolling)
        // Hiding cancels the pending sleep; the loop then ends without another query.
        await waitForAsync { await sleeper.pendingCount == 0 }
        for _ in 0..<20 { await Task.yield() }
        #expect(factory.log.statusQueries == 2)
        #expect(await sleeper.sleepCount == 2)
    }

    /// With automatic polling off (or nothing visible) no loop restarts after a print; the status
    /// must not stay "printing".
    @Test @MainActor func resumeWithoutPollingDoesNotStayPrinting() async {
        let factory = AppStubFactory(list: [appLW450Printer])
        let m = monitor(factory)
        m.pollingEnabled = false
        await m.refreshNow()
        #expect(m.state == .ready(name: "LabelWriter 450"))
        m.pause()
        #expect(m.state == .printing(name: "LabelWriter 450"))
        m.resume()
        #expect(!m.isPolling)
        #expect(m.state == .ready(name: "LabelWriter 450"))
        // Nothing visible: no device query after the print.
        #expect(factory.log.statusQueries == 1)
    }

    /// Visible with polling off: resuming asks the printer once.
    @Test @MainActor func resumeWhileVisibleWithoutPollingAsksOnce() async {
        let factory = AppStubFactory(list: [appLW450Printer])
        let m = monitor(factory)
        m.pollingEnabled = false
        m.visibilityChanged(visible: true)
        #expect(!m.isPolling)
        m.pause()
        #expect(m.state == .printing(name: "LabelWriter 450"))
        m.resume()
        #expect(!m.isPolling)
        // The query is counted before its answer is applied; wait for the state.
        await waitFor { m.state == .ready(name: "LabelWriter 450") }
        #expect(m.state == .ready(name: "LabelWriter 450"))
        #expect(factory.log.statusQueries == 1)
        m.visibilityChanged(visible: false)
    }

    @Test @MainActor func visibilityIsCounted() async throws {
        let factory = AppStubFactory(list: [appLW450Printer])
        let m = monitor(factory)
        m.visibilityChanged(visible: true)  // window
        m.visibilityChanged(visible: true)  // panel
        m.visibilityChanged(visible: false) // panel closes, window still visible
        #expect(m.isPolling)
        m.visibilityChanged(visible: false)
        #expect(!m.isPolling)
        m.visibilityChanged(visible: false) // extra hide never goes below zero
        m.visibilityChanged(visible: true)
        #expect(m.isPolling)
        m.visibilityChanged(visible: false)
    }

    @Test @MainActor func pauseStopsPolling() async throws {
        let factory = AppStubFactory(list: [appLW450Printer])
        let m = monitor(factory)
        m.visibilityChanged(visible: true)
        m.pause()
        #expect(!m.isPolling)
        try await Task.sleep(for: .milliseconds(30))
        let paused = factory.log.statusQueries
        try await Task.sleep(for: .milliseconds(100))
        #expect(factory.log.statusQueries == paused)
        m.resume()
        #expect(m.isPolling)
        m.visibilityChanged(visible: false)
    }

    @Test @MainActor func monitorBacksOffWhenBusy() async {
        let factory = AppStubFactory(list: [appLW450Printer], openError: .busy)
        let sleeper = ManualSleeper()
        let m = monitor(factory, busyBackoff: .seconds(15), sleep: { try await sleeper.sleep($0) })
        m.visibilityChanged(visible: true)
        await waitForAsync { await sleeper.sleepCount == 1 }
        #expect(await sleeper.requests == [.seconds(15)])
        #expect(factory.log.opens == 1)
        #expect(m.state == .busy(name: "LabelWriter 450"))
        await sleeper.advance()
        await waitFor { factory.log.opens == 2 }
        #expect(factory.log.opens == 2)
        m.visibilityChanged(visible: false)
    }

    @Test @MainActor func restartingWhileBusyPollsImmediately() async {
        let factory = AppStubFactory(list: [appLW450Printer], openError: .busy)
        let sleeper = ManualSleeper()
        let m = monitor(factory, sleep: { try await sleeper.sleep($0) })
        m.visibilityChanged(visible: true)
        await waitForAsync { await sleeper.sleepCount == 1 }
        m.visibilityChanged(visible: false)
        m.visibilityChanged(visible: true)
        // No `advance()`: the restarted loop must query first and only then wait.
        await waitFor { factory.log.opens == 2 }
        #expect(factory.log.opens == 2)
        m.visibilityChanged(visible: false)
    }

    @Test @MainActor func refreshNowQueriesOnce() async {
        let factory = AppStubFactory(list: [appLW450Printer])
        let m = monitor(factory)
        await m.refreshNow()
        #expect(factory.log.statusQueries == 1 && m.state == .ready(name: "LabelWriter 450"))
    }

    @Test @MainActor func rediscoversAfterDisconnect() async {
        let factory = AppStubFactory(list: [appLW450Printer], openError: .disconnected)
        let m = monitor(factory)
        var rediscovered = 0
        m.rediscover = { rediscovered += 1 }
        await m.refreshNow()
        #expect(m.state == .disconnected && rediscovered == 0)
        await m.refreshNow()
        #expect(rediscovered == 1)
    }
}
