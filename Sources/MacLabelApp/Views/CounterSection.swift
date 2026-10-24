import SwiftUI

/// The `{n}` counter: on/off, start value and minimum digits.
struct CounterSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section {
            Toggle(L10n.string("Counter"), isOn: $model.document.counterEnabled)
            if model.document.counterEnabled {
                LabeledContent(L10n.string("Start")) {
                    Text(model.document.counterStart, format: .number)
                        .monospacedDigit()
                    Stepper(L10n.string("Start"), value: $model.document.counterStart, in: 0...999_999)
                        .labelsHidden()
                }
                LabeledContent(L10n.string("Digits")) {
                    Text(model.document.counterDigits, format: .number)
                        .monospacedDigit()
                    Stepper(L10n.string("Digits"), value: $model.document.counterDigits, in: 1...8)
                        .labelsHidden()
                }
            }
        } header: {
            Text(L10n.string("Series"))
        } footer: {
            Text(L10n.string("Use {n} in the text for the running number."))
        }
    }
}
