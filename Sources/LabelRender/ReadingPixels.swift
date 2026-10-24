import CoreGraphics
import LabelProtocol

/// The printable area as an integer pixel grid in reading orientation. Each reading axis
/// keeps the head unit of the head axis it lies on (dots across, lines along the feed),
/// so a fill here is an exact rectangle of head pixels.
struct ReadingPixels {
    let geometry: LabelGeometry
    /// Extent along reading x / y, in head units of the respective axis.
    let width: Int, height: Int
    /// Head units per 300-dpi dot along reading x / y (2 on the feed axis at 600 lpi).
    let xUnitsPerDot: Int, yUnitsPerDot: Int
    private let xUnitsPerInch: Int, yUnitsPerInch: Int

    init(_ geometry: LabelGeometry) {
        self.geometry = geometry
        let r = geometry.printableRect, lpi = geometry.quality.linesPerInch
        switch geometry.rotation {
        case .upright, .upsideDown:
            (width, height) = (Int(r.width), Int(r.height))
            (xUnitsPerInch, yUnitsPerInch) = (300, lpi)
        case .clockwise90, .counterClockwise90:
            (width, height) = (Int(r.height), Int(r.width))
            (xUnitsPerInch, yUnitsPerInch) = (lpi, 300)
        }
        (xUnitsPerDot, yUnitsPerDot) = (xUnitsPerInch / 300, yUnitsPerInch / 300)
    }

    /// Sets the head pixels covering reading pixels `x × y` to black, clipped to the grid.
    func fill(_ bitmap: inout MonochromeBitmap, x: Range<Int>, y: Range<Int>) {
        let x = x.clamped(to: 0..<width), y = y.clamped(to: 0..<height)
        guard !x.isEmpty, !y.isEmpty else { return }
        let r = geometry.printableRect
        let minX = Int(r.minX), minY = Int(r.minY), maxX = Int(r.maxX), maxY = Int(r.maxY)
        let headX: Range<Int>, headY: Range<Int>
        // Must agree with LabelGeometry.headTransform().
        switch geometry.rotation {
        case .upright:
            (headX, headY) = (minX + x.lowerBound..<minX + x.upperBound, minY + y.lowerBound..<minY + y.upperBound)
        case .clockwise90:
            (headX, headY) = (maxX - y.upperBound..<maxX - y.lowerBound, minY + x.lowerBound..<minY + x.upperBound)
        case .upsideDown:
            (headX, headY) = (maxX - x.upperBound..<maxX - x.lowerBound, maxY - y.upperBound..<maxY - y.lowerBound)
        case .counterClockwise90:
            (headX, headY) = (minX + y.lowerBound..<minX + y.upperBound, maxY - x.upperBound..<maxY - x.lowerBound)
        }
        for hy in headY { for hx in headX { bitmap[hx, hy] = true } }
    }

    /// The reading-point rectangle covering reading pixels `x × y`.
    func points(x: Range<Int>, y: Range<Int>) -> CGRect {
        let sx = 72 / CGFloat(xUnitsPerInch), sy = 72 / CGFloat(yUnitsPerInch)
        return CGRect(x: CGFloat(x.lowerBound) * sx, y: CGFloat(y.lowerBound) * sy,
                      width: CGFloat(x.count) * sx, height: CGFloat(y.count) * sy)
    }
}
