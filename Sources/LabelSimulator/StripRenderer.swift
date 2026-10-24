import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Renders the physical label strip: grey backing paper, white rounded labels, the sense holes
/// (schematic, dark outline at the left edge) and every printed dot, at 600 px per inch in both
/// directions so 600-lpi lines are 1 px and 300-lpi lines 2 px tall (true aspect ratio).
public enum StripRenderer {
    public static let pixelsPerMM = 600 / 25.4
    public static let marginPixels = 40

    static let backing: UInt8 = 190
    static let label: UInt8 = 255
    static let hole: UInt8 = 90
    static let ink: UInt8 = 0
    static let jobTick: UInt8 = 60

    public static func render(_ result: SimulationResult) -> CGImage {
        let m = result.model
        let s = pixelsPerMM
        let lastInk = result.rows.map { $0.positionMM + $0.heightMM }.max() ?? 0
        let extent = max(lastInk, result.finalPositionMM, result.labels.map(\.pageStartMM).max() ?? 0)
        let labelCount = max(1, Int((extent / m.pitchMM).rounded(.down)) + 1)
        let firstY = min(0, result.rows.map(\.positionMM).min() ?? 0)
        let lengthMM = Double(labelCount) * m.pitchMM - firstY
        let width = Int((m.labelWidthMM * s).rounded(.up)) + 2 * marginPixels
        let height = Int((lengthMM * s).rounded(.up)) + 2 * marginPixels
        var buffer = [UInt8](repeating: backing, count: width * height)

        func py(_ mm: Double) -> Int { Int(((mm - firstY) * s).rounded()) + marginPixels }
        func px(_ mm: Double) -> Int { Int((mm * s).rounded()) + marginPixels }
        func fill(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ v: UInt8) {
            let xa = max(0, x0), xb = min(width, x1), ya = max(0, y0), yb = min(height, y1)
            guard xa < xb, ya < yb else { return }
            for y in ya..<yb { for x in xa..<xb { buffer[y * width + x] = v } }
        }

        // Labels with rounded corners.
        let r = m.cornerRadiusMM * s
        for k in 0..<labelCount {
            let top = m.leadingEdgeMM(label: k)
            let x0 = px(0), x1 = px(m.labelWidthMM), y0 = py(top), y1 = py(top + m.labelLengthMM)
            for y in max(0, y0)..<min(height, y1) {
                for x in x0..<x1 {
                    let cx = Double(x) < Double(x0) + r ? Double(x0) + r : (Double(x) > Double(x1) - r ? Double(x1) - r : Double(x))
                    let cy = Double(y) < Double(y0) + r ? Double(y0) + r : (Double(y) > Double(y1) - r ? Double(y1) - r : Double(y))
                    let dx = Double(x) - cx, dy = Double(y) - cy
                    if dx * dx + dy * dy <= r * r { buffer[y * width + x] = label }
                }
            }
            // Sense hole outline (schematic: 3 mm × 1.5 mm, 1 mm from the left edge).
            let hy = m.leadingEdgeMM(label: k) + m.senseHoleOffsetMM
            let hx0 = px(1), hx1 = px(4), hy0 = py(hy - 0.75), hy1 = py(hy + 0.75)
            fill(hx0, hy0, hx1, hy0 + 2, hole); fill(hx0, hy1 - 2, hx1, hy1, hole)
            fill(hx0, hy0, hx0 + 2, hy1, hole); fill(hx1 - 2, hy0, hx1, hy1, hole)
        }

        // Ink: head centred on the label.
        let headOffsetMM = (m.labelWidthMM - Double(m.headDots) * MechanicalModel.step300MM) / 2
        for row in result.rows {
            let y0 = py(row.positionMM), y1 = py(row.positionMM + row.heightMM)
            for (i, byte) in row.bits.enumerated() where byte != 0 {
                for bit in 0..<8 where byte & (0x80 >> UInt8(bit)) != 0 {
                    let dot = row.firstDot + i * 8 + bit
                    let xa = headOffsetMM + Double(dot) * MechanicalModel.step300MM
                    fill(px(xa), y0, px(xa + MechanicalModel.step300MM), y1, ink)
                }
            }
        }

        // Job start ticks in the left margin.
        for job in result.jobs {
            let y = py(job.startMM)
            fill(4, y - 1, marginPixels - 6, y + 1, jobTick)
        }

        let provider = CGDataProvider(data: Data(buffer) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    /// 8-bit grey values of `image`, row-major.
    public static func grayPixels(_ image: CGImage) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: image.width * image.height)
        let ok = out.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return ok ? out : nil
    }

    public static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }
}

extension SimulationResult {
    public func renderStrip() -> CGImage { StripRenderer.render(self) }
}
