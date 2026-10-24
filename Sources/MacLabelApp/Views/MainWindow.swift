import SwiftUI

/// The main window: editor on the leading side, the live preview on the trailing side, the print
/// bar below, roll chip and printer status in the toolbar, and "More" as an inspector.
/// Reads `AppModel` from the environment.
public struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @State private var showsRollPicker = false
    @State private var showsInspector = false

    /// Editor (300) + preview (380); the inspector adds its own minimum (260) when open.
    static let minWidth: CGFloat = 720
    static let minWidthWithInspector: CGFloat = 300 + 380 + 260

    public init() { self.init(showsInspector: false) }

    init(showsInspector: Bool) { _showsInspector = State(initialValue: showsInspector) }

    public var body: some View {
        @Bindable var model = model
        HSplitView {
            EditorForm()
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 480)
            LabelPreviewView(chooseRoll: openRollPicker)
                .frame(minWidth: 380)
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            PrintBar()
        }
        .frame(minWidth: showsInspector ? Self.minWidthWithInspector : Self.minWidth, minHeight: 460)
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
