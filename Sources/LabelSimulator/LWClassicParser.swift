import LabelProtocol

/// One LW-Classic command as the LabelWriter 400/450 firmware would see it
/// (docs/research/lw450-protocol.md §2).
public enum LWCommand: Sendable, Equatable {
    /// Run of ≥ 85 `ESC` bytes that ends a partial raster line. `count` excludes the
    /// `ESC` that starts the following command.
    case resync(count: Int)
    /// `ESC @`: reset all parameters (BPL 84, dot tab 0, text mode, normal density, default length).
    case reset
    /// `ESC *`: internal parameters to their defaults (same reset of the raster state as `ESC @`).
    case restoreDefaults
    /// `ESC A`: 1-byte status.
    case statusRequest
    /// `ESC V`: model and firmware string.
    case versionRequest
    /// `ESC B n`: first byte of the raster line (0…83).
    case dotTab(Int)
    /// `ESC D n`: bytes per raster line (1…84).
    case bytesPerLine(Int)
    /// `ESC Q hi lo`: line tab (undocumented for the 450, MacLabel/DYMO send 0).
    case lineTab(Int)
    /// `ESC L hi lo`: label length in lines; ≥ 0x8000 = continuous.
    case labelLength(Int)
    /// `ESC E`: form feed to the tear bar.
    case formFeed
    /// `ESC G`: short form feed to the next top of form.
    case shortFormFeed
    /// `ESC f 1 n`: feed n blank lines.
    case skipLines(Int)
    /// `SYN`/`ETB`: one raster line, already decoded to `bytesPerLine` bytes (MSB = left dot, 1 = black).
    case rasterLine([UInt8], compressed: Bool)
    /// `ESC h` / `ESC i`.
    case quality(PrintQuality)
    /// `ESC c/d/e/g`.
    case density(PrintDensity)
    /// `ESC q n` (Twin Turbo only, accepted and ignored on the 450).
    case rollSelect(TwinRoll)
}

public struct ParsedCommand: Sendable, Equatable {
    public let offset: Int
    public let command: LWCommand
}

/// Protocol errors the simulator reports instead of printing garbage.
public enum SimulatorError: Error, Equatable, CustomStringConvertible {
    case unknownByte(offset: Int, byte: UInt8)
    case unknownEscape(offset: Int, byte: UInt8)
    case truncated(offset: Int, command: String)
    case rlePixelCount(offset: Int, expected: Int, actual: Int)
    case valueOutOfRange(offset: Int, command: String, value: Int)
    case shortResync(offset: Int, count: Int)
    case unsupportedOnLW450(offset: Int, command: String)

    public var description: String {
        switch self {
        case let .unknownByte(o, b): "byte 0x\(hex(b)) at offset \(o) is neither ESC, SYN nor ETB"
        case let .unknownEscape(o, b): "unknown command ESC 0x\(hex(b)) at offset \(o)"
        case let .truncated(o, c): "\(c) at offset \(o) is truncated (stream ends)"
        case let .rlePixelCount(o, e, a): "ETB at offset \(o) encodes \(a) pixels, BPL×8 = \(e)"
        case let .valueOutOfRange(o, c, v): "\(c) at offset \(o) has invalid value \(v)"
        case let .shortResync(o, n): "run of \(n) ESC bytes at offset \(o) is too short for a resync (≥ 85)"
        case let .unsupportedOnLW450(o, c): "\(c) at offset \(o) is not supported by the LabelWriter 450"
        }
    }

    private func hex(_ b: UInt8) -> String {
        let s = String(b, radix: 16, uppercase: true)
        return s.count == 1 ? "0" + s : s
    }
}

/// Byte-exact parser for the LW-Classic command stream (lw450-protocol.md §2).
public enum LWClassicParser {
    public static let maxBytesPerLine = 84
    public static let minResync = 85

    public static func parse(_ bytes: [UInt8]) throws -> [ParsedCommand] {
        var out: [ParsedCommand] = []
        var bpl = maxBytesPerLine
        var dotTab = 0
        var i = 0
        let n = bytes.count

        func need(_ count: Int, _ name: String, at offset: Int) throws {
            if offset + count > n { throw SimulatorError.truncated(offset: offset, command: name) }
        }

        while i < n {
            let start = i
            if (bytes[i] == 0x16 || bytes[i] == 0x17) && dotTab + bpl > maxBytesPerLine {
                throw SimulatorError.valueOutOfRange(offset: start, command: "raster line (dot tab + BPL > 84)", value: dotTab + bpl)
            }
            switch bytes[i] {
            case 0x1B:
                // Count the ESC run.
                var j = i
                while j < n && bytes[j] == 0x1B { j += 1 }
                let run = j - i
                if run > 1 || j == n {
                    // The last ESC starts a command unless the stream ends here.
                    let resync = j == n ? run : run - 1
                    if resync >= 1 {
                        if resync < minResync { throw SimulatorError.shortResync(offset: start, count: resync) }
                        out.append(ParsedCommand(offset: start, command: .resync(count: resync)))
                    }
                    if j == n { i = j; continue }
                    i = j - 1
                }
                let cmdOffset = i
                try need(2, "ESC", at: cmdOffset)
                let code = bytes[i + 1]
                func value(_ index: Int) -> Int { Int(bytes[cmdOffset + index]) }
                let command: LWCommand
                switch code {
                case 0x40, 0x2A:
                    command = code == 0x40 ? .reset : .restoreDefaults
                    bpl = maxBytesPerLine; dotTab = 0
                    i += 2
                case 0x41: command = .statusRequest; i += 2
                case 0x56: command = .versionRequest; i += 2
                case 0x42:
                    try need(3, "ESC B", at: cmdOffset)
                    let v = value(2)
                    guard v < maxBytesPerLine else {
                        throw SimulatorError.valueOutOfRange(offset: cmdOffset, command: "ESC B", value: v)
                    }
                    dotTab = v; command = .dotTab(v); i += 3
                case 0x44:
                    try need(3, "ESC D", at: cmdOffset)
                    let v = value(2)
                    guard (1...maxBytesPerLine).contains(v) else {
                        throw SimulatorError.valueOutOfRange(offset: cmdOffset, command: "ESC D", value: v)
                    }
                    bpl = v; command = .bytesPerLine(v); i += 3
                case 0x51:
                    try need(4, "ESC Q", at: cmdOffset)
                    command = .lineTab(value(2) << 8 | value(3)); i += 4
                case 0x4C:
                    try need(4, "ESC L", at: cmdOffset)
                    let v = value(2) << 8 | value(3)
                    guard v > 0 else { throw SimulatorError.valueOutOfRange(offset: cmdOffset, command: "ESC L", value: v) }
                    command = .labelLength(v); i += 4
                case 0x45: command = .formFeed; i += 2
                case 0x47: command = .shortFormFeed; i += 2
                case 0x66:
                    try need(4, "ESC f", at: cmdOffset)
                    guard value(2) == 1 else {
                        throw SimulatorError.valueOutOfRange(offset: cmdOffset, command: "ESC f (second byte)", value: value(2))
                    }
                    command = .skipLines(value(3)); i += 4
                case 0x68: command = .quality(.text); i += 2
                case 0x69: command = .quality(.graphics); i += 2
                case 0x63: command = .density(.light); i += 2
                case 0x64: command = .density(.medium); i += 2
                case 0x65: command = .density(.normal); i += 2
                case 0x67: command = .density(.dark); i += 2
                case 0x71:
                    try need(3, "ESC q", at: cmdOffset)
                    switch value(2) {
                    case 0x30: command = .rollSelect(.auto)
                    case 0x31: command = .rollSelect(.left)
                    case 0x32: command = .rollSelect(.right)
                    default: throw SimulatorError.valueOutOfRange(offset: cmdOffset, command: "ESC q", value: value(2))
                    }
                    i += 3
                case 0x79, 0x7A:
                    throw SimulatorError.unsupportedOnLW450(offset: cmdOffset, command: code == 0x79 ? "ESC y" : "ESC z")
                default:
                    throw SimulatorError.unknownEscape(offset: cmdOffset, byte: code)
                }
                out.append(ParsedCommand(offset: cmdOffset, command: command))
            case 0x16:
                try need(1 + bpl, "SYN", at: start)
                out.append(ParsedCommand(offset: start, command: .rasterLine(Array(bytes[(i + 1)...(i + bpl)]), compressed: false)))
                i += 1 + bpl
            case 0x17:
                let expected = bpl * 8
                var row = [UInt8](repeating: 0, count: bpl)
                var pixel = 0
                i += 1
                while pixel < expected {
                    guard i < n else { throw SimulatorError.truncated(offset: start, command: "ETB") }
                    let b = bytes[i]
                    let length = Int(b & 0x7F) + 1
                    if pixel + length > expected {
                        throw SimulatorError.rlePixelCount(offset: start, expected: expected, actual: pixel + length)
                    }
                    if b & 0x80 != 0 {
                        for p in pixel..<(pixel + length) { row[p / 8] |= 0x80 >> UInt8(p % 8) }
                    }
                    pixel += length
                    i += 1
                }
                out.append(ParsedCommand(offset: start, command: .rasterLine(row, compressed: true)))
            default:
                throw SimulatorError.unknownByte(offset: start, byte: bytes[i])
            }
        }
        return out
    }
}
