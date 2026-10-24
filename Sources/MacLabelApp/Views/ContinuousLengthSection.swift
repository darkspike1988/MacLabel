import SwiftUI

/// Label length on continuous rolls, in millimetres.
struct ContinuousLengthSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section(L10n.string("Continuous Roll")) {
            LabeledContent(L10n.string("Length")) {
                HStack(spacing: 4) {
                    TextField(
                        L10n.string("Length"), value: $model.document.continuousLengthMM,
                        format: .number.precision(.fractionLength(0...1))
                    )
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    Text(UnitLength.millimeters.symbol)
                    Stepper(L10n.string("Length"), value: $model.document.continuousLengthMM, in: 10...1000, step: 5)
                        .labelsHidden()
                }
            }
        }
    }
}
