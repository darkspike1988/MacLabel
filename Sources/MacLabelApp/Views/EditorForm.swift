import SwiftUI

/// The leading editor: layout segments (⌘1 … ⌘5), the fields of the chosen layout and,
/// for series, the placeholder menu.
struct EditorForm: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker(L10n.string("Layout"), selection: $model.document.layout) {
                    ForEach(LabelLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel(L10n.string("Layout"))
            }

            switch model.document.layout {
            case .text: TextLayoutFields()
            case .address: AddressFields()
            case .barcode: BarcodeFields()
            case .qr: QRFields()
            case .image: ImageFields()
            }

            let names = model.document.placeholderNames()
            if !names.isEmpty, model.document.layout != .image {
                Section {
                    PlaceholderMenu(names: names)
                } footer: {
                    Text(L10n.string("Fields are filled in for every label of the series."))
                }
            }
        }
        .formStyle(.grouped)
        .background {
            LayoutShortcuts()
        }
    }
}
