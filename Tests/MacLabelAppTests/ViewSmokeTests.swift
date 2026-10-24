import AppKit
import Foundation
import SwiftUI
import Testing
import LabelMedia
import LabelProtocol
import LabelRender
import LabelTransport
import MacLabelKit
@testable import MacLabelApp

// MARK: - Pure view logic

@Suite struct RollPickerLogicTests {
    @Test func sizeQueryGroupsStandardFirst() {
        let groups = RollPicker.groups(for: "32x57", catalog: .bundled)
        #expect(groups.count == 1)
        #expect(groups.first?.first?.id == "11354")
        #expect(groups.first?.contains { $0.id == "1933084" } == true)
    }

    @Test func emptyQueryListsEveryRollOnce() {
        let groups = RollPicker.groups(for: "  ", catalog: .bundled)
        #expect(groups.flatMap { $0 }.count == MediaCatalog.bundled.rolls.count)
    }

    @Test func headFilterDropsWideRolls() {
        let all = RollPicker.groups(for: "", catalog: .bundled, headDots: 672).flatMap { $0 }
        #expect(!all.contains { $0.minHeadDots > 672 })
        #expect(all.contains { $0.id == "11354" })
    }

    @Test func quickChoicesFitTheHead() {
        let narrow = FirstRunRollSheet.quickChoices(catalog: .bundled, headDots: 672).map(\.id)
        #expect(narrow.first == "11354")
        #expect(!narrow.contains("S0904980"))
        let wide = FirstRunRollSheet.quickChoices(catalog: .bundled, headDots: 1248).map(\.id)
        #expect(wide.contains("S0904980"))
    }

    @Test func chipTextShowsIDAndReadingSize() {
        #expect(RollPicker.chipText(appRoll11354) == "11354 · 57 × 32 mm")
    }

    @Test func feedDirectionFollowsRotation() {
        #expect(FeedDirection(rotation: .upright) == .up)
        #expect(FeedDirection(rotation: .clockwise90) == .left)
        #expect(FeedDirection(rotation: .upsideDown) == .down)
        #expect(FeedDirection(rotation: .counterClockwise90) == .right)
    }

    @Test func statusTextsInGerman() {
        let de = localizedBundle(preferred: ["de"])
        #expect(PrinterState.noPrinter.statusText(bundle: de) == "Kein Drucker")
        #expect(PrinterState.ready(name: "LabelWriter 450").statusText(bundle: de) == "LabelWriter 450 · bereit")
        #expect(PrinterState.busy(name: "LabelWriter 450").statusText(bundle: de) == "LabelWriter 450 · belegt")
        #expect(PrinterState.printing(name: "LabelWriter 450").statusText(bundle: de) == "LabelWriter 450 · druckt …")
    }
}

@Suite struct DocumentEditingTests {
    @Test func placeholderGoesIntoTheLayoutsMainField() {
        var d = LabelDocument()
        d.text = "Nr. "
        d.insertPlaceholder("n")
        #expect(d.text == "Nr. {n}")
        d.layout = .barcode
        d.insertPlaceholder("Artikel")
        #expect(d.barcodeValue == "{Artikel}")
        d.layout = .qr
        d.qrKind = .wifi
        d.insertPlaceholder("ssid")
        #expect(d.wifiSSID == "{ssid}")
    }

    @Test func counterToggleKeepsSettings() {
        var d = LabelDocument()
        #expect(!d.counterEnabled)
        d.counterEnabled = true
        #expect(d.counter == CounterSpec())
        d.counterStart = 7
        d.counterDigits = 3
        #expect(d.counter == CounterSpec(start: 7, minimumDigits: 3))
        d.counterEnabled = false
        #expect(d.counter == nil)
    }

    @Test func spokenTextExpandsTheShownLabel() {
        var d = LabelDocument()
        d.text = "Kiste {n}"
        d.counter = CounterSpec(start: 5)
        d.copies = 3
        #expect(d.spokenText(at: 1) == "Kiste 6")
        d.layout = .barcode
        d.barcodeValue = "12345"
        #expect(d.spokenText(at: 0).contains("12345"))
    }

    @Test func counterStartIsClamped() {
        var d = LabelDocument()
        d.counterEnabled = true
        d.counterStart = 5_000_000
        #expect(d.counterStart == 999_999)
        d.counterStart = -3
        #expect(d.counterStart == 0)
    }

    @Test func effectiveRotationMatchesGeometry() {
        let d = LabelDocument()
        #expect(d.effectiveRotation(for: appRoll11354) == .upright)
        let address = MediaCatalog.bundled.roll(sku: "99010")!
        #expect(d.effectiveRotation(for: address) == .clockwise90)
        var turned = d
        turned.rotation = .upsideDown
        #expect(turned.effectiveRotation(for: address) == .upsideDown)
    }
}

@Suite struct RollPickerSelectionTests {
    @Test func selectionStaysWhileVisibleElseFirstResult() {
        let all = RollPicker.groups(for: "", catalog: .bundled)
        #expect(RollPicker.selection(afterFilter: all, keeping: "11354") == "11354")
        let filtered = RollPicker.groups(for: "32x57", catalog: .bundled)
        #expect(RollPicker.selection(afterFilter: filtered, keeping: "99010") == filtered.first?.first?.id)
        #expect(RollPicker.selection(afterFilter: [], keeping: "11354") == nil)
    }

    @Test func choosingByIDAndFirst() {
        let groups = RollPicker.groups(for: "32x57", catalog: .bundled)
        #expect(RollPicker.roll(ids: ["1933084"], in: groups)?.id == "1933084")
        #expect(RollPicker.roll(ids: [], in: groups)?.id == groups.first?.first?.id)
        #expect(RollPicker.roll(ids: ["nope"], in: groups) == nil)
    }
}

@Suite struct PreviewSizingTests {
    private let limit = CGSize(width: 560, height: 380)

    @Test func enlargesByWholeFactorsOnly() {
        // 100 × 60 dots on a 2x display: 560 × 2 / 100 = 11.2 and 380 × 2 / 60 = 12.7 -> factor 11.
        let size = PreviewSizing.size(pixels: CGSize(width: 100, height: 60), displayScale: 2, limit: limit)
        #expect(size == CGSize(width: 550, height: 330))
    }

    @Test func neverBelowOneDevicePixelPerDot() {
        // A 1193-dot label does not fit 560 pt even at 1:1 on a 2x display (596.5 pt): stay 1:1.
        let size = PreviewSizing.size(pixels: CGSize(width: 1193, height: 638), displayScale: 2, limit: limit)
        #expect(size == CGSize(width: 596.5, height: 319))
        let oneX = PreviewSizing.size(pixels: CGSize(width: 673, height: 378), displayScale: 1, limit: limit)
        #expect(oneX == CGSize(width: 673, height: 378))
    }

    @Test func commonRollFitsMinimumPreviewPaneOnRetina() {
        // 24 pt padding on both sides, feed arrow (about 14 pt) and spacing (12 pt) beside the label.
        let pane = MainWindow.previewMinWidth - 2 * 24 - 12 - 14
        let size = PreviewSizing.size(pixels: CGSize(width: 673, height: 378), displayScale: 2, limit: limit)
        #expect(size.width <= pane)
    }

    @Test func labelOfTheCommonRollIsShownAtOneToOneOnRetina() {
        let size = PreviewSizing.size(pixels: CGSize(width: 673, height: 378), displayScale: 2, limit: limit)
        #expect(size == CGSize(width: 336.5, height: 189))
    }

    @Test func emptyImageHasNoSize() {
        #expect(PreviewSizing.size(pixels: .zero, displayScale: 2, limit: limit) == .zero)
    }
}

// MARK: - Window smoke tests and snapshots

@Suite(.serialized) struct ViewSmokeTests {
    @Test @MainActor func noPrinter() async throws {
        let m = makeViewModel(printers: [], remembered: nil)
        await m.refreshPrinters()
        try await check(m, name: "no-printer", expectsPaper: false)
    }

    @Test @MainActor func readyWithTextPreview() async throws {
        let m = makeViewModel(printers: [appLW450Printer], remembered: "11354")
        await m.refreshPrinters()
        m.document.text = "Keller\nRegal 3"
        await waitFor { m.previewResult?.pages.count == 1 }
        await m.monitor.refreshNow()
        try await check(m, name: "ready-text")
    }

    @Test @MainActor func qrPreview() async throws {
        let m = makeViewModel(printers: [appLW450Printer], remembered: "11354")
        await m.refreshPrinters()
        m.document.layout = .qr
        m.document.qrKind = .url
        m.document.qrText = "maclabel.example"
        m.document.qrCaption = "Anleitung"
        await waitFor { m.previewResult?.pages.count == 1 }
        await m.monitor.refreshNow()
        try await check(m, name: "qr")
    }

    @Test @MainActor func overflow() async throws {
        let m = makeViewModel(printers: [appLW450Printer], remembered: "11354")
        await m.refreshPrinters()
        m.document.text = String(repeating: "Überlauf ", count: 200)
        await waitFor { m.previewResult?.overflowIndices == [0] }
        #expect(m.previewResult?.overflowIndices == [0])
        await m.monitor.refreshNow()
        try await check(m, name: "overflow")
    }

    @Test @MainActor func seriesWhilePrinting() async throws {
        // Status queries: 1 = ready check, 2 = after label 1, 3 = hangs until cancelled.
        let m = makeViewModel(printers: [appLW450Printer], remembered: "11354", blockFrom: 3, maxPages: 3)
        await m.refreshPrinters()
        m.document.text = "Kiste"
        m.document.copies = 3
        await waitFor { m.previewResult?.pages.count == 3 }
        let job = Task { await m.print(allowOverflow: false) }
        await waitFor { m.printPhase == .printing(done: 1, total: 3) }
        #expect(m.printPhase == .printing(done: 1, total: 3))
        try await check(m, name: "printing")
        m.cancelPrint()
        await job.value
    }

    @Test @MainActor func noRollChosen() async throws {
        let m = makeViewModel(printers: [appLW450Printer], remembered: nil)
        await m.refreshPrinters()
        m.needsRollChoice = false // keep the sheet out of this shot
        try await check(m, name: "no-roll", expectsPaper: false)
    }

    @Test @MainActor func firstRunSheetRenders() async throws {
        let model = makeViewModel(printers: [], remembered: nil)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let window = makeWindow(FirstRunRollSheet().environment(model), size: CGSize(width: 540, height: 600), appearance: appearance)
            try await Task.sleep(for: .milliseconds(300))
            let image = try snapshot(of: try #require(window.contentView?.superview))
            #expect(distinctColors(image) > 1)
            try saveIfRequested(image, name: "first-run-sheet-\(appearance == .aqua ? "light" : "dark")")
            window.close()
        }
    }

    @Test @MainActor func windowWithInspectorAtMinimumWidthRenders() async throws {
        let m = makeViewModel(printers: [appLW450Printer], remembered: "11354")
        await m.refreshPrinters()
        m.document.text = "Keller\nRegal 3"
        await waitFor { m.previewResult?.pages.count == 1 }
        await m.monitor.refreshNow()
        // Shrink the window below any sane size and measure what the window really allows.
        let window = makeWindow(MainWindow(showsInspector: true).environment(m), size: CGSize(width: 1400, height: 560), appearance: .aqua)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        window.setContentSize(CGSize(width: 200, height: 200))
        try await Task.sleep(for: .milliseconds(500))
        let width = window.contentLayoutRect.width
        // Content minimum plus the inspector column (260 minimum, 300 ideal), not the 940 of round 1.
        #expect(width >= MainWindow.minWidth + 260)
        #expect(width <= MainWindow.minWidth + 300 + 10, "min width \(width) is larger than content + inspector")
        let image = try snapshot(of: try #require(window.contentView?.superview ?? window.contentView))
        #expect(hasBlackPixel(image, inRight: 0.5))
        try saveIfRequested(image, name: "main-inspector-min-light")
    }

    @Test @MainActor func moreInspectorRenders() async throws {
        let model = makeViewModel(printers: [appLW450Printer], remembered: "11354")
        await model.refreshPrinters()
        model.document.counterEnabled = true
        model.document.csv = try CSVTable(parsing: "Name;Ort\nKiste;Keller\n")
        let window = makeWindow(MoreInspector().environment(model), size: CGSize(width: 260, height: 600), appearance: .aqua)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        let image = try snapshot(of: try #require(window.contentView?.superview))
        #expect(distinctColors(image) > 1)
        try saveIfRequested(image, name: "more-inspector-light")
    }

    @Test @MainActor func addressEditorShowsContactButton() async throws {
        let model = makeViewModel(printers: [appLW450Printer], remembered: "11354")
        await model.refreshPrinters()
        model.document.layout = .address
        model.document.addressText = "Max Mustermann\nMusterstraße 1\n12345 Musterstadt"
        let window = makeWindow(EditorForm().environment(model), size: CGSize(width: 440, height: 360), appearance: .aqua)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        let button = try #require(window.contentView.flatMap { findButton(titled: L10n.string("Choose Contact …"), in: $0) })
        #expect(!button.isHidden)
        let image = try snapshot(of: try #require(window.contentView?.superview))
        #expect(distinctColors(image) > 1)
        try saveIfRequested(image, name: "address-light")
    }

    // MARK: Helpers

    @MainActor
    private func check(_ model: AppModel, name: String, expectsPaper: Bool = true) async throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let window = makeWindow(model, appearance: appearance)
            try await Task.sleep(for: .milliseconds(400))
            let view = try #require(window.contentView?.superview ?? window.contentView)
            let image = try snapshot(of: view)
            #expect(image.pixelsWide > 0 && image.pixelsHigh > 0)
            if expectsPaper {
                #expect(hasBlackPixel(image, inRight: 0.55), "\(name): no black ink in the preview area")
            } else {
                #expect(distinctColors(image) > 1, "\(name) rendered blank")
            }
            try saveIfRequested(image, name: "\(name)-\(appearance == .aqua ? "light" : "dark")")
            window.close()
        }
    }
}

// MARK: - Shared helpers

@MainActor
private func makeWindow(_ model: AppModel, appearance: NSAppearance.Name) -> NSWindow {
    makeWindow(MainWindow().environment(model), size: CGSize(width: 980, height: 600), appearance: appearance)
}

@MainActor
private func findButton(titled prefix: String, in view: NSView) -> NSButton? {
    if let button = view as? NSButton, button.title.hasPrefix(prefix) { return button }
    for sub in view.subviews { if let found = findButton(titled: prefix, in: sub) { return found } }
    return nil
}
