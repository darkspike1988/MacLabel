import LabelMedia

/// Picks a roll from a user query (CLI `--roll`, app search field) or the remembered roll.
public enum RollChoice: Sendable {
    /// One roll; `alternatives` are other matches of the same physical size (e.g. durable variants).
    case resolved(LabelRoll, alternatives: [LabelRoll])
    /// Several differently sized matches (at most the ranked search result).
    case ambiguous([LabelRoll])
    /// No query and nothing remembered, or no match.
    case none

    public static func choose(query: String?, catalog: MediaCatalog, remembered: String?) -> RollChoice {
        guard let query else {
            if let remembered, let roll = catalog.roll(id: remembered) { return .resolved(roll, alternatives: []) }
            return .none
        }
        if let exact = catalog.roll(id: query) ?? catalog.roll(sku: query) { return .resolved(exact, alternatives: []) }

        let matches = catalog.search(query)
        guard let first = matches.first else { return .none }
        if matches.count == 1 { return .resolved(first, alternatives: []) }

        // Same physical size (e.g. standard and durable variants): not ambiguous.
        let sameSize = matches.allSatisfy {
            $0.acrossDots == first.acrossDots && $0.feedDots == first.feedDots && $0.kind == first.kind
        }
        if sameSize {
            let chosen = matches.first { $0.material == "standard" } ?? first
            return .resolved(chosen, alternatives: matches.filter { $0.id != chosen.id })
        }
        return .ambiguous(matches)
    }
}
