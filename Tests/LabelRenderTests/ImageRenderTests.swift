import CoreGraphics
import Foundation
import LabelProtocol
import Testing
@testable import LabelRender

@Suite struct ImageRenderTests {
    /// An image with the printable area's aspect ratio fills it completely.
    func fillingImage(_ g: LabelGeometry, gray: UInt8, alpha: UInt8 = 255) -> CGImage {
        let s = g.readingSizePoints
        return uniformImage(width: Int(s.width * 2), height: Int(s.height * 2), gray: gray, alpha: alpha)
    }

    @Test func grayImageIsDithered() throws {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .text)
        let r = g.printableRect
        let dithered = try LabelRenderer.render(.image(.init(image: fillingImage(g, gray: 128), dither: true)), geometry: g)
        let f = blackFraction(dithered.bitmap, in: r)
        #expect(f > 0.35 && f < 0.65, "black fraction \(f)")
        let plain = try LabelRenderer.render(.image(.init(image: fillingImage(g, gray: 128), dither: false)), geometry: g)
        #expect(blackFraction(plain.bitmap, in: r) == 0)
        let dark = try LabelRenderer.render(.image(.init(image: fillingImage(g, gray: 127), dither: false)), geometry: g)
        #expect(blackFraction(dark.bitmap, in: r.insetBy(dx: 1, dy: 1)) == 1)
        #expect(!dithered.overflow)
    }

    @Test func nothingOutsidePrintableArea() throws {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .graphics)
        let res = try LabelRenderer.render(.image(.init(image: fillingImage(g, gray: 40))), geometry: g)
        let ink = inkBounds(res.bitmap)!, r = g.printableRect
        #expect(ink.minX >= Int(r.minX) && ink.maxX < Int(r.maxX) && ink.minY >= Int(r.minY) && ink.maxY < Int(r.maxY))
    }

    @Test func transparentPixelsAreWhite() throws {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .text)
        let res = try LabelRenderer.render(.image(.init(image: fillingImage(g, gray: 0, alpha: 0))), geometry: g)
        #expect(inkBounds(res.bitmap) == nil)
    }

    /// A square black image on a wide label: aspect kept, centred.
    @Test func aspectFitCentred() throws {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .text)
        let res = try LabelRenderer.render(.image(.init(image: uniformImage(width: 50, height: 50, gray: 0), dither: false)), geometry: g)
        let ink = inkBounds(res.bitmap)!, r = g.printableRect
        #expect(abs(ink.height - Int(r.height)) <= 1)
        #expect(abs(ink.width - ink.height) <= 2) // 300 × 300 dpi: square in dots
        #expect(abs((ink.minX + ink.maxX) / 2 - Int(r.midX)) <= 1)
    }

    @Test func rotatedImageIsPhysicallySquare() throws {
        let g = LabelGeometry(roll: r99010, headDots: 672, quality: .graphics)
        let res = try LabelRenderer.render(.image(.init(image: uniformImage(width: 50, height: 50, gray: 0), dither: false)), geometry: g)
        let ink = inkBounds(res.bitmap)!
        #expect(abs(ink.height - 2 * ink.width) <= 3) // lines at 600 lpi vs dots at 300 dpi
    }
}
