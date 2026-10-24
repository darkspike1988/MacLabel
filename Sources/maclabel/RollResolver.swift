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
        let remembered = preferences.lastRollID(forPrinterSerial: serial)
        switch RollChoice.choose(query: query, catalog: catalog, remembered: remembered) {
        case .resolved(let roll, let alternatives):
            guard !alternatives.isEmpty else { return Resolution(roll: roll, note: nil) }
            let others = alternatives.map(\.id).joined(separator: ", ")
            return Resolution(
                roll: roll,
                note: localizedString("Roll: \(roll.id) (\(roll.displayName)); also matching: \(others)"))
        case .ambiguous(let matches):
            let head = localizedString("Roll \"\(query ?? "")\" is ambiguous. Please be more specific:")
            throw fail(head + "\n" + rollTable(Array(matches.prefix(10))), code: Exit.usage)
        case .none:
            if let query {
                throw fail(localizedString("No roll found for \"\(query)\"."), code: Exit.usage)
            }
            throw fail(localizedString("No roll selected. Example: maclabel print \"Text\" --roll 11354"), code: Exit.usage)
        }
    }
}
