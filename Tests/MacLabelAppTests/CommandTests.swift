import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MacLabelApp

/// The menu commands (File › Print, Label menu) act on the window's `AppModel`; these tests cover that logic.
@Suite struct CommandTests {
    @Test func layoutItemsUseCommandOneToFive() {
        #expect(LabelLayout.allCases == [.text, .address, .barcode, .qr, .image])
        #expect(LabelLayout.allCases.map(\.shortcut) == ["1", "2", "3", "4", "5"].map { KeyEquivalent(Character($0)) })
    }

    @Test func menuTitlesInBothLanguages() {
        let de = localizedBundle(preferred: ["de"]), en = localizedBundle(preferred: ["en"])
        #expect(String(localized: "Print… (menu item)", bundle: de) == "Drucken…")
        #expect(String(localized: "Print… (menu item)", bundle: en) == "Print…")
        #expect(String(localized: "Choose Roll… (menu item)", bundle: de) == "Rolle wählen…")
        #expect(String(localized: "Choose Roll… (menu item)", bundle: en) == "Choose Roll…")
        #expect(String(localized: "Label", bundle: de) == "Etikett")
    }

    @Test @MainActor func layoutCommandSwitchesLayout() {
        let m = makeViewModel(printers: [], remembered: nil)
        MacLabelCommands.select(.qr, in: m)
        #expect(m.document.layout == .qr)
        #expect(MacLabelCommands.isSelected(.qr, in: m))
        #expect(!MacLabelCommands.isSelected(.text, in: m))
    }

    @Test @MainActor func chooseRollCommandOpensThePicker() {
        let m = makeViewModel(printers: [], remembered: nil)
        #expect(!m.showsRollPicker)
        MacLabelCommands.chooseRoll(in: m)
        #expect(m.showsRollPicker)
    }

    @Test @MainActor func printCommandDisabledWithoutPrinterOrWindow() async {
        let m = makeViewModel(printers: [], remembered: nil)
        await m.refreshPrinters()
        m.document.text = "x"
        #expect(!m.canRequestPrint)
        #expect(!MacLabelCommands.canPrint(nil))
    }

    @Test @MainActor func printCommandPrintsWhenItFits() async {
        let m = makeViewModel(printers: [appLW450Printer], remembered: "11354")
        await m.refreshPrinters()
        m.document.text = "Keller"
        await waitFor { m.previewResult?.pages.count == 1 }
        #expect(MacLabelCommands.canPrint(m))
        m.requestPrint()
        #expect(!m.confirmsOverflowPrint)
        await waitFor { m.printPhase == .finished(1) }
        #expect(m.printPhase == .finished(1))
    }

    @Test @MainActor func printCommandAsksBeforeOverflow() async throws {
        let log = DeviceLog()
        let factory = AppStubFactory(list: [appLW450Printer], log: log)
        let printer = LabelPrinter(factory: factory, preferences: appPrefs(remembered: "11354"), formFeedClock: AppNoStampClock())
        let m = AppModel(printer: printer, preview: PreviewEngine(debounce: .zero, maxPages: 1), defaults: tempDefaults())
        await m.refreshPrinters()
        m.document.text = String(repeating: "Überlauf ", count: 200)
        await waitFor { m.previewResult?.overflowIndices == [0] }
        let opensBefore = log.opens
        m.requestPrint()
        #expect(m.confirmsOverflowPrint)
        try await Task.sleep(for: .milliseconds(100))
        #expect(m.printPhase == .idle)
        #expect(log.opens == opensBefore)
    }
}

/// "Text too long – open in window" and the Service replace the window's document; Edit › Undo brings it back.
@Suite struct LoadTextUndoTests {
    @MainActor private func manager() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }

    @Test @MainActor func loadIsUndoableAndRedoable() {
        let m = makeViewModel(printers: [], remembered: nil)
        let undo = manager()
        m.undoManager = undo
        m.document.layout = .barcode
        m.document.barcodeValue = "4711"
        let before = m.document
        m.load(text: "Keller")
        #expect(m.document.layout == .text && m.document.text == "Keller")
        #expect(undo.canUndo)
        undo.undo()
        #expect(m.document == before)
        #expect(undo.canRedo)
        undo.redo()
        #expect(m.document.text == "Keller" && m.document.layout == .text)
    }

    @Test @MainActor func loadBeforeTheWindowIsUndoableOnceItAppears() {
        let m = makeViewModel(printers: [], remembered: nil)
        m.document.text = "Alt"
        let before = m.document
        m.load(text: "Neu")
        let undo = manager()
        m.undoManager = undo
        #expect(undo.canUndo)
        undo.undo()
        #expect(m.document == before)
    }

    @Test @MainActor func loadingTheSameTextRegistersNothing() {
        let m = makeViewModel(printers: [], remembered: nil)
        let undo = manager()
        m.undoManager = undo
        m.load(text: "")
        #expect(!undo.canUndo)
    }
}
