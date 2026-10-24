import AppKit
import LabelMedia
import SwiftUI

/// The quick print in the menu bar (`MenuBarExtra` with the window style): a text field, the printer
/// status, the loaded roll and Print (⌘Return). Return inserts a line break.
///
/// The panel keeps its own text. It prints it as a text-label `LabelDocument` through the shared
/// `AppModel` (printer, remembered roll, `LabelPrinter`, `PrintPhase`), so the window's document
/// stays untouched. "Text too long" copies the text into the window's document and opens it.
/// Reads `AppModel` from the environment.
public struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var text: String
    @State private var preview: PreviewResult?
    @State private var engine = PreviewEngine(maxPages: 1)
    @FocusState private var focused: Bool

    public init() { self.init(initialText: "") }

    init(initialText: String) { _text = State(initialValue: initialText) }

    /// The single text label the panel prints.
    nonisolated static func document(text: String) -> LabelDocument {
        var document = LabelDocument()
        document.text = text
        return document
    }

    /// Decides the main button. `preview` is the (possibly not yet finished) render of `document`.
    nonisolated static func action(for document: LabelDocument, preview: PreviewResult?, bundle: Bundle = L10n.bundle) -> PanelAction {
        if let preview, preview.missingRoll {
            return .disabled(String(localized: "No roll chosen", bundle: bundle))
        }
        if document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .disabled(String(localized: "Enter some text", bundle: bundle))
        }
        if let preview {
            if !preview.overflowIndices.isEmpty { return .openWindow }
            if let error = preview.error { return .disabled(error) }
        }
        return .print
    }

    private struct PreviewKey: Equatable {
        let text: String
        let roll: LabelRoll?
        let printerModel: String
    }

    public var body: some View {
        let document = Self.document(text: text)
        let action = resolvedAction(document)
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $text)
                .font(.body)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 84)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
                .accessibilityLabel(Text(L10n.string("Label text")))

            HStack {
                PrinterStatusIndicator(state: model.monitor.state)
                Spacer()
            }

            rollRow

            statusLine(for: action)

            actionButton(for: action, document: document)
        }
        .padding(16)
        .frame(width: 320)
        .background {
            VisibilityReporter { visible in
                model.monitor.visibilityChanged(visible: visible)
            }
        }
        .onAppear { focused = true }
        .task(id: PreviewKey(text: text, roll: model.roll, printerModel: model.effectiveModel.name)) {
            preview = await engine.update(document: document, roll: model.roll, model: model.effectiveModel)
        }
        .task {
            await model.refreshPrinters()
            await model.monitor.refreshNow()
        }
    }

    private var rollRow: some View {
        HStack {
            Label(model.roll.map(RollPicker.chipText) ?? L10n.string("No roll chosen"), systemImage: "tag")
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Spacer()
            Button(L10n.string("Change …"), action: openMainWindow)
                .buttonStyle(.link)
                .help(L10n.string("Choose the loaded roll in the main window"))
        }
    }

    @ViewBuilder
    private func statusLine(for action: PanelAction) -> some View {
        if model.printPhase != .idle {
            PrintStatusView(blockReason: nil)
        } else if case .disabled(let reason) = action {
            Label(reason, systemImage: "info.circle")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    @ViewBuilder
    private func actionButton(for action: PanelAction, document: LabelDocument) -> some View {
        switch action {
        case .openWindow:
            Button(L10n.string("Text too long – open in window"), systemImage: "arrow.up.forward.app", action: openMainWindowWithText)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .print, .disabled:
            Button(L10n.string("Print"), systemImage: "printer") {
                Task { await model.print(document: document, allowOverflow: false) }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(action != .print || model.isPrinting)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .help(L10n.string("Print the text (⌘Return)"))
        }
    }

    /// No printer or an unsupported one blocks before the text is looked at.
    private func resolvedAction(_ document: LabelDocument) -> PanelAction {
        if let reason = model.printBlockReason, model.selectedPrinter == nil || model.selectedPrinter?.model.family != .lwClassic {
            return .disabled(reason)
        }
        return Self.action(for: document, preview: preview)
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate()
    }

    private func openMainWindowWithText() {
        model.load(text: text)
        openMainWindow()
    }
}
