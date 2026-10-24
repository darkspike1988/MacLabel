import AppKit
import Foundation
import SwiftUI
import Testing
import LabelMedia
import LabelProtocol
import LabelTransport
@testable import MacLabelApp

private func textDocument(_ text: String) -> LabelDocument {
    var d = LabelDocument()
    d.text = text
    return d
}

private let okPreview = PreviewResult(pages: [], totalLabels: 1, overflowIndices: [], error: nil)

@Suite struct PanelActionTests {
    @Test func normalTextPrints() {
        #expect(MenuBarPanel.action(for: textDocument("Keller"), preview: okPreview) == .print)
    }

    @Test func textBeforeThePreviewIsReadyStillPrints() {
        #expect(MenuBarPanel.action(for: textDocument("Keller"), preview: nil, hasRoll: true) == .print)
    }

    @Test func overflowOpensTheWindow() {
        let overflow = PreviewResult(pages: [], totalLabels: 1, overflowIndices: [0], error: nil)
        #expect(MenuBarPanel.action(for: textDocument("zu lang"), preview: overflow) == .openWindow)
    }

    @Test func emptyOrBlankTextIsDisabled() {
        for text in ["", "  \n "] {
            guard case .disabled = MenuBarPanel.action(for: textDocument(text), preview: okPreview) else {
                Issue.record("expected .disabled for \(text.debugDescription)")
                continue
            }
        }
    }

    @Test func missingRollIsDisabledWithGermanText() {
        let noRoll = PreviewResult(pages: [], totalLabels: 1, overflowIndices: [], error: "No roll selected.", missingRoll: true)
        let de = localizedBundle(preferred: ["de"])
        #expect(MenuBarPanel.action(for: textDocument("Keller"), preview: noRoll, bundle: de) == .disabled("Keine Rolle gewählt"))
        let en = localizedBundle(preferred: ["en"])
        #expect(MenuBarPanel.action(for: textDocument("Keller"), preview: noRoll, bundle: en) == .disabled("No roll chosen"))
    }

    @Test func otherRenderErrorIsDisabledWithItsText() {
        let broken = PreviewResult(pages: [], totalLabels: 0, overflowIndices: [], error: "kaputt")
        #expect(MenuBarPanel.action(for: textDocument("x"), preview: broken) == .disabled("kaputt"))
    }

    @Test func documentIsAPlainTextLabel() {
        let d = MenuBarPanel.document(text: "Hallo")
        #expect(d.layout == .text && d.text == "Hallo" && d.copies == 1)
    }

    @Test func panelStringsInGerman() {
        let de = localizedBundle(preferred: ["de"])
        #expect(String(localized: "Text too long – open in window", bundle: de) == "Text zu lang – im Fenster öffnen")
    }
}

@Suite struct AppSettingsTests {
    @Test func defaultsAreOn() {
        let settings = AppSettings(defaults: tempDefaults())
        #expect(settings.showMenuBarExtra)
        #expect(settings.statusPolling)
        #expect(settings.defaultPrinterSerial == nil)
    }

    @Test func readsStoredValues() {
        let defaults = tempDefaults()
        defaults.set(false, forKey: "statusPolling")
        defaults.set(false, forKey: "showMenuBarExtra")
        defaults.set("S2", forKey: "defaultPrinterSerial")
        let settings = AppSettings(defaults: defaults)
        #expect(!settings.statusPolling && !settings.showMenuBarExtra)
        #expect(settings.defaultPrinterSerial == "S2")
    }

    @Test func homebrewBranchNeedsNoAdministrator() {
        #expect(AppSettings.cliInstall(bundlePath: "/Applications/MacLabel.app", homebrewBinWritable: true)
            == .homebrew("ln -sf '/Applications/MacLabel.app/Contents/MacOS/maclabel' /opt/homebrew/bin/maclabel"))
    }

    @Test func systemBranchUsesSudoAndCreatesTheDirectory() {
        #expect(AppSettings.cliInstall(bundlePath: "/Applications/MacLabel.app", homebrewBinWritable: false)
            == .systemWide("sudo mkdir -p /usr/local/bin && sudo ln -sf '/Applications/MacLabel.app/Contents/MacOS/maclabel' /usr/local/bin/maclabel"))
    }

    @Test func pathWithSpacesAndApostropheIsQuoted() {
        let install = AppSettings.cliInstall(bundlePath: "/Users/o'neil/My Apps/MacLabel.app", homebrewBinWritable: true)
        #expect(install == .homebrew("ln -sf '/Users/o'\\''neil/My Apps/MacLabel.app/Contents/MacOS/maclabel' /opt/homebrew/bin/maclabel"))
    }

    @Test func translocatedAppMustMoveFirst() {
        let path = "/private/var/folders/xy/AppTranslocation/ABC/d/MacLabel.app"
        #expect(AppSettings.cliInstall(bundlePath: path, homebrewBinWritable: true) == .moveFirst)
        #expect(AppSettings.cliInstall(bundlePath: path, homebrewBinWritable: false) == .moveFirst)
    }
}

@Suite(.serialized) struct SettingsWiringTests {
    @Test @MainActor func disablingPollingStopsTheMonitor() async {
        let defaults = tempDefaults()
        let m = makeViewModel(printers: [appLW450Printer], remembered: "11354", defaults: defaults)
        m.monitor.visibilityChanged(visible: true)
        #expect(m.monitor.isPolling)
        defaults.set(false, forKey: "statusPolling")
        await waitFor { !m.monitor.isPolling }
        #expect(!m.monitor.isPolling)
        defaults.set(true, forKey: "statusPolling")
        await waitFor { m.monitor.isPolling }
        #expect(m.monitor.isPolling)
        m.monitor.visibilityChanged(visible: false)
    }

    @Test @MainActor func startsWithoutPollingWhenSwitchedOff() {
        let defaults = tempDefaults()
        defaults.set(false, forKey: "statusPolling")
        let m = makeViewModel(printers: [appLW450Printer], remembered: "11354", defaults: defaults)
        m.monitor.visibilityChanged(visible: true)
        #expect(!m.monitor.isPolling)
        m.monitor.visibilityChanged(visible: false)
    }

    @Test @MainActor func defaultPrinterIsSelectedBySerial() async {
        let defaults = tempDefaults()
        defaults.set("S2", forKey: "defaultPrinterSerial")
        let m = makeViewModel(printers: [appLW450Printer, appLW550Printer], remembered: "11354", defaults: defaults)
        await m.refreshPrinters()
        #expect(m.selectedPrinter?.serialNumber == "S2")
        defaults.set("S1", forKey: "defaultPrinterSerial")
        await waitFor { m.selectedPrinter?.serialNumber == "S1" }
        #expect(m.selectedPrinter?.serialNumber == "S1")
    }

    @Test @MainActor func withoutDefaultTheFirstClassicPrinterWins() async {
        let m = makeViewModel(printers: [appLW550Printer, appLW450Printer], remembered: "11354")
        await m.refreshPrinters()
        #expect(m.selectedPrinter?.serialNumber == "S1")
    }

    @Test @MainActor func panelPrintsItsOwnDocumentNotTheWindows() async {
        let m = makeViewModel(printers: [appLW450Printer], remembered: "11354")
        await m.refreshPrinters()
        m.document.text = "Fenster"
        await m.print(document: MenuBarPanel.document(text: "Panel"), allowOverflow: false)
        #expect(m.printPhase == .finished(1))
        #expect(m.document.text == "Fenster")
    }
}

@Suite(.serialized) struct PanelSnapshotTests {
    @Test @MainActor func panelReady() async throws {
        let m = makeViewModel(printers: [appLW450Printer], remembered: "11354")
        await m.refreshPrinters()
        await m.monitor.refreshNow()
        try await shoot(MenuBarPanel(initialText: "Keller\nRegal 3"), model: m, name: "panel-ready")
    }

    @Test @MainActor func panelOverflow() async throws {
        let m = makeViewModel(printers: [appLW450Printer], remembered: "11354")
        await m.refreshPrinters()
        await m.monitor.refreshNow()
        try await shoot(MenuBarPanel(initialText: String(repeating: "Überlauf ", count: 200)), model: m, name: "panel-overflow")
    }

    @Test @MainActor func settingsRender() async throws {
        let m = makeViewModel(printers: [appLW450Printer, appLW550Printer], remembered: "11354")
        await m.refreshPrinters()
        let window = makeWindow(SettingsView().environment(m), size: CGSize(width: 520, height: 520), appearance: .aqua)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(400))
        let image = try snapshot(of: try #require(window.contentView?.superview))
        #expect(distinctColors(image) > 1)
        try saveIfRequested(image, name: "settings-light")
    }

    @MainActor
    private func shoot(_ panel: MenuBarPanel, model: AppModel, name: String) async throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let window = makeWindow(panel.environment(model), size: CGSize(width: 320, height: 300), appearance: appearance)
            try await Task.sleep(for: .milliseconds(500))
            let image = try snapshot(of: try #require(window.contentView?.superview))
            #expect(distinctColors(image) > 1, "\(name) rendered blank")
            try saveIfRequested(image, name: "\(name)-\(appearance == .aqua ? "light" : "dark")")
            window.close()
        }
    }
}

@Suite(.serialized) struct FixRound1Tests {
    @Test @MainActor func foreignDefaultsKeyDoesNotResetTheSelection() async {
        let defaults = tempDefaults()
        defaults.set("S1", forKey: "defaultPrinterSerial")
        let other = DiscoveredPrinter(id: 3, model: appLW450, serialNumber: "S3", locationID: nil)
        let m = makeViewModel(printers: [appLW450Printer, other], remembered: "11354", defaults: defaults)
        await m.refreshPrinters()
        #expect(m.selectedPrinter?.serialNumber == "S1")
        m.selectedPrinter = other
        defaults.set("irrelevant", forKey: "NSWindow Frame Foo")
        defaults.set(true, forKey: "statusPolling")
        await Task.yield()
        #expect(m.selectedPrinter?.serialNumber == "S3")
    }

    @Test @MainActor func switchingToAPrinterWithoutRollClearsTheRoll() async {
        let other = DiscoveredPrinter(id: 3, model: appLW450, serialNumber: "S3", locationID: nil)
        let m = makeViewModel(printers: [appLW450Printer, other], remembered: "11354")
        await m.refreshPrinters()
        #expect(m.roll?.id == "11354")
        m.selectedPrinter = other
        #expect(m.roll == nil)
        #expect(m.printBlockReason != nil)
        await m.print(document: MenuBarPanel.document(text: "x"), allowOverflow: false)
        guard case .failed = m.printPhase else {
            Issue.record("expected the print to be refused, got \(m.printPhase)")
            return
        }
        await m.refreshPrinters()
    }

    @Test func blockReasonWinsOverAnOldOutcome() {
        #expect(PrintStatusView.showsBlockReason(phase: .finished(1), blockReason: "No printer connected."))
        #expect(PrintStatusView.showsBlockReason(phase: .idle, blockReason: "x"))
        #expect(!PrintStatusView.showsBlockReason(phase: .printing(done: 0, total: 1), blockReason: "x"))
        #expect(!PrintStatusView.showsBlockReason(phase: .positioning(remaining: .seconds(1)), blockReason: "x"))
        #expect(!PrintStatusView.showsBlockReason(phase: .idle, blockReason: nil))
    }

    @Test @MainActor func clearingTheOutcomeKeepsARunningPrint() async {
        let m = makeViewModel(printers: [appLW450Printer], remembered: "11354")
        await m.refreshPrinters()
        await m.print(document: MenuBarPanel.document(text: "x"), allowOverflow: false)
        #expect(m.printPhase == .finished(1))
        m.clearPrintOutcome()
        #expect(m.printPhase == .idle)
    }

    @Test func noRollDisablesBeforeAnyPreviewExists() {
        let de = localizedBundle(preferred: ["de"])
        #expect(MenuBarPanel.action(for: textDocument("x"), preview: nil, hasRoll: false, bundle: de) == .disabled("Keine Rolle gewählt"))
    }

    @Test func settingsListsAStoredPrinterThatIsNotConnected() {
        let choices = SettingsView.printerChoices(connected: [appLW450Printer, appLW550Printer], saved: "S9")
        #expect(choices.map(\.serial) == ["S1", "S2", "S9"])
        #expect(choices.last?.isConnected == false)
        #expect(SettingsView.printerChoices(connected: [appLW450Printer], saved: "S1").count == 1)
        #expect(SettingsView.printerChoices(connected: [appLW450Printer], saved: "").count == 1)
    }

    @Test func changeButtonUsesTheTypographicEllipsis() {
        let de = localizedBundle(preferred: ["de"])
        #expect(String(localized: "Change…", bundle: de) == "Ändern…")
        #expect(String(localized: "Print the text (⌘↩)", bundle: de) == "Text drucken (⌘↩)")
        #expect(String(localized: "\("S9") (not connected)", bundle: de) == "S9 (nicht verbunden)")
    }
}
