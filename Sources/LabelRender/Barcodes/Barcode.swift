import Foundation

public enum BarcodeSymbology: String, Sendable, CaseIterable, Codable {
    case code128, ean13, ean8, upcA, code39, itf14
}

public enum BarcodeError: Error, Equatable {
    case empty
    case invalidCharacter(Character)
    case invalidLength(expected: [Int], got: Int)
    case badCheckDigit
    case payloadTooLong
    case generationFailed
}

/// 1D barcode encoder. Modules carry no quiet zone; `true` = bar.
public enum Barcode {
    public static func modules(_ s: BarcodeSymbology, _ value: String) throws -> [Bool] {
        guard !value.isEmpty else { throw BarcodeError.empty }
        switch s {
        case .code128: return try Code128.modules(value)
        case .ean13: return EANUPC.ean13Modules(try EANUPC.digits(value, bodyLength: 12))
        case .upcA: return EANUPC.ean13Modules([0] + (try EANUPC.digits(value, bodyLength: 11)))
        case .ean8: return EANUPC.ean8Modules(try EANUPC.digits(value, bodyLength: 7))
        case .code39: return try Code39.modules(value)
        case .itf14: return ITF14.modules(try EANUPC.digits(value, bodyLength: 13))
        }
    }

    public static func humanReadable(_ s: BarcodeSymbology, _ value: String) throws -> String {
        guard !value.isEmpty else { throw BarcodeError.empty }
        switch s {
        case .code128: _ = try Code128.modules(value); return value
        case .ean13: return try EANUPC.digits(value, bodyLength: 12).map(String.init).joined()
        case .upcA: return try EANUPC.digits(value, bodyLength: 11).map(String.init).joined()
        case .ean8: return try EANUPC.digits(value, bodyLength: 7).map(String.init).joined()
        case .code39: return "*" + (try Code39.normalize(value)) + "*"
        case .itf14: return try EANUPC.digits(value, bodyLength: 13).map(String.init).joined()
        }
    }

    /// Expands a width string ("212222") of alternating bar/space runs, starting with a bar.
    static func runs(_ widths: [Int]) -> [Bool] {
        var out: [Bool] = []
        for (i, w) in widths.enumerated() { out += Array(repeating: i % 2 == 0, count: w) }
        return out
    }
}
