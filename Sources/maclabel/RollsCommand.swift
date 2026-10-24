import ArgumentParser
import Foundation
import LabelMedia
import MacLabelKit

struct RollsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rolls", abstract: "Look up label rolls.",
        subcommands: [Search.self]
    )

    struct Search: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "search", abstract: "Search rolls by article number, size or name."
        )

        @Argument(help: "Article number, size (e.g. 32x57) or part of the name.")
        var query: String

        func run() throws {
            let rolls = MediaCatalog.bundled.search(query)
            guard !rolls.isEmpty else {
                print(localizedString("No matches."))
                return
            }
            print(rollTable(rolls))
        }
    }
}

func readingSize(_ roll: LabelRoll) -> String {
    let size = roll.readingSizeMM
    let w = Int(size.width.rounded())
    if let h = size.height { return "\(w) × \(Int(h.rounded())) mm" }
    return localizedString("\(w) mm continuous")
}

func rollTable(_ rolls: [LabelRoll]) -> String {
    let header = ["ID", "Name", localizedString("Size"), localizedString("Article numbers")]
    let rows = [header] + rolls.map { [$0.id, $0.displayName, readingSize($0), $0.skus.joined(separator: ", ")] }
    return formatTable(rows)
}
