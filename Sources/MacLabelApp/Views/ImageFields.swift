import SwiftUI

/// Picture layout: the chosen picture and whether photos are dithered.
struct ImageFields: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section {
            LabeledContent(L10n.string("Picture")) {
                if let image = model.document.image {
                    Text(verbatim: "\(image.width) × \(image.height) px")
                } else {
                    Text(L10n.string("None"))
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(L10n.string("Dither photos"), isOn: $model.document.ditherImage)
        } footer: {
            Text(L10n.string("Dithering turns grey tones into dot patterns. Turn it off for logos and line art."))
        }
    }
}
