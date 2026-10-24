import Foundation
import LabelTransport
import Testing
@testable import MacLabelApp

/// The logic behind the "Print Label" and "Printer Status" App Intents (no window, no questions).
@Suite struct QuickPrintTests {
    private func printer(_ list: [DiscoveredPrinter], remembered: String?, log: DeviceLog = DeviceLog(),
                         openError: TransportError? = nil) -> LabelPrinter {
        LabelPrinter(
            factory: AppStubFactory(list: list, log: log, openError: openError),
            preferences: appPrefs(remembered: remembered), formFeedClock: AppNoStampClock()
        )
    }

    @Test func printsWithRememberedRoll() async throws {
        let p = printer([appLW450Printer], remembered: "11354")
        let count = try await p.printText("Keller", copies: 2, rollQuery: nil)
        #expect(count == 2)
    }

    @Test func printsWithRollQuery() async throws {
        let p = printer([appLW450Printer], remembered: nil)
        #expect(try await p.printText("Keller", copies: 1, rollQuery: "11354") == 1)
    }

    @Test func noRollIsAPlainError() async {
        let log = DeviceLog()
        let p = printer([appLW450Printer], remembered: nil, log: log)
        await #expect(throws: QuickPrintError.noRoll) { try await p.printText("x", copies: 1, rollQuery: nil) }
        #expect(log.opens == 0)
    }

    @Test func unknownRollIsAPlainError() async {
        let p = printer([appLW450Printer], remembered: nil)
        await #expect(throws: QuickPrintError.noMatchingRoll("zzzz-nothing")) {
            try await p.printText("x", copies: 1, rollQuery: "zzzz-nothing")
        }
    }

    @Test func ambiguousRollIsAPlainError() async throws {
        let p = printer([appLW450Printer], remembered: nil)
        do {
            _ = try await p.printText("x", copies: 1, rollQuery: "address")
            Issue.record("expected an error")
        } catch let error as QuickPrintError {
            guard case .ambiguousRoll(let query, let ids) = error else { Issue.record("\(error)"); return }
            #expect(query == "address" && ids.count > 1)
            #expect(error.localizedDescription.contains(ids[0]))
        }
    }

    @Test func overflowIsRefused() async {
        let log = DeviceLog()
        let p = printer([appLW450Printer], remembered: "11354", log: log)
        await #expect(throws: QuickPrintError.overflow) {
            try await p.printText(String(repeating: "Überlauf ", count: 200), copies: 1, rollQuery: nil)
        }
    }

    @Test func busyPrinterIsAPlainError() async {
        let p = printer([appLW450Printer], remembered: "11354", openError: .busy)
        do {
            _ = try await p.printText("x", copies: 1, rollQuery: nil)
            Issue.record("expected an error")
        } catch let error as QuickPrintError {
            guard case .printerNotReady(let text) = error else { Issue.record("\(error)"); return }
            #expect(text.contains("LabelWriter 450"))
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func noPrinterIsAPlainError() async {
        let p = printer([], remembered: "11354")
        await #expect(throws: QuickPrintError.self) { try await p.printText("x", copies: 1, rollQuery: nil) }
    }

    @Test func emptyTextAndBadCopiesAreRefused() async {
        let p = printer([appLW450Printer], remembered: "11354")
        await #expect(throws: QuickPrintError.emptyText) { try await p.printText("  \n", copies: 1, rollQuery: nil) }
        await #expect(throws: QuickPrintError.invalidCopies) { try await p.printText("x", copies: 0, rollQuery: nil) }
    }

    @Test func statusText() async {
        #expect(await printer([appLW450Printer], remembered: nil).statusText() == PrinterState.ready(name: "LabelWriter 450").statusText)
        #expect(await printer([], remembered: nil).statusText() == PrinterState.noPrinter.statusText)
    }

    @Test func errorsInGerman() {
        let de = localizedBundle(preferred: ["de"])
        #expect(QuickPrintError.noRoll.text(bundle: de).contains("Rolle"))
        #expect(QuickPrintError.overflow.text(bundle: de).contains("passt nicht"))
    }
}
