import SwiftUI

/// The menu bar commands: File › Print… (⌘P, replacing the system item), the Label menu with the
/// layouts (⌘1 … ⌘5) and Choose Roll… (⌘L), the inspector toggle, and Install Command Line Tool…
/// in the app menu. Window commands act on the focused main window's model and are disabled otherwise.
public struct MacLabelCommands: Commands {
    @FocusedValue(\.mainWindowModel) private var model
    @Environment(\.openSettings) private var openSettings

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button(L10n.string("Print… (menu item)"), action: printDocument)
                .keyboardShortcut("p", modifiers: .command)
                .disabled(!Self.canPrint(model))
        }

        CommandGroup(after: .appSettings) {
            // The Settings window shows the command (and how to run it) in its Command Line section.
            Button(L10n.string("Install Command Line Tool…"), action: showCommandLineSettings)
        }

        CommandMenu(L10n.string("Label")) {
            ForEach(LabelLayout.allCases) { layout in
                Toggle(layout.title, isOn: layoutBinding(layout))
                    .keyboardShortcut(layout.shortcut, modifiers: .command)
                    .disabled(model == nil)
            }
            Divider()
            Button(L10n.string("Choose Roll… (menu item)"), action: chooseRoll)
                .keyboardShortcut("l", modifiers: .command)
                .disabled(model == nil)
        }

        InspectorCommands()
    }

    // MARK: - Logic (tested without a menu bar)

    @MainActor static func canPrint(_ model: AppModel?) -> Bool {
        model?.canRequestPrint ?? false
    }

    @MainActor static func isSelected(_ layout: LabelLayout, in model: AppModel) -> Bool {
        model.document.layout == layout
    }

    @MainActor static func select(_ layout: LabelLayout, in model: AppModel) {
        model.document.layout = layout
    }

    @MainActor static func chooseRoll(in model: AppModel) {
        model.showsRollPicker = true
    }

    // MARK: - Actions

    private func layoutBinding(_ layout: LabelLayout) -> Binding<Bool> {
        Binding(
            get: { model.map { Self.isSelected(layout, in: $0) } ?? false },
            set: { _ in if let model { Self.select(layout, in: model) } }
        )
    }

    private func printDocument() { model?.requestPrint() }
    private func chooseRoll() { if let model { Self.chooseRoll(in: model) } }
    private func showCommandLineSettings() { openSettings() }
}
