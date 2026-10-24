import LabelRender
import SwiftUI

/// Text layout: multi-line text (auto-fitted by the renderer), bold and alignment.
struct TextLayoutFields: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section(L10n.string("Text")) {
            TextField(
                L10n.string("Text"), text: $model.document.text,
                prompt: Text(L10n.string("Label text")), axis: .vertical
            )
            .labelsHidden()
            .lineLimit(3...10)
            .multilineTextAlignment(.leading)
        }

        Section {
            Toggle(L10n.string("Bold"), isOn: $model.document.bold)

            Picker(L10n.string("Alignment"), selection: $model.document.alignment) {
                ForEach(TextContent.TextAlignment.all, id: \.self) { alignment in
                    Label(alignment.title, systemImage: alignment.systemImage)
                        .labelStyle(.iconOnly)
                        .tag(alignment)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text(L10n.string("The text size adapts to the label automatically."))
        }
    }
}
