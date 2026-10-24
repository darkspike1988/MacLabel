import LabelRender
import SwiftUI

/// Barcode layout: symbology, value and the human-readable text.
struct BarcodeFields: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section {
            Picker(L10n.string("Barcode type"), selection: $model.document.symbology) {
                ForEach(BarcodeSymbology.allCases, id: \.self) { symbology in
                    Text(symbology.title).tag(symbology)
                }
            }
            TextField(L10n.string("Value"), text: $model.document.barcodeValue, prompt: Text(verbatim: "4006381333931"))
                .monospacedDigit()
            Toggle(L10n.string("Show text below"), isOn: $model.document.showBarcodeText)
        }
    }
}
