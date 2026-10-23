import CoreGraphics
import Testing
@testable import LabelRender

@Suite struct GeometryTests {
    @Test func geometry11354() {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .text)
        #expect(g.rotation == .none)
        #expect(g.lengthLines == 375)
        #expect(Int(g.printableRect.width) == 651)
        #expect(g.printableRect == CGRect(x: 12, y: 18, width: 651, height: 339))
        #expect(g.readingSizePoints.width == 651 * 72.0 / 300)
        #expect(g.readingSizePoints.height == 339 * 72.0 / 300)
    }

    @Test func geometry600lpiDoublesLines() {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .graphics)
        #expect(g.lengthLines == 750)
        #expect(g.printableRect == CGRect(x: 12, y: 36, width: 651, height: 678))
        // Reading size in points does not depend on lpi.
        #expect(g.readingSizePoints == LabelGeometry(roll: r11354, headDots: 672, quality: .text).readingSizePoints)
    }

    @Test func addressIsRotated() {
        let g = LabelGeometry(roll: r99010, headDots: 672, quality: .text)
        #expect(g.rotation == .clockwise90)
        // Reading size swaps: feed length becomes reading width.
        #expect(g.readingSizePoints.width == 963 * 72.0 / 300)
        #expect(g.readingSizePoints.height == 299 * 72.0 / 300)
    }

    // Note: `rotation: .none` would bind to `Optional.none` (= default); spell out the type.
    @Test func explicitRotationOverridesDefault() {
        #expect(LabelGeometry(roll: r99010, headDots: 672, quality: .text, rotation: ReadingRotation.none).rotation == .none)
    }

    @Test func continuousRollUsesLengthAndClampsToHead() {
        let g = LabelGeometry(roll: rContinuous62, headDots: 672, quality: .text)
        #expect(g.rotation == .none)
        #expect(g.lengthLines == Int((50 / 25.4 * 300).rounded()))
        // Ruling 8: x = min(offset + originAcross, headDots - widthDots) = min(35, 10).
        #expect(g.printableRect == CGRect(x: 10, y: 0, width: 662, height: CGFloat(g.lengthLines)))
        let g2 = LabelGeometry(roll: rContinuous62, headDots: 672, quality: .graphics, continuousLengthMM: 100)
        #expect(g2.lengthLines == Int((100 / 25.4 * 600).rounded()))
    }

    @Test(arguments: [ReadingRotation.none, .clockwise90, .upsideDown, .counterClockwise90])
    func headTransformMapsCornersOntoPrintableRect(rotation: ReadingRotation) {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .graphics, rotation: rotation)
        let t = g.headTransform()
        let s = g.readingSizePoints
        let mapped = CGRect(origin: .zero, size: s).applying(t)
        #expect(abs(mapped.minX - g.printableRect.minX) < 1e-6)
        #expect(abs(mapped.maxX - g.printableRect.maxX) < 1e-6)
        #expect(abs(mapped.minY - g.printableRect.minY) < 1e-6)
        #expect(abs(mapped.maxY - g.printableRect.maxY) < 1e-6)
    }

    @Test func clockwiseMappingMatchesConvention() {
        let g = LabelGeometry(roll: r99010, headDots: 672, quality: .graphics)
        let p = CGPoint(x: 10, y: 20).applying(g.headTransform())
        let r = g.printableRect
        #expect(abs(p.x - (r.maxX - 20 * 300 / 72)) < 1e-9)
        #expect(abs(p.y - (r.minY + 10 * 600 / 72)) < 1e-9)
    }
}
