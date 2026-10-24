import LabelMedia
import LabelProtocol
import Testing
@testable import MacLabelApp

@Suite struct PreviewEngineTests {
    private let roll = MediaCatalog.bundled.roll(id: "11354")!
    private let lw450 = PrinterModel.lookup(productID: 0x20)!

    @Test @MainActor func rendersFirstPage() async {
        let e = PreviewEngine(debounce: .zero)
        var d = LabelDocument(); d.text = "Keller"
        let r = await e.update(document: d, roll: roll, model: lw450)!
        #expect(r.pages.count == 1 && r.totalLabels == 1 && r.error == nil)
    }

    @Test @MainActor func newerCallSupersedesOlder() async {
        let e = PreviewEngine(debounce: .milliseconds(100))
        var a = LabelDocument(); a.text = "A"
        var b = a; b.text = "B"
        async let first = e.update(document: a, roll: roll, model: lw450)
        async let second = e.update(document: b, roll: roll, model: lw450)
        let (r1, r2) = await (first, second)
        #expect(r1 == nil)
        #expect(r2 != nil)
    }

    @Test @MainActor func capsPagesAtMax() async {
        // Debug renders cost ~60 ms/page, so the cap is exercised with a small maxPages (default is 50).
        let e = PreviewEngine(debounce: .zero, maxPages: 5)
        var d = LabelDocument(); d.text = "x"; d.copies = 120
        let r = await e.update(document: d, roll: roll, model: lw450)!
        #expect(r.pages.count == 5 && r.totalLabels == 120 && r.error == nil)
    }

    @Test @MainActor func overflowReported() async {
        let e = PreviewEngine(debounce: .zero)
        var d = LabelDocument(); d.text = String(repeating: "Überlauf ", count: 200)
        let r = await e.update(document: d, roll: roll, model: lw450)!
        #expect(r.overflowIndices == [0] && r.pages.count == 1 && r.error == nil)
    }

    @Test @MainActor func emptyTextIsError() async {
        let e = PreviewEngine(debounce: .zero)
        let r = await e.update(document: LabelDocument(), roll: roll, model: lw450)!
        #expect(r.error != nil && r.pages.isEmpty)
    }

    @Test @MainActor func missingRollIsError() async {
        let e = PreviewEngine(debounce: .zero)
        var d = LabelDocument(); d.text = "x"
        let r = await e.update(document: d, roll: nil, model: lw450)!
        #expect(r.error != nil && r.pages.isEmpty)
    }

    @Test @MainActor func invalidBarcodeIsError() async {
        let e = PreviewEngine(debounce: .zero)
        var d = LabelDocument(); d.layout = .barcode; d.symbology = .ean13; d.barcodeValue = "abc"
        let r = await e.update(document: d, roll: roll, model: lw450)!
        #expect(r.error != nil && r.pages.isEmpty)
    }

    @Test @MainActor func missingImageIsError() async {
        let e = PreviewEngine(debounce: .zero)
        var d = LabelDocument(); d.layout = .image
        let r = await e.update(document: d, roll: roll, model: lw450)!
        #expect(r.error != nil && r.pages.isEmpty)
    }

    @Test @MainActor func firstPageDeliveredBeforeFinalResult() async {
        let e = PreviewEngine(debounce: .zero, maxPages: 5)
        var d = LabelDocument(); d.text = "x"; d.copies = 120
        var order: [String] = []
        var first: PreviewResult?
        let final = await e.update(document: d, roll: roll, model: lw450) { r in
            order.append("first"); first = r
        }
        order.append("final")
        #expect(order == ["first", "final"])
        #expect(first?.pages.count == 1 && first?.totalLabels == 120)
        #expect(final?.pages.count == 5)
    }

    @Test @MainActor func errorKeepsTotalLabels() async {
        let e = PreviewEngine(debounce: .zero)
        var d = LabelDocument(); d.layout = .barcode; d.symbology = .ean13; d.barcodeValue = "abc"; d.copies = 7
        let r = await e.update(document: d, roll: roll, model: lw450)!
        #expect(r.error != nil && r.totalLabels == 7)
    }
}
