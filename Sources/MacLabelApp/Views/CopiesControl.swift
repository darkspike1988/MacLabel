import SwiftUI

/// Number of copies, 1 … 999, typed or stepped.
struct CopiesControl: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 6) {
            Text(L10n.string("Copies"))
            TextField(L10n.string("Copies"), value: $model.document.copies, format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 48)
            Stepper(L10n.string("Copies"), value: $model.document.copies, in: 1...999)
                .labelsHidden()
        }
        .disabled(model.isPrinting)
        .accessibilityElement(children: .contain)
        .onChange(of: model.document.copies) { _, copies in
            let clamped = min(max(copies, 1), 999)
            if clamped != copies { model.document.copies = clamped }
        }
    }
}
