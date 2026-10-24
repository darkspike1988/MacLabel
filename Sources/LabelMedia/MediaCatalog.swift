import Foundation

/// The roll database (facts only) with lookup and search.
public struct MediaCatalog: Sendable {
    public let rolls: [LabelRoll]

    public init(rolls: [LabelRoll]) {
        self.rolls = rolls
    }

    /// Location of the bundled `media.json` (resource bundle of `LabelMedia`).
    public static var bundledResourceURL: URL {
        resourceBundle.url(forResource: "media", withExtension: "json")!
    }

    private static let resourceBundle: Bundle = {
        ResourceLocator.bundle(named: "MacLabelKit_LabelMedia", fallback: Bundle.module)!
    }()

    public static let bundled: MediaCatalog = {
        struct File: Decodable { let version: Int; let rolls: [LabelRoll] }
        do {
            let data = try Data(contentsOf: bundledResourceURL)
            return MediaCatalog(rolls: try JSONDecoder().decode(File.self, from: data).rolls)
        } catch {
            fatalError("media.json is unreadable: \(error)")
        }
    }()

    public func roll(id: String) -> LabelRoll? {
        rolls.first { $0.id == id }
    }

    public func roll(sku: String) -> LabelRoll? {
        let key = Self.normalize(sku)
        return rolls.first { $0.skus.contains { Self.normalize($0) == key } }
    }

    /// Ranking: exact SKU, SKU prefix, size, name part. Ties stay in id order.
    public func search(_ query: String) -> [LabelRoll] {
        let q = Self.normalize(query)
        guard !q.isEmpty else { return [] }
        let dims = Self.dimensions(q)
        var ranked: [(rank: Int, roll: LabelRoll)] = []
        for roll in rolls.sorted(by: { $0.id < $1.id }) {
            let skus = roll.skus.map(Self.normalize)
            if skus.contains(q) {
                ranked.append((0, roll))
            } else if skus.contains(where: { $0.hasPrefix(q) }) {
                ranked.append((1, roll))
            } else if let dims, Self.matches(roll, dims) {
                ranked.append((2, roll))
            } else if [roll.nameDE, roll.nameEN].contains(where: { Self.normalize($0).contains(q) }) {
                ranked.append((3, roll))
            }
        }
        return ranked.enumerated()
            .sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }
            .map(\.element.roll)
    }

    static func normalize(_ s: String) -> String {
        var t = s.lowercased().filter { !$0.isWhitespace }
        t = t.replacingOccurrences(of: "×", with: "x").replacingOccurrences(of: "*", with: "x")
        return t.replacingOccurrences(of: "mm", with: "")
    }

    private static func dimensions(_ q: String) -> (Double, Double)? {
        let parts = q.split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let a = Double(parts[0].replacingOccurrences(of: ",", with: ".")),
              let b = Double(parts[1].replacingOccurrences(of: ",", with: "."))
        else { return nil }
        return (a, b)
    }

    private static func matches(_ roll: LabelRoll, _ dims: (Double, Double)) -> Bool {
        guard let height = roll.readingSizeMM.height else { return false }
        let width = roll.readingSizeMM.width
        let (hi, lo) = (max(dims.0, dims.1), min(dims.0, dims.1))
        return abs(hi - width) <= 1 && abs(lo - height) <= 1
    }
}
