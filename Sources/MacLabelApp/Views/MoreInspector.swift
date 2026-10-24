import LabelProtocol
import LabelRender
import SwiftUI

/// "More": everything beyond roll, content, copies and Print. Automatic is always the default.
struct MoreInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section(L10n.string("Print")) {
                Picker(L10n.string("Density"), selection: $model.document.density) {
                    Text(L10n.string("Automatic")).tag(PrintDensity?.none)
                    ForEach(PrintDensity.allCases, id: \.self) { density in
                        Text(density.title).tag(Optional(density))
                    }
                }
                Picker(L10n.string("Mode"), selection: $model.document.quality) {
                    Text(L10n.string("Automatic")).tag(PrintQuality?.none)
                    Text(PrintQuality.text.title).tag(Optional(PrintQuality.text))
                    if model.selectedPrinter?.model.supports600lpi ?? true {
                        Text(PrintQuality.graphics.title).tag(Optional(PrintQuality.graphics))
                    }
                }
                Picker(L10n.string("Rotation"), selection: $model.document.rotation) {
                    Text(L10n.string("Automatic")).tag(ReadingRotation?.none)
                    ForEach(ReadingRotation.all, id: \.self) { rotation in
                        Text(rotation.title).tag(Optional(rotation))
                    }
                }
            }

            if model.roll?.kind == .continuous {
                ContinuousLengthSection()
            }

            CounterSection()
            CSVSection()
        }
        .formStyle(.grouped)
    }
}
