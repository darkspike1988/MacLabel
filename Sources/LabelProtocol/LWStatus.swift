/// Decoded status byte returned by `ESC A`.
public struct LWStatus: Sendable, Equatable {
    public let raw: UInt8

    public init(raw: UInt8) { self.raw = raw }

    public var isReady: Bool { raw & 0x01 != 0 }
    public var isTopOfForm: Bool { raw & 0x02 != 0 }
    public var isPaperOut: Bool { raw & 0x20 != 0 }
    public var isJammed: Bool { raw & 0x40 != 0 }
    public var hasError: Bool { raw & 0x80 != 0 }
    public var canPrint: Bool { isReady && !isPaperOut && !isJammed && !hasError }
}

/// Decoded `ESC V` version response: 7-digit model number followed by firmware string.
public struct LWVersion: Sendable, Equatable {
    public let modelNumber: String
    public let firmware: String

    public init?(response: [UInt8]) {
        guard response.count >= 8, response[0..<7].allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
        modelNumber = String(decoding: response[0..<7], as: UTF8.self)
        let rest = response[7...].filter { $0 != 0x20 && $0 != 0x00 }
        firmware = String(decoding: rest, as: UTF8.self)
    }
}
