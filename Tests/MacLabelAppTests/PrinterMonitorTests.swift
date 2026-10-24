import Foundation
import Testing
import LabelMedia
import LabelProtocol
import LabelTransport
import MacLabelKit
@testable import MacLabelApp

@Suite struct PrinterMonitorTests {
    @MainActor
    private func monitor(_ factory: AppStubFactory, interval: Duration = .milliseconds(20), busyBackoff: Duration = .seconds(15)) -> PrinterMonitor {
        let printer = LabelPrinter(factory: factory, preferences: appPrefs(), formFeedClock: AppNoStampClock())
        let m = PrinterMonitor(printer: printer, interval: interval, busyBackoff: busyBackoff)
        m.target = appLW450Printer
        return m
    }

    @Test @MainActor func monitorPollsOnlyWhenVisible() async throws {
        let factory = AppStubFactory(list: [appLW450Printer])
        let m = monitor(factory)
        try await Task.sleep(for: .milliseconds(100))
        #expect(factory.log.statusQueries == 0)
        m.visibilityChanged(visible: true)
        // Wait for two polls; a busy main actor (window tests running in parallel) may delay them.
        await waitFor(timeout: .seconds(3)) { factory.log.statusQueries >= 2 }
        #expect(factory.log.statusQueries >= 2)
        #expect(m.state == .ready(name: "LabelWriter 450"))
        m.visibilityChanged(visible: false)
        try await Task.sleep(for: .milliseconds(30))
        let stopped = factory.log.statusQueries
        try await Task.sleep(for: .milliseconds(100))
        #expect(factory.log.statusQueries == stopped)
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

    @Test @MainActor func monitorBacksOffWhenBusy() async throws {
        let factory = AppStubFactory(list: [appLW450Printer], openError: .busy)
        let m = monitor(factory, busyBackoff: .milliseconds(200))
        m.visibilityChanged(visible: true)
        try await Task.sleep(for: .milliseconds(150))
        #expect(factory.log.opens == 1)
        #expect(m.state == .busy(name: "LabelWriter 450"))
        await waitFor(timeout: .seconds(3)) { factory.log.opens >= 2 }
        #expect(factory.log.opens >= 2)
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
