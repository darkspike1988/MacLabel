import CoreGraphics
import LabelMedia
import LabelProtocol

/// How the reading orientation is turned relative to the print head.
public enum ReadingRotation: Sendable {
    case upright, clockwise90, upsideDown, counterClockwise90
}

/// Geometry of one label in head coordinates (x = dot across, dot 0 = MSB of the first
/// byte; y = feed line, line 0 is sent first) and its reading orientation.
public struct LabelGeometry: Sendable {
    public let headDots: Int
    public let lengthLines: Int
    /// Printable area in head coordinates: x in dots, y in lines.
    public let printableRect: CGRect
    public let rotation: ReadingRotation
    /// Printable area in reading coordinates, in points (1/72").
    public let readingSizePoints: CGSize
    /// Whole label (die-cut) or label strip (continuous) in head coordinates, clipped to the head.
    let labelRect: CGRect
    let quality: PrintQuality

    public init(roll: LabelRoll, headDots: Int, quality: PrintQuality,
                rotation: ReadingRotation? = nil, continuousLengthMM: Double? = nil) {
        let lpi = quality.linesPerInch
        let p = roll.printable
        self.headDots = headDots
        self.quality = quality

        let x = max(0, min(roll.offsetDots + p.originAcrossDots, headDots - p.widthDots))
        let width = min(p.widthDots, headDots - x)
        if let feedDots = roll.feedDots, let feedMM = roll.feedMM {
            lengthLines = feedDots * lpi / 300
            let lengthDots = p.lengthDots ?? feedDots - p.originFeedDots
            printableRect = CGRect(x: x, y: p.originFeedDots * lpi / 300, width: width, height: lengthDots * lpi / 300)
            self.rotation = rotation ?? (roll.acrossMM >= feedMM ? .upright : .clockwise90)
        } else {
            lengthLines = Int(((continuousLengthMM ?? 50) / 25.4 * Double(lpi)).rounded())
            printableRect = CGRect(x: x, y: 0, width: width, height: lengthLines)
            self.rotation = rotation ?? .upright
        }

        let labelX = max(0, x - p.originAcrossDots)
        labelRect = CGRect(x: labelX, y: 0, width: min(roll.acrossDots, headDots - labelX), height: lengthLines)

        let acrossPt = printableRect.width * 72 / 300
        let feedPt = printableRect.height * 72 / CGFloat(lpi)
        switch self.rotation {
        case .upright, .upsideDown: readingSizePoints = CGSize(width: acrossPt, height: feedPt)
        case .clockwise90, .counterClockwise90: readingSizePoints = CGSize(width: feedPt, height: acrossPt)
        }
    }

    /// Maps reading points (origin top-left of the printable area, y down) to head pixels.
    public func headTransform() -> CGAffineTransform {
        let sx: CGFloat = 300.0 / 72
        let sy = CGFloat(quality.linesPerInch) / 72
        let r = printableRect
        switch rotation {
        case .upright:
            return CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: r.minX, ty: r.minY)
        case .clockwise90:
            return CGAffineTransform(a: 0, b: sy, c: -sx, d: 0, tx: r.maxX, ty: r.minY)
        case .upsideDown:
            return CGAffineTransform(a: -sx, b: 0, c: 0, d: -sy, tx: r.maxX, ty: r.maxY)
        case .counterClockwise90:
            return CGAffineTransform(a: 0, b: -sy, c: sx, d: 0, tx: r.minX, ty: r.maxY)
        }
    }
}
