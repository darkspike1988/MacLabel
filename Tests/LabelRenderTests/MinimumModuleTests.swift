import LabelMedia
import LabelProtocol
import Testing
@testable import LabelRender

/// Ruling 30: physical minimum X-dimension. 1D modules ≥ 2 dots (≈0.17 mm), QR modules ≥ 3 dots;
/// below that the code is rendered at the minimum and flagged as overflow.
@Suite struct MinimumModuleTests {
    @Test func longCode128On11354KeepsMinimumOrOverflows() throws {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .graphics)
        let value = String(repeating: "Ab", count: 15) // 30 characters
        let res = try LabelRenderer.render(.barcode(.init(symbology: .code128, value: value, showText: false)), geometry: g)
        let runs = runLengthsAcross(res.bitmap, y: res.bitmap.height / 2)
        #expect(runs.min()! >= 2)
        let modules = try Barcode.modules(.code128, value).count + 2 * BarcodeLayout.quietModules
        #expect(res.overflow == (modules * 2 > Int(g.printableRect.width)))
        #expect(res.overflow || runs.min()! >= 2)
    }

    @Test func longCode128OnNarrowRotatedAddressRollOverflows() throws {
        let g = LabelGeometry(roll: r99010, headDots: 672, quality: .graphics, rotation: .clockwise90)
        let res = try LabelRenderer.render(
            .barcode(.init(symbology: .code128, value: String(repeating: "X", count: 50), showText: false)), geometry: g)
        #expect(res.overflow)
        // Modules along the feed are at least 2 dots = 4 lines at 600 lpi.
        let x = Int(g.printableRect.midX)
        let column = (0..<res.bitmap.height).map { res.bitmap[x, $0] }
        #expect(minRun(column) >= 4)
    }

    @Test func shortCode128StillFitsWithoutOverflow() throws {
        let g = LabelGeometry(roll: r99010, headDots: 672, quality: .graphics, rotation: .clockwise90)
        let res = try LabelRenderer.render(.barcode(.init(symbology: .code128, value: "Box 08")), geometry: g)
        #expect(!res.overflow)
    }

    @Test func denseQRKeepsThreeDotModulesAndOverflows() throws {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .graphics)
        let payload = String(repeating: "https://example.com/", count: 50)
        let res = try LabelRenderer.render(.qr(.init(payload: payload)), geometry: g)
        let q = qrModuleSize(res.bitmap)
        #expect(q.acrossDots >= 3)
        #expect(q.feedLines >= 6)
        #expect(res.overflow)
    }

    private func minRun(_ values: [Bool]) -> Int {
        guard let first = values.firstIndex(of: true), let last = values.lastIndex(of: true) else { return 0 }
        var runs: [Int] = [], current = true, length = 0
        for v in values[first...last] {
            if v == current { length += 1 } else { runs.append(length); current = v; length = 1 }
        }
        runs.append(length)
        return runs.min()!
    }
}
