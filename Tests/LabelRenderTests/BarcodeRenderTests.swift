import CoreGraphics
import Foundation
import LabelMedia
import LabelProtocol
import Testing
@testable import LabelRender

@Suite struct BarcodeRenderTests {
    @Test func ean13BarsAreDotAligned() throws {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .graphics)
        let res = try LabelRenderer.render(.barcode(.init(symbology: .ean13, value: "4006381333931")), geometry: g)
        let runs = runLengthsAcross(res.bitmap, y: res.bitmap.height / 3)
        let unit = runs.min()!
        #expect(unit >= 2)
        #expect(runs.allSatisfy { $0 % unit == 0 })
        #expect(!res.overflow)
    }

    @Test func barcodeTooLongOverflows() throws {
        let narrow = MediaCatalog.bundled.rolls.filter { $0.kind == .dieCut }
            .min { $0.readingSizeMM.width < $1.readingSizeMM.width }!
        let g = LabelGeometry(roll: narrow, headDots: 672, quality: .graphics)
        #expect(try LabelRenderer.render(.barcode(.init(symbology: .code128, value: String(repeating: "X", count: 60))),
                                         geometry: g).overflow)
    }

    @Test func invalidBarcodeSurfaces() {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .graphics)
        #expect(throws: RenderError.barcode(.badCheckDigit)) {
            try LabelRenderer.render(.barcode(.init(symbology: .ean13, value: "4006381333932")), geometry: g)
        }
        #expect(throws: RenderError.barcode(.empty)) { try LabelRenderer.render(.qr(.init(payload: "")), geometry: g) }
    }

    /// Module width = floor(available / (modules + 20)), quiet zone 10 modules each side,
    /// barcode centred in the printable area.
    @Test func moduleWidthAndQuietZone() throws {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .graphics)
        let res = try LabelRenderer.render(.barcode(.init(symbology: .ean13, value: "4006381333931", showText: false)), geometry: g)
        let m = Int(g.printableRect.width) / (95 + 20)
        let runs = runLengthsAcross(res.bitmap, y: res.bitmap.height / 2)
        #expect(runs.min() == m)
        #expect(runs.reduce(0, +) == 95 * m)
        let ink = inkBounds(res.bitmap)!
        let left = ink.minX - Int(g.printableRect.minX), right = Int(g.printableRect.maxX) - 1 - ink.maxX
        #expect(left >= 10 * m && right >= 10 * m && abs(left - right) <= 1)
    }

    /// Bars span the full printable height without text; with text they stop at 80 %.
    @Test func barHeightAndTextBand() throws {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .graphics)
        let r = g.printableRect
        let plain = try LabelRenderer.render(.barcode(.init(symbology: .code128, value: "Box 08", showText: false)), geometry: g)
        let p = inkBounds(plain.bitmap)!
        #expect(p.minY == Int(r.minY) && p.maxY == Int(r.maxY) - 1)

        let withText = try LabelRenderer.render(.barcode(.init(symbology: .code128, value: "Box 08")), geometry: g)
        #expect(!withText.overflow)
        let barEnd = Int(r.minY) + Int(r.height * 0.8)
        // A bar column: black right down to the band, nothing in the band except text.
        let firstBar = inkBounds(withText.bitmap)!.minX
        #expect(withText.bitmap[firstBar, barEnd - 1])
        #expect(!withText.bitmap[firstBar, barEnd])
        let textRows = (barEnd..<Int(r.maxY)).filter { !withText.bitmap.isRowBlank($0) }
        #expect(!textRows.isEmpty)
    }

    /// Rotated: bars run across the head, modules are whole lines along the feed.
    @Test func rotatedBarcodeUsesLines() throws {
        let g = LabelGeometry(roll: r99010, headDots: 672, quality: .graphics, rotation: .clockwise90)
        let res = try LabelRenderer.render(.barcode(.init(symbology: .code128, value: "Box 08", showText: false)), geometry: g)
        #expect(!res.overflow)
        let x = Int(g.printableRect.midX)
        let column = (0..<res.bitmap.height).map { res.bitmap[x, $0] }
        let blackLines = column.indices.filter { column[$0] }
        var runs: [Int] = [], current = true, length = 0
        for v in column[blackLines.first!...blackLines.last!] {
            if v == current { length += 1 } else { runs.append(length); current = v; length = 1 }
        }
        runs.append(length)
        let unit = runs.min()!
        #expect(unit == Int(g.printableRect.height) / (try Barcode.modules(.code128, "Box 08").count + 20))
        #expect(runs.allSatisfy { $0 % unit == 0 })
        // Every head row in the bar region is either fully black or fully white across.
        let r = g.printableRect
        for y in blackLines.first!...blackLines.last! {
            let row = (Int(r.minX)..<Int(r.maxX)).map { res.bitmap[$0, y] }
            #expect(row.allSatisfy { $0 == row[0] })
        }
    }

    @Test func qrModulesSquareIn600lpi() throws {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .graphics)
        let res = try LabelRenderer.render(.qr(.init(payload: "https://example.com", caption: "Regal 4")), geometry: g)
        #expect(!res.overflow)
        let q = qrModuleSize(res.bitmap)
        #expect(q.acrossDots >= 1)
        #expect(q.feedLines == 2 * q.acrossDots)
    }

    @Test func qrWithCaptionSitsLeftAndCaptionRight() throws {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .text)
        let res = try LabelRenderer.render(.qr(.init(payload: "https://example.com", caption: "Regal 4")), geometry: g)
        let n = try QRMatrix.modules("https://example.com").count
        let m = min(Int(g.printableRect.width), Int(g.printableRect.height)) / (n + 4)
        let ink = inkBounds(res.bitmap)!
        #expect(ink.minX == Int(g.printableRect.minX) + 2 * m) // quiet zone of two modules
        #expect(ink.maxX > Int(g.printableRect.minX) + (n + 4) * m) // caption to the right
        #expect(qrModuleSize(res.bitmap) == (m, m))
    }

    @Test(arguments: [nil, "", "  "] as [String?])
    func qrWithoutCaptionIsCentred(caption: String?) throws {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .text)
        let res = try LabelRenderer.render(.qr(.init(payload: "https://example.com", caption: caption)), geometry: g)
        #expect(!res.overflow)
        let ink = inkBounds(res.bitmap)!, r = g.printableRect
        #expect(abs((ink.minX + ink.maxX) / 2 - Int(r.midX)) <= 1)
        #expect(abs((ink.minY + ink.maxY) / 2 - Int(r.midY)) <= 1)
        #expect(ink.width == ink.height)
    }

    @Test func preferredQuality() {
        let m = PrinterModel.lookup(productID: 0x20)!
        let old = PrinterModel.lookup(productID: 0x19)!
        let image = ImageContent(image: uniformImage(width: 4, height: 4, gray: 0))
        #expect(LabelRenderer.preferredQuality(for: .qr(.init(payload: "x")), model: m) == .graphics)
        #expect(LabelRenderer.preferredQuality(for: .barcode(.init(symbology: .ean8, value: "1")), model: m) == .graphics)
        #expect(LabelRenderer.preferredQuality(for: .image(image), model: m) == .graphics)
        #expect(LabelRenderer.preferredQuality(for: .text(.init(text: "x")), model: m) == .text)
        #expect(LabelRenderer.preferredQuality(for: .qr(.init(payload: "x")), model: old) == .text)
        #expect(LabelRenderer.preferredQuality(for: .image(image), model: old) == .text)
    }

    /// Writes sample previews when `MACLABEL_PREVIEW_DIR` is set.
    @Test func writeSamplePreviews() throws {
        guard let dir = ProcessInfo.processInfo.environment["MACLABEL_PREVIEW_DIR"] else { return }
        let base = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .graphics)
        try writePNG(try LabelRenderer.render(.barcode(.init(symbology: .ean13, value: "4006381333931")), geometry: g).preview,
                     to: base.appendingPathComponent("11354-ean13.png"))
        try writePNG(try LabelRenderer.render(.qr(.init(payload: "https://example.com", caption: "Regal 4")), geometry: g).preview,
                     to: base.appendingPathComponent("11354-qr-regal4.png"))
        let address = LabelGeometry(roll: r99010, headDots: 672, quality: .graphics)
        try writePNG(try LabelRenderer.render(.barcode(.init(symbology: .code128, value: "Box 08")), geometry: address).preview,
                     to: base.appendingPathComponent("99010-code128.png"))
    }
}
