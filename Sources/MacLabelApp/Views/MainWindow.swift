import SwiftUI

/// The main window: editor on the leading side, the live preview on the trailing side, the print
/// bar below, roll chip and printer status in the toolbar, and "More" as an inspector.
/// Reads `AppModel` from the environment.
public struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @State private var showsRollPicker = false
    @State private var showsInspector = false

    /// Editor (380: the five-segment layout picker needs about that) + preview (420: the 11354 label at 2x is 336.5 pt, plus feed arrow and 2 x 24 padding).
    /// An open inspector adds its own `inspectorColumnWidth` minimum on top of this.
    nonisolated static let editorMinWidth: CGFloat = 420
    nonisolated static let previewMinWidth: CGFloat = 420
    nonisolated static let minWidth: CGFloat = editorMinWidth + previewMinWidth

    public init() { self.init(showsInspector: false) }

    init(showsInspector: Bool) { _showsInspector = State(initialValue: showsInspector) }

    public var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            EditorForm()
                .frame(minWidth: Self.editorMinWidth, idealWidth: 420, maxWidth: 480)
            Divider()
            LabelPreviewView(chooseRoll: openRollPicker)
                .frame(minWidth: Self.previewMinWidth)
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            PrintBar()
        }
        .frame(minWidth: Self.minWidth, minHeight: 460)
        .navigationTitle(Text(verbatim: "MacLabel"))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                RollChip(isPresented: $showsRollPicker)
            }
            ToolbarItem(placement: .status) {
                PrinterStatusIndicator(state: model.monitor.state)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(L10n.string("More"), systemImage: "slider.horizontal.3", action: toggleInspector)
                    .help(L10n.string("Density, mode, rotation, counter and CSV"))
            }
        }
        .inspector(isPresented: $showsInspector) {
            MoreInspector()
                .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
        }
        .sheet(isPresented: $model.needsRollChoice) {
            FirstRunRollSheet()
        }
        .background {
            VisibilityReporter { visible in
                model.monitor.visibilityChanged(visible: visible)
            }
        }
        .task {
            await model.refreshPrinters()
            await model.monitor.refreshNow()
        }
    }

    private func openRollPicker() { showsRollPicker = true }
    private func toggleInspector() { showsInspector.toggle() }
}
