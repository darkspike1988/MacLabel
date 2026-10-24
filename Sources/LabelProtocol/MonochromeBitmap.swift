/// 1-bit raster image. Rows are padded to whole bytes; MSB of each byte is the leftmost dot; 1 = black.
public struct MonochromeBitmap: Sendable, Equatable {
    public let width: Int
    public let height: Int
    private var storage: [UInt8]

    public var bytesPerRow: Int { (width + 7) / 8 }

    public init(width: Int, height: Int) {
        precondition(width >= 0 && height >= 0, "negative bitmap size")
        self.width = width
        self.height = height
        self.storage = [UInt8](repeating: 0, count: ((width + 7) / 8) * height)
    }

    public subscript(x: Int, y: Int) -> Bool {
        get {
            precondition(x >= 0 && x < width && y >= 0 && y < height, "pixel out of bounds")
            return storage[y * bytesPerRow + x / 8] & (0x80 >> UInt8(x % 8)) != 0
        }
        set {
            precondition(x >= 0 && x < width && y >= 0 && y < height, "pixel out of bounds")
            let index = y * bytesPerRow + x / 8
            let mask = UInt8(0x80) >> UInt8(x % 8)
            if newValue { storage[index] |= mask } else { storage[index] &= ~mask }
        }
    }

    public func row(_ y: Int) -> ArraySlice<UInt8> {
        precondition(y >= 0 && y < height, "row out of bounds")
        return storage[(y * bytesPerRow)..<((y + 1) * bytesPerRow)]
    }

    public func isRowBlank(_ y: Int) -> Bool {
        row(y).allSatisfy { $0 == 0 }
    }
}
