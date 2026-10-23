import ArgumentParser
import LabelMedia
import MacLabelKit

/// Turns `--roll` (or the remembered roll) into one roll, or fails with exit 64.
enum RollResolver {
    struct Resolution {
        let roll: LabelRoll
        /// Printed to stderr when several rolls of the same size matched.
        let note: String?
    }

    static func resolve(
        query: String?, catalog: MediaCatalog, preferences: RollPreferences, serial: String?
    ) throws -> Resolution {
        guard let query else {
            if let id = preferences.lastRollID(forPrinterSerial: serial), let remembered = catalog.roll(id: id) {
                return Resolution(roll: remembered, note: nil)
            }
            throw fail(localizedString("No roll selected. Example: maclabel print \"Text\" --roll 11354"), code: Exit.usage)
        }
        if let exact = catalog.roll(id: query) ?? catalog.roll(sku: query) { return Resolution(roll: exact, note: nil) }

        let matches = catalog.search(query)
        guard let first = matches.first else {
            throw fail(localizedString("No roll found for \"\(query)\"."), code: Exit.usage)
        }
        if matches.count == 1 { return Resolution(roll: first, note: nil) }

        // Same physical size (e.g. standard and durable variants): not ambiguous.
        let sameSize = matches.allSatisfy {
            $0.acrossDots == first.acrossDots && $0.feedDots == first.feedDots && $0.kind == first.kind
        }
        if sameSize {
            let chosen = matches.first { $0.material == "standard" } ?? first
            let others = matches.filter { $0.id != chosen.id }.map(\.id).joined(separator: ", ")
            return Resolution(
                roll: chosen,
                note: localizedString("Roll: \(chosen.id) (\(chosen.displayName)); also matching: \(others)"))
        }
        let head = localizedString("Roll \"\(query)\" is ambiguous. Please be more specific:")
        throw fail(head + "\n" + rollTable(Array(matches.prefix(10))), code: Exit.usage)
    }
}
