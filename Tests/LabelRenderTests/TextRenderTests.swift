import CoreGraphics
import Foundation
import LabelProtocol
import Testing
@testable import LabelRender

@Suite struct TextRenderTests {
    @Test func textFitsAndIsCentered() throws {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .text)
        let res = try LabelRenderer.render(.text(.init(text: "Keller")), geometry: g)
        #expect(!res.overflow)
        #expect(res.bitmap.width == 672 && res.bitmap.height == 375)
        let ink = inkBounds(res.bitmap)!
        #expect(ink.minX >= Int(g.printableRect.minX))
        #expect(ink.maxX < Int(g.printableRect.maxX))
        #expect(abs((ink.minX + ink.maxX) / 2 - Int(g.printableRect.midX)) <= 3)
        #expect(abs((ink.minY + ink.maxY) / 2 - Int(g.printableRect.midY)) <= 30)
        #expect(ink.width > 400) // auto-fit makes it big
    }

    @Test(arguments: ["Keller\r\nBox 3", "Keller\rBox 3", "Keller\u{2028}Box 3"])
    func otherLineBreaksSplitLikeLF(text: String) throws {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .text)
        let lf = try LabelRenderer.render(.text(.init(text: "Keller\nBox 3")), geometry: g).bitmap
        let other = try LabelRenderer.render(.text(.init(text: text)), geometry: g).bitmap
        #expect(other == lf)
        // Two separated ink bands along the feed.
        let ink = inkBounds(lf)!
        let blank = (ink.minY...ink.maxY).filter { lf.isRowBlank($0) }
        #expect(!blank.isEmpty)
    }

    /// Stacked diacritics and fallback-font glyphs rise above the base font's ascent;
    /// they must still be fully inside the printable area (or overflow is reported).
    @Test(arguments: ["\u{C9}\u{302}", "\u{E01}\u{E4C}\u{E48}", "\u{C9}\u{302}\nq\u{327}\u{328}"])
    func tallGlyphInkIsNotClipped(text: String) throws {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .text)
        let res = try LabelRenderer.render(.text(.init(text: text)), geometry: g)
        #expect(!res.overflow)
        let ink = inkBounds(res.bitmap)!
        let r = g.printableRect
        #expect(ink.minY > Int(r.minY) && ink.maxY < Int(r.maxY) - 1)
        #expect(ink.minX > Int(r.minX) && ink.maxX < Int(r.maxX) - 1)
    }

    @Test func longTextOverflows() throws {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .text)
        let res = try LabelRenderer.render(.text(.init(text: String(repeating: "Sehr langer Text ", count: 40))), geometry: g)
        #expect(res.overflow)
        // Clipped to the printable area, never outside.
        let ink = inkBounds(res.bitmap)!
        #expect(ink.minX >= Int(g.printableRect.minX) && ink.maxX < Int(g.printableRect.maxX))
        #expect(ink.minY >= Int(g.printableRect.minY) && ink.maxY < Int(g.printableRect.maxY))
    }

    @Test func emptyTextRejected() {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .text)
        #expect(throws: RenderError.emptyContent) { try LabelRenderer.render(.text(.init(text: "  \n ")), geometry: g) }
    }

    @Test func rotatedTextInkIsTallerThanWideOnHead() throws {
        let g = LabelGeometry(roll: r99010, headDots: 672, quality: .text)
        let ink = inkBounds(try LabelRenderer.render(.text(.init(text: "Max Mustermann")), geometry: g).bitmap)!
        #expect(ink.height > ink.width)
    }

    @Test func previewIsReadingOriented() throws {
        let g = LabelGeometry(roll: r99010, headDots: 672, quality: .text)
        let p = try LabelRenderer.render(.text(.init(text: "Max")), geometry: g).preview
        #expect(p.width > p.height)
        #expect(p.width == 1050 && p.height == 327) // whole label at 300 dpi
    }

    @Test func graphicsPreviewIs300dpi() throws {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .graphics)
        let res = try LabelRenderer.render(.text(.init(text: "Keller")), geometry: g)
        #expect(res.bitmap.height == 750)
        #expect(res.quality == .graphics)
        #expect(res.preview.width == 672 && res.preview.height == 375)
    }

    @Test func previewMatchesRasterForUpright() throws {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .text)
        let res = try LabelRenderer.render(.text(.init(text: "Keller")), geometry: g)
        let a = inkBounds(res.bitmap)!, b = inkBounds(res.preview)!
        #expect(a.minX == b.minX && a.maxX == b.maxX && a.minY == b.minY && a.maxY == b.maxY)
    }

    /// The first line of a two-line text must appear on the reading top, i.e. on the
    /// head's right side for `.clockwise90`, and in the preview's upper half.
    @Test func rotatedReadingOrderIsCorrect() throws {
        let g = LabelGeometry(roll: r99010, headDots: 672, quality: .text)
        let res = try LabelRenderer.render(.text(.init(text: "WWWWWWWW\n.")), geometry: g)
        let ink = inkBounds(res.bitmap)!
        // Long first line spans more feed lines and sits at larger x than the dot.
        var colsWithInkRight = 0, colsWithInkLeft = 0
        let mid = (ink.minX + ink.maxX) / 2
        for y in 0..<res.bitmap.height { for x in ink.minX...ink.maxX where res.bitmap[x, y] {
            if x > mid { colsWithInkRight += 1 } else { colsWithInkLeft += 1 }
        } }
        #expect(colsWithInkRight > colsWithInkLeft * 3)
        let p = inkBounds(res.preview)!
        #expect(p.width > p.height)
    }

    @Test func boldIsHeavier() throws {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .text)
        func count(_ bold: Bool) throws -> Int {
            let b = try LabelRenderer.render(.text(.init(text: "iiii", bold: bold)), geometry: g).bitmap
            var n = 0
            for y in 0..<b.height { for x in 0..<b.width where b[x, y] { n += 1 } }
            return n
        }
        #expect(try count(true) > count(false))
    }

    @Test func alignmentLeadingAndTrailing() throws {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .text)
        let lead = inkBounds(try LabelRenderer.render(.text(.init(text: "A\nBBBBBBBB", alignment: .leading)), geometry: g).bitmap)!
        let trail = inkBounds(try LabelRenderer.render(.text(.init(text: "A\nBBBBBBBB", alignment: .trailing)), geometry: g).bitmap)!
        #expect(lead.minX - Int(g.printableRect.minX) <= 3)
        #expect(Int(g.printableRect.maxX) - 1 - trail.maxX <= 3)
    }

    @Test func nonTextContentUnsupportedForNow() {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .text)
        #expect(throws: RenderError.unsupported) {
            try LabelRenderer.render(.barcode(.init(symbology: .code128, value: "A")), geometry: g)
        }
        #expect(throws: RenderError.unsupported) { try LabelRenderer.render(.qr(.init(payload: "x")), geometry: g) }
    }

    @Test func preferredQuality() {
        let lw450 = PrinterModel.all.first { $0.supports600lpi }!
        let lw550 = PrinterModel.all.first { !$0.supports600lpi }!
        #expect(LabelRenderer.preferredQuality(for: .text(.init(text: "x")), model: lw450) == .text)
        #expect(LabelRenderer.preferredQuality(for: .qr(.init(payload: "x")), model: lw450) == .graphics)
        #expect(LabelRenderer.preferredQuality(for: .barcode(.init(symbology: .ean13, value: "1")), model: lw550) == .text)
    }

    /// Writes sample previews when `MACLABEL_PREVIEW_DIR` is set.
    @Test func writeSamplePreviews() throws {
        guard let dir = ProcessInfo.processInfo.environment["MACLABEL_PREVIEW_DIR"] else { return }
        let base = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let a = try LabelRenderer.render(.text(.init(text: "Keller\nBox 3")),
                                         geometry: LabelGeometry(roll: r11354, headDots: 672, quality: .text))
        try writePNG(a.preview, to: base.appendingPathComponent("11354-keller.png"))
        let b = try LabelRenderer.render(.text(.init(text: "Max Mustermann\nMusterstraße 1\n12345 Musterstadt", alignment: .leading)),
                                         geometry: LabelGeometry(roll: r99010, headDots: 672, quality: .text))
        try writePNG(b.preview, to: base.appendingPathComponent("99010-address.png"))
    }
}
