import Foundation
import LabelMedia
import LabelTransport
import MacLabelKit
import Testing
@testable import MacLabelApp

/// The logic behind the "Print Label" and "Printer Status" App Intents (no window, no questions).
@Suite struct QuickPrintTests {
    private func printer(_ list: [DiscoveredPrinter], remembered: String?, log: DeviceLog = DeviceLog(),
                         openError: TransportError? = nil, blockFrom: Int? = nil) -> LabelPrinter {
        LabelPrinter(
            factory: AppStubFactory(list: list, log: log, blockFrom: blockFrom, openError: openError),
            preferences: appPrefs(remembered: remembered), formFeedClock: AppNoStampClock()
        )
    }

    /// Ruling A22: a roll named in the shortcut is used once; the window's remembered roll stays.
    @Test func explicitRollIsNotRemembered() async throws {
        let p = printer([appLW450Printer], remembered: "11354")
        #expect(try await p.printText("Keller", copies: 1, rollQuery: "99012") == 1)
        #expect(await p.rememberedRoll(for: appLW450Printer)?.id == "11354")
    }

    @Test func rememberedRollStaysRememberedWithoutQuery() async throws {
        let p = printer([appLW450Printer], remembered: "11354")
        _ = try await p.printText("Keller", copies: 1, rollQuery: nil)
        #expect(await p.rememberedRoll(for: appLW450Printer)?.id == "11354")
    }

    @Test func windowPrintsStillRememberTheRoll() async throws {
        let p = printer([appLW450Printer], remembered: nil)
        let roll = try #require(MediaCatalog.bundled.roll(id: "30321"))
        let request = PrintRequest(contents: [.text(.init(text: "x"))], roll: roll, model: appLW450)
        try await p.print(request, on: appLW450Printer) { _ in }
        #expect(await p.rememberedRoll(for: appLW450Printer)?.id == "30321")
    }

    /// Cancelling (e.g. the shortcut is stopped) ends in a plain sentence, not "CancellationError error 1".
    @Test func cancellationIsPlainLanguage() async {
        // Every status query hangs until the task is cancelled.
        let p = printer([appLW450Printer], remembered: "11354", blockFrom: 1)
        let job = Task { () -> Result<Int, QuickPrintError> in
            do throws(QuickPrintError) { return .success(try await p.printText("x", copies: 1, rollQuery: nil)) } catch { return .failure(error) }
        }
        try? await Task.sleep(for: .milliseconds(100))
        job.cancel()
        guard case .failure(let error) = await job.value else { Issue.record("printed despite cancel"); return }
        #expect(error == .failed(QuickPrintError.cancelledText))
        #expect(!error.localizedDescription.contains("CancellationError"))
    }

    /// Cancelled while the labels are checked (before the device): still the plain cancel sentence.
    @Test func cancellationDuringContentCheckIsPlainLanguage() async {
        let log = DeviceLog()
        let p = printer([appLW450Printer], remembered: "11354", log: log)
        let job = Task { () -> Result<Int, QuickPrintError> in
            withUnsafeCurrentTask { $0?.cancel() }
            do throws(QuickPrintError) { return .success(try await p.printText("x", copies: 1, rollQuery: nil)) } catch { return .failure(error) }
        }
        guard case .failure(let error) = await job.value else { Issue.record("printed despite cancel"); return }
        #expect(error == .failed(QuickPrintError.cancelledText))
        #expect(log.opens == 0)
    }

    @Test func noPrinterSaysNoPrinterConnected() async {
        let p = printer([], remembered: "11354")
        await #expect(throws: QuickPrintError.noPrinter(L10n.string("No printer connected."))) {
            try await p.printText("x", copies: 1, rollQuery: nil)
        }
    }

    @Test func otherErrorsBecomeFailedWithTheirDescription() {
        #expect(QuickPrintError(CancellationError()) == .failed(QuickPrintError.cancelledText))
        #expect(QuickPrintError(PrintError.nothingToPrint) == .failed(PrintError.nothingToPrint.localizedDescription))
        #expect(QuickPrintError(QuickPrintError.noRoll) == .noRoll)
        let de = localizedBundle(preferred: ["de"])
        #expect(String(localized: "Printing was cancelled.", bundle: de) == "Der Druck wurde abgebrochen.")
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
        } catch {
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
        } catch {
            guard case .printerNotReady(let text) = error else { Issue.record("\(error)"); return }
            #expect(text.contains("LabelWriter 450"))
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
