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

    private func qrDoc(_ csv: String? = nil) throws -> LabelDocument {
        var d = LabelDocument(); d.layout = .qr
        if let csv { d.csv = try CSVTable(parsing: csv) }
        return d
    }

    private func payloads(_ d: LabelDocument) throws -> [String] {
        try d.contents().map { if case .qr(let q) = $0 { q.payload } else { "" } }
    }

    @Test func literalBracesInWifiPasswordSurvive() throws {
        var d = try qrDoc(); d.qrKind = .wifi; d.wifiSSID = "N"; d.wifiPassword = "pa{ss}word"
        #expect(try payloads(d) == ["WIFI:T:WPA;S:N;P:pa{ss}word;;"])
    }

    @Test func csvValueIsEscapedInPayload() throws {
        var d = try qrDoc("Pass\n\"a;b\"\n"); d.qrKind = .wifi; d.wifiSSID = "N"; d.wifiPassword = "{Pass}"
        #expect(try payloads(d) == [#"WIFI:T:WPA;S:N;P:a\;b;;"#])
    }

    @Test func urlPlaceholderNoDoubleScheme() throws {
        var d = try qrDoc("url\nhttp://x.de\n"); d.qrKind = .url; d.qrText = "{url}"
        #expect(try payloads(d) == ["http://x.de"])
    }

    @Test func counterAndCaptionSubstituted() throws {
        var d = try qrDoc(); d.qrText = "id{n}"; d.qrCaption = "#{n}"; d.copies = 2; d.counter = CounterSpec(start: 5)
        #expect(try payloads(d) == ["id5", "id6"])
        guard case .qr(let q) = try d.contents()[1] else { Issue.record("x"); return }
        #expect(q.caption == "#6")
    }

    @Test func limitDoesNotExpandEverything() throws {
        var csv = "A\n"
        for i in 0..<10_000 { csv += "r\(i)\n" }
        var d = LabelDocument(); d.text = "{A}"; d.copies = 2; d.csv = try CSVTable(parsing: csv)
        let start = ContinuousClock.now
        let c = try d.contents(limit: 50)
        #expect(c.count == 50)
        #expect(ContinuousClock.now - start < .milliseconds(500))
        guard case .text(let t) = c[49] else { Issue.record("x"); return }
        #expect(t.text == "r24")
    }

    @Test func negativeLimitIsEmpty() throws {
        var d = LabelDocument(); d.text = "x"
        #expect(try d.contents(limit: -1).isEmpty)
    }

    @Test func labelCountThrowsLikeContents() throws {
        var d = LabelDocument(); d.text = "x"; d.copies = 0
        #expect(throws: BatchError.invalidCopies) { try d.labelCount() }
        var e = LabelDocument(); e.text = "x"; e.csv = try CSVTable(parsing: "A\n")
        #expect(throws: DocumentError.emptyCSV) { try e.labelCount() }
        #expect(throws: DocumentError.emptyCSV) { try e.contents() }
    }
}
