import ArgumentParser

@main
struct MacLabel: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "maclabel",
        abstract: "Print labels on a DYMO LabelWriter."
    )

    func run() throws {
        print(Self.helpMessage())
    }
}
