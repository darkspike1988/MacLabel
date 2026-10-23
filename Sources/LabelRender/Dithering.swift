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
}
