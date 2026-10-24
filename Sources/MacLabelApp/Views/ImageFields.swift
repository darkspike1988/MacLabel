import SwiftUI
import UniformTypeIdentifiers

/// Picture layout: the chosen picture and whether photos are dithered.
struct ImageFields: View {
    @Environment(AppModel.self) private var model
    @State private var choosingFile = false

    var body: some View {
        @Bindable var model = model
        Section {
            LabeledContent(L10n.string("Picture")) {
                if let image = model.document.image {
                    Text(L10n.string("\(image.width) × \(image.height) px"))
                } else {
                    Text(L10n.string("None"))
                        .foregroundStyle(.secondary)
                }
            }
            Button(L10n.string("Choose Picture …"), systemImage: "photo", action: chooseFile)
            Toggle(L10n.string("Dither photos"), isOn: $model.document.ditherImage)
        } footer: {
            Text(L10n.string("Dithering turns grey tones into dot patterns. Turn it off for logos and line art. You can also drop a picture on the window."))
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { model.startImport([url]) }
        }
    }

    private func chooseFile() { choosingFile = true }
}
