public struct LWClassicJob: Sendable {
    public var labels: [MonochromeBitmap]
    /// `nil` means continuous (endless) media.
    public var labelLengthLines: Int?
    public var quality: PrintQuality
    public var density: PrintDensity
    public var twinRoll: TwinRoll?

    public init(
        labels: [MonochromeBitmap],
        labelLengthLines: Int?,
        quality: PrintQuality,
        density: PrintDensity,
        twinRoll: TwinRoll? = nil
    ) {
        self.labels = labels
        self.labelLengthLines = labelLengthLines
        self.quality = quality
        self.density = density
        self.twinRoll = twinRoll
    }
}

public enum LWClassicEncoder {
    public static let resync = [UInt8](repeating: 0x1B, count: 156)
    public static let betweenLabels: [UInt8] = [0x1B, 0x47]
    public static let endOfJob: [UInt8] = [0x1B, 0x45]
    public static let statusRequest: [UInt8] = [0x1B, 0x41]
    public static let versionRequest: [UInt8] = [0x1B, 0x56]
    /// `ESC @`: only used after an aborted job (with `resync`); never part of a normal header.
    public static let reset: [UInt8] = [0x1B, 0x40]

    public static func jobHeader(_ job: LWClassicJob) -> [UInt8] {
        var out = resync
        out += [0x1B, 0x51, 0x00, 0x00]
        out += [0x1B, 0x42, 0x00]
        out += [0x1B, job.quality == .text ? 0x68 : 0x69]
        let density: UInt8
        switch job.density {
        case .light: density = 0x63
        case .medium: density = 0x64
        case .normal: density = 0x65
        case .dark: density = 0x67
        }
        out += [0x1B, density]
        if let twin = job.twinRoll {
            let n: UInt8
            switch twin {
            case .auto: n = 0x30
            case .left: n = 0x31
            case .right: n = 0x32
            }
            out += [0x1B, 0x71, n]
        }
        return out
    }

    public static func label(_ bitmap: MonochromeBitmap, lengthLines: Int?) -> [UInt8] {
        let length = UInt16(clamping: lengthLines ?? 0xFFFF)
        var out: [UInt8] = [0x1B, 0x4C, UInt8(length >> 8), UInt8(length & 0xFF)]
        out += [0x1B, 0x44, UInt8(clamping: bitmap.bytesPerRow)]

        var blankRun = 0
        func flushBlank() {
            while blankRun > 0 {
                let k = min(blankRun, 255)
                out += [0x1B, 0x66, 0x01, UInt8(k)]
                blankRun -= k
            }
        }
        for y in 0..<bitmap.height {
            if bitmap.isRowBlank(y) {
                blankRun += 1
                continue
            }
            flushBlank()
            let row = bitmap.row(y)
            let rle = rleEncode(row)
            if rle.count < row.count {
                out.append(0x17)
                out += rle
            } else {
                out.append(0x16)
                out += row
            }
        }
        flushBlank()
        return out
    }

    public static func encode(_ job: LWClassicJob) -> [UInt8] {
        var out = jobHeader(job)
        for (i, bitmap) in job.labels.enumerated() {
            if i > 0 { out += betweenLabels }
            out += label(bitmap, lengthLines: job.labelLengthLines)
        }
        out += endOfJob
        return out
    }

    /// Runs over all `row.count * 8` pixels; each byte is `(black ? 0x80 : 0) | (len - 1)`, len <= 128.
    private static func rleEncode(_ row: ArraySlice<UInt8>) -> [UInt8] {
        var out: [UInt8] = []
        var current = false
        var length = 0
        for byte in row {
            for bit in 0..<8 {
                let black = byte & (0x80 >> UInt8(bit)) != 0
                if length > 0 && (black != current || length == 128) {
                    out.append((current ? 0x80 : 0) | UInt8(length - 1))
                    length = 0
                }
                current = black
                length += 1
            }
        }
        if length > 0 { out.append((current ? 0x80 : 0) | UInt8(length - 1)) }
        return out
    }
}
