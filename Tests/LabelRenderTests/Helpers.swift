import CoreGraphics
import Foundation
import ImageIO
import LabelMedia
import LabelProtocol
import UniformTypeIdentifiers

/// Shared rolls used across render tests.
let r11354 = MediaCatalog.bundled.roll(id: "11354")!
let r99010 = MediaCatalog.bundled.roll(sku: "99010")!
let rContinuous62 = MediaCatalog.bundled.roll(id: "30270")!

/// Bounding box of all black dots, or `nil` for a blank bitmap.
func inkBounds(_ b: MonochromeBitmap) -> (minX: Int, maxX: Int, minY: Int, maxY: Int, width: Int, height: Int)? {
    var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
    for y in 0..<b.height where !b.isRowBlank(y) {
        for x in 0..<b.width where b[x, y] {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= 0 else { return nil }
    return (minX, maxX, minY, maxY, maxX - minX + 1, maxY - minY + 1)
}

/// Bounding box of all dark pixels (< 128) in an 8-bit gray image, or `nil`.
func inkBounds(_ image: CGImage) -> (minX: Int, maxX: Int, minY: Int, maxY: Int, width: Int, height: Int)? {
    let w = image.width, h = image.height
    var pixels = [UInt8](repeating: 255, count: w * h)
    let ok = pixels.withUnsafeMutableBytes { buf -> Bool in
        guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    guard ok else { return nil }
    var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
    for y in 0..<h { for x in 0..<w where pixels[y * w + x] < 128 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    guard maxX >= 0 else { return nil }
    return (minX, maxX, minY, maxY, maxX - minX + 1, maxY - minY + 1)
}

/// Writes `image` as PNG; used to produce sample previews on demand.
func writePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
}
