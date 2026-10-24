import LabelMedia
import SwiftUI

/// The large live preview on a neutral canvas: the label exactly as it will print, the overflow
/// warning, series paging, or a placeholder when there is no roll or the content cannot render.
struct LabelPreviewView: View {
    @Environment(AppModel.self) private var model
    /// Opens the roll picker (from the "no roll" placeholder).
    let chooseRoll: () -> Void

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 16) {
            if let roll = model.roll {
                if let result = model.previewResult {
                    if let error = result.error {
                        ContentUnavailableView {
                            Label(L10n.string("No Preview"), systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(error)
                        }
                    } else if !result.pages.isEmpty {
                        PreviewPageView(result: result, roll: roll, page: $model.previewPage)
                    }
                } else {
                    ProgressView()
                }
            } else {
                NoRollView(hasPrinter: !model.printers.isEmpty, chooseRoll: chooseRoll)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}
