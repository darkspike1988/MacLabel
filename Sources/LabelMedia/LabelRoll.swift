import Foundation

/// Printable area of a roll in dots (300 dpi across, 300 lpi along the feed).
public struct PrintableArea: Codable, Sendable, Hashable {
    public let originAcrossDots: Int
    public let originFeedDots: Int
    public let widthDots: Int
    /// `nil` for continuous rolls.
    public let lengthDots: Int?

    public init(originAcrossDots: Int, originFeedDots: Int, widthDots: Int, lengthDots: Int?) {
        self.originAcrossDots = originAcrossDots
        self.originFeedDots = originFeedDots
        self.widthDots = widthDots
        self.lengthDots = lengthDots
    }
}

/// A label roll. `acrossMM`/`acrossDots` are measured across the print head,
/// `feedMM`/`feedDots` along the feed direction.
public struct LabelRoll: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case dieCut, continuous
    }

    public let id: String
    public let skus: [String]
    public let nameDE: String
    public let nameEN: String
    public let kind: Kind
    public let acrossMM: Double
    public let feedMM: Double?
    public let acrossDots: Int
    /// Exactly `round(twips / 4.8)`; `nil` for continuous rolls.
    public let feedDots: Int?
    public let printable: PrintableArea
    public let offsetDots: Int
    public let cornerRadiusMM: Double
    public let material: String
    public let regions: [String]
    public let minHeadDots: Int

    public init(
        id: String, skus: [String], nameDE: String, nameEN: String, kind: Kind,
        acrossMM: Double, feedMM: Double?, acrossDots: Int, feedDots: Int?,
        printable: PrintableArea, offsetDots: Int, cornerRadiusMM: Double,
        material: String, regions: [String], minHeadDots: Int
    ) {
        self.id = id
        self.skus = skus
        self.nameDE = nameDE
        self.nameEN = nameEN
        self.kind = kind
        self.acrossMM = acrossMM
        self.feedMM = feedMM
        self.acrossDots = acrossDots
        self.feedDots = feedDots
        self.printable = printable
        self.offsetDots = offsetDots
        self.cornerRadiusMM = cornerRadiusMM
        self.material = material
        self.regions = regions
        self.minHeadDots = minHeadDots
    }

    /// German name when the system language is German, English otherwise.
    public var displayName: String {
        Locale.preferredLanguages.first?.hasPrefix("de") == true ? nameDE : nameEN
    }

    /// Size as read by a person: longer edge first. Continuous rolls are read
    /// across with free length: `(acrossMM, nil)`.
    public var readingSizeMM: (width: Double, height: Double?) {
        guard let feedMM else { return (acrossMM, nil) }
        return (max(acrossMM, feedMM), min(acrossMM, feedMM))
    }
}
