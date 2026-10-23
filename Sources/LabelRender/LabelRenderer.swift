import CoreGraphics
import Foundation
import CoreText
import LabelProtocol

public struct RenderResult: Sendable {
    /// Head coordinates: width = headDots, height = lengthLines.
    public let bitmap: MonochromeBitmap
    /// Reading orientation, whole label, 300 dpi on both axes.
    public let preview: CGImage
    public let overflow: Bool
    public let quality: PrintQuality
}

public enum LabelRenderer {
    public static func render(_ content: LabelContent, geometry: LabelGeometry) throws -> RenderResult {
        switch content {
        case .text(let text):
            guard let layout = TextLayout(text, in: geometry.readingSizePoints) else { throw RenderError.emptyContent }
            let bitmap = rasterize(geometry) { ctx in
                for line in layout.lines {
                    ctx.saveGState()
                    // Reading space is y-down; Core Text draws y-up.
                    ctx.translateBy(x: line.x, y: line.baseline)
                    ctx.scaleBy(x: 1, y: -1)
                    ctx.textPosition = .zero
                    CTLineDraw(line.line, ctx)
                    ctx.restoreGState()
                }
            }
            return RenderResult(bitmap: bitmap, preview: preview(bitmap, geometry: geometry),
                                overflow: layout.overflow, quality: geometry.quality)
        case .barcode, .qr, .image:
            throw RenderError.unsupported
        }
    }

    public static func preferredQuality(for content: LabelContent, model: PrinterModel) -> PrintQuality {
        switch content {
        case .barcode, .qr: model.supports600lpi ? .graphics : .text
        case .text, .image: .text
        }
    }

    /// Draws in reading points into a white 8-bit head-sized context clipped to the
    /// printable area, then thresholds to 1 bit.
    static func rasterize(_ geometry: LabelGeometry, draw: (CGContext) -> Void) -> MonochromeBitmap {
        let width = geometry.headDots, height = geometry.lengthLines
        var gray = [UInt8](repeating: 255, count: width * height)
        return gray.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { preconditionFailure("cannot create gray bitmap context \(width)×\(height)") }
            // Head space: memory row 0 (top of CG's y-up space) is head line 0.
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            ctx.clip(to: geometry.printableRect)
            ctx.concatenate(geometry.headTransform())
            ctx.setFillColor(gray: 0, alpha: 1)
            draw(ctx)
            ctx.flush()
            return Dithering.threshold(UnsafeBufferPointer(buf.bindMemory(to: UInt8.self)),
                                       width: width, height: height, bytesPerRow: width)
        }
    }

    /// Turns the head raster back into reading orientation at 300 dpi (every second
    /// line is dropped at 600 lpi), cropped to the label.
    static func preview(_ bitmap: MonochromeBitmap, geometry: LabelGeometry) -> CGImage {
        let f = geometry.quality.linesPerInch / 300
        let x0 = Int(geometry.labelRect.minX), w = Int(geometry.labelRect.width)
        let lines = geometry.lengthLines / f
        let rotated = geometry.rotation == .clockwise90 || geometry.rotation == .counterClockwise90
        let pw = rotated ? lines : w, ph = rotated ? w : lines
        var pixels = [UInt8](repeating: 255, count: pw * ph)
        for py in 0..<ph {
            for px in 0..<pw {
                let (x, line): (Int, Int)
                switch geometry.rotation {
                case .none: (x, line) = (x0 + px, py)
                case .clockwise90: (x, line) = (x0 + w - 1 - py, px)
                case .upsideDown: (x, line) = (x0 + w - 1 - px, lines - 1 - py)
                case .counterClockwise90: (x, line) = (x0 + py, lines - 1 - px)
                }
                if bitmap[x, line * f] { pixels[py * pw + px] = 0 }
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: pw, height: ph, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: pw,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}
