import CoreGraphics
import LabelProtocol

enum Dithering {
    /// Converts an 8-bit gray buffer (row-major, 0 = black) to 1 bit: values < 128 become black.
    static func threshold(_ gray: UnsafeBufferPointer<UInt8>, width: Int, height: Int, bytesPerRow: Int) -> MonochromeBitmap {
        var bitmap = MonochromeBitmap(width: width, height: height)
        for y in 0..<height {
            let row = y * bytesPerRow
            for x in 0..<width where gray[row + x] < 128 {
                bitmap[x, y] = true
            }
        }
        return bitmap
    }

    /// Floyd–Steinberg error diffusion inside `rect`; everything outside stays white.
    static func floydSteinberg(_ gray: UnsafeBufferPointer<UInt8>, width: Int, height: Int, bytesPerRow: Int,
                               in rect: CGRect) -> MonochromeBitmap {
        var bitmap = MonochromeBitmap(width: width, height: height)
        let x0 = max(0, Int(rect.minX)), x1 = min(width, Int(rect.maxX))
        let y0 = max(0, Int(rect.minY)), y1 = min(height, Int(rect.maxY))
        guard x0 < x1, y0 < y1 else { return bitmap }
        let w = x1 - x0
        // Current and next row with one guard cell on each side.
        var current = [Int](repeating: 0, count: w + 2), next = current
        for y in y0..<y1 {
            for i in 0..<w { current[i + 1] += Int(gray[y * bytesPerRow + x0 + i]) }
            for i in 0..<w {
                let value = current[i + 1]
                let black = value < 128
                if black { bitmap[x0 + i, y] = true }
                let error = value - (black ? 0 : 255)
                current[i + 2] += error * 7 / 16
                next[i] += error * 3 / 16
                next[i + 1] += error * 5 / 16
                next[i + 2] += error / 16
            }
            swap(&current, &next)
            for i in next.indices { next[i] = 0 }
        }
        return bitmap
    }
}
