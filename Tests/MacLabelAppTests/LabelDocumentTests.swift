import CoreGraphics
import LabelRender
import MacLabelKit
import Testing
@testable import MacLabelApp

@Suite struct LabelDocumentTests {
    @Test func addressIsLeading() throws {
        var d = LabelDocument(); d.layout = .address; d.addressText = "A\nB"
        guard case .text(let t) = try d.template() else { Issue.record("not text"); return }
        #expect(t.alignment == .leading && t.text == "A\nB")
    }

    @Test func csvTimesCopiesCount() throws {
        var d = LabelDocument(); d.text = "{Name}"; d.copies = 2
        d.csv = try CSVTable(parsing: "Name\nA\nB\nC\n")
        #expect(try d.labelCount() == 6)
    }

    @Test func limitCapsContents() throws {
        var d = LabelDocument(); d.text = "x"; d.copies = 500
        #expect(try d.contents(limit: 50).count == 50)
    }

    @Test func imageMissing() {
        var d = LabelDocument(); d.layout = .image
        #expect(throws: DocumentError.missingImage) { try d.template() }
    }

    @Test func placeholderNames() throws {
        var d = LabelDocument(); d.csv = try CSVTable(parsing: "Name;Ort\nA;B\n"); d.counter = CounterSpec()
        #expect(d.placeholderNames() == ["Name", "Ort", "n"])
    }

    @Test func qrTemplateUsesPayloadAndCaption() throws {
        var d = LabelDocument(); d.layout = .qr; d.qrKind = .url; d.qrText = "example.com"; d.qrCaption = "Hi"
        guard case .qr(let q) = try d.template() else { Issue.record("not qr"); return }
        #expect(q.payload == "https://example.com" && q.caption == "Hi")
    }

    @Test func imageEqualityIsIdentity() throws {
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        let a = ctx.makeImage()!, b = ctx.makeImage()!
        var d1 = LabelDocument(), d2 = LabelDocument()
        d1.image = a; d2.image = a
        #expect(d1 == d2)
        d2.image = b
        #expect(d1 != d2)
    }

    @Test func documentErrorTextsAreLocalized() {
        #expect(DocumentError.missingImage.text(bundle: localizedBundle(preferred: ["de"])) == "Wähle zuerst ein Bild aus.")
        #expect(DocumentError.missingImage.text(bundle: localizedBundle(preferred: ["en"])) == "Choose a picture first.")
        #expect(DocumentError.emptyCSV.text(bundle: localizedBundle(preferred: ["de"])).contains("CSV"))
    }
}
