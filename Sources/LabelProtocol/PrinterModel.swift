/// Command-set family a printer speaks.
public enum ProtocolFamily: Sendable {
    case lwClassic
    case lwV2
    case unsupported
}

/// A known DYMO LabelWriter model, identified by USB product ID.
public struct PrinterModel: Sendable, Hashable {
    public let name: String
    public let productID: UInt16
    public let family: ProtocolFamily
    /// Printable dots across the head at 300 dpi (or native dpi for unsupported models).
    public let headDots: Int
    public let supports600lpi: Bool
    public let hasTwinRolls: Bool

    public static let vendorID: UInt16 = 0x0922

    public static let all: [PrinterModel] = [
        // LW-Classic, supported in v1
        classic(0x18, "LabelWriter Twin Turbo", twin: true),
        classic(0x19, "LabelWriter 400"),
        classic(0x1A, "LabelWriter 400 Turbo"),
        classic(0x1D, "LabelWriter DUO"),
        classic(0x1F, "LabelWriter 4XL", dots: 1248),
        classic(0x20, "LabelWriter 450", lpi600: true),
        classic(0x21, "LabelWriter 450 Turbo", lpi600: true),
        classic(0x22, "LabelWriter 450 Twin Turbo", lpi600: true, twin: true),
        classic(0x23, "LabelWriter 450 DUO", lpi600: true),
        // LW-V2, recognised only
        PrinterModel(name: "LabelWriter 550", productID: 0x28, family: .lwV2, headDots: 672, supports600lpi: false, hasTwinRolls: false),
        PrinterModel(name: "LabelWriter 550 Turbo", productID: 0x29, family: .lwV2, headDots: 672, supports600lpi: false, hasTwinRolls: false),
        PrinterModel(name: "LabelWriter 5XL", productID: 0x2A, family: .lwV2, headDots: 1248, supports600lpi: false, hasTwinRolls: false),
        // Recognised, unsupported
        unsupported(0x06, "LabelWriter 300", dots: 464),
        unsupported(0x09, "LabelWriter 310", dots: 464),
        unsupported(0x12, "LabelWriter 315", dots: 464),
        unsupported(0x10, "LabelWriter 320", dots: 464),
        unsupported(0x07, "LabelWriter 330", dots: 464),
        unsupported(0x08, "LabelWriter 330 Turbo", dots: 464),
        unsupported(0x24, "LabelWriter SE450", dots: 448),
        unsupported(0x27, "LabelWriter Wireless", dots: 672),
    ]

    public static func lookup(productID: UInt16) -> PrinterModel? {
        all.first { $0.productID == productID }
    }

    private static func classic(_ pid: UInt16, _ name: String, dots: Int = 672, lpi600: Bool = false, twin: Bool = false) -> PrinterModel {
        PrinterModel(name: name, productID: pid, family: .lwClassic, headDots: dots, supports600lpi: lpi600, hasTwinRolls: twin)
    }

    private static func unsupported(_ pid: UInt16, _ name: String, dots: Int) -> PrinterModel {
        PrinterModel(name: name, productID: pid, family: .unsupported, headDots: dots, supports600lpi: false, hasTwinRolls: false)
    }
}
