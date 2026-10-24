import SwiftUI

/// Address layout: one multi-line field, always left-aligned on the label.
struct AddressFields: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section(L10n.string("Address")) {
            TextField(
                L10n.string("Address"), text: $model.document.addressText,
                prompt: Text(L10n.string("Name\nStreet\nPostcode City")), axis: .vertical
            )
            .labelsHidden()
            .lineLimit(4...8)
            .multilineTextAlignment(.leading)
        }
    }
}
