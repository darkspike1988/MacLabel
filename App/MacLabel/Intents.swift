import AppIntents
import MacLabelApp

/// "Print Label": prints text without opening a window. It never asks back: no roll, an ambiguous
/// roll, overflow or a busy / not-ready printer end with a plain-language error.
struct PrintLabelIntent: AppIntent {
    static let title: LocalizedStringResource = "Print Label"
    static let description = IntentDescription("Prints text as a label on the connected DYMO LabelWriter.")
    static let openAppWhenRun = false

    @Parameter(title: "Text")
    var text: String

    @Parameter(title: "Copies", default: 1, inclusiveRange: (1, 999))
    var copies: Int

    @Parameter(title: "Roll", description: "Article number or size, e.g. 11354 or 57x32. Empty: the roll chosen last.")
    var rollQuery: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Print \(\.$text)") {
            \.$copies
            \.$rollQuery
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let count = try await LabelPrinter.shared.printText(text, copies: copies, rollQuery: rollQuery)
            return .result(dialog: IntentDialog(stringLiteral: PrintPhase.finished(count).message ?? ""))
        } catch {
            // `printText` throws only `QuickPrintError` (any other error, cancellation included, is mapped).
            throw IntentFailure(message: error.localizedDescription)
        }
    }
}

/// "Printer Status": the state of the printer the print intent would use, e.g. "LabelWriter 450 · ready".
struct PrinterStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Printer Status"
    static let description = IntentDescription("Tells whether the DYMO LabelWriter is ready.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text = await LabelPrinter.shared.statusText()
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

/// An intent error whose text is already localized by MacLabelApp.
struct IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: message) }
}

struct MacLabelShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PrintLabelIntent(),
            // German phrases: AppShortcuts.xcstrings.
            phrases: ["Print a label with \(.applicationName)"],
            shortTitle: "Print Label",
            systemImageName: "printer"
        )
        AppShortcut(
            intent: PrinterStatusIntent(),
            phrases: ["Printer status in \(.applicationName)"],
            shortTitle: "Printer Status",
            systemImageName: "printer.dotmatrix"
        )
    }
}
