import SwiftUI

/// QR layout: kind (text, link, Wi-Fi, contact), its fields and an optional caption.
struct QRFields: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section {
            Picker(L10n.string("Content"), selection: $model.document.qrKind) {
                ForEach(QRKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            switch model.document.qrKind {
            case .text:
                TextField(L10n.string("Text"), text: $model.document.qrText, axis: .vertical)
                    .lineLimit(2...6)
            case .url:
                TextField(L10n.string("Link"), text: $model.document.qrText, prompt: Text(verbatim: "example.com"))
            case .wifi:
                TextField(L10n.string("Network name"), text: $model.document.wifiSSID)
                TextField(L10n.string("Password"), text: $model.document.wifiPassword)
                Picker(L10n.string("Security"), selection: $model.document.wifiSecurity) {
                    Text(verbatim: "WPA/WPA2/WPA3").tag("WPA")
                    Text(verbatim: "WEP").tag("WEP")
                    Text(L10n.string("None")).tag("nopass")
                }
            case .contact:
                TextField(L10n.string("Name"), text: $model.document.contactName)
                TextField(L10n.string("Phone"), text: $model.document.contactPhone)
                TextField(L10n.string("Email"), text: $model.document.contactEmail)
            }
        }

        Section {
            TextField(L10n.string("Caption"), text: $model.document.qrCaption, prompt: Text(L10n.string("Optional")))
        }
    }
}
