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

/// Run lengths (black and white alternating) along head row `y`, from the first to the
/// last black dot; leading and trailing white is not counted.
func runLengthsAcross(_ b: MonochromeBitmap, y: Int) -> [Int] {
    let xs = (0..<b.width).filter { b[$0, y] }
    guard let first = xs.first, let last = xs.last else { return [] }
    var runs: [Int] = [], current = b[first, y], length = 0
    for x in first...last {
        if b[x, y] == current { length += 1 } else { runs.append(length); current = b[x, y]; length = 1 }
    }
    runs.append(length)
    return runs
}

/// Smallest run length inside the QR symbol per head axis. The QR is the leftmost ink
/// cluster on the head (upright layout: QR left, caption right after a blank quiet zone).
func qrModuleSize(_ b: MonochromeBitmap) -> (acrossDots: Int, feedLines: Int) {
    let inkColumns = (0..<b.width).map { x in (0..<b.height).contains { b[x, $0] } }
    guard let x0 = inkColumns.firstIndex(of: true) else { return (0, 0) }
    let x1 = (x0..<b.width).first { !inkColumns[$0] } ?? b.width
    let rows = (0..<b.height).filter { y in (x0..<x1).contains { b[$0, y] } }
    guard let y0 = rows.first, let y1 = rows.last else { return (0, 0) }
    func minRun(_ values: [Bool]) -> Int {
        var best = Int.max, current = values[0], length = 0
        for v in values {
            if v == current { length += 1 } else { best = min(best, length); current = v; length = 1 }
        }
        return min(best, length)
    }
    let across = (y0...y1).map { y in minRun((x0..<x1).map { b[$0, y] }) }.min() ?? 0
    let feed = (x0..<x1).map { x in minRun((y0...y1).map { b[x, $0] }) }.min() ?? 0
    return (across, feed)
}

/// Fraction of black dots inside `rect` (head coordinates).
func blackFraction(_ b: MonochromeBitmap, in rect: CGRect) -> Double {
    var black = 0, total = 0
    for y in Int(rect.minY)..<Int(rect.maxY) { for x in Int(rect.minX)..<Int(rect.maxX) {
        total += 1
        if b[x, y] { black += 1 }
    } }
    return Double(black) / Double(max(total, 1))
}

/// A uniform image with one gray value and alpha (premultiplied RGBA when alpha < 255).
func uniformImage(width: Int, height: Int, gray: UInt8, alpha: UInt8 = 255) -> CGImage {
    if alpha == 255 {
        let data = Data(repeating: gray, count: width * height)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: CGDataProvider(data: data as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }
    let premultiplied = UInt8(Int(gray) * Int(alpha) / 255)
    var bytes: [UInt8] = []
    for _ in 0..<(width * height) { bytes += [premultiplied, premultiplied, premultiplied, alpha] }
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                   space: CGColorSpaceCreateDeviceRGB(),
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                   shouldInterpolate: false, intent: .defaultIntent)!
}
