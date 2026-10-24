import AppKit
import Contacts
import ContactsUI
import SwiftUI

/// A button that shows the system contact picker (out of process, so no Contacts permission is needed).
struct ContactPickerButton: NSViewRepresentable {
    let title: String
    let onPick: (CNContact) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.show(_:)))
        button.image = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.bezelStyle = .push
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.title = title
        context.coordinator.onPick = onPick
    }

    @MainActor
    final class Coordinator: NSObject, @MainActor CNContactPickerDelegate {
        var onPick: (CNContact) -> Void = { _ in }
        private let picker = CNContactPicker()

        override init() {
            super.init()
            picker.delegate = self
        }

        @objc func show(_ sender: NSButton) {
            picker.showRelative(to: sender.bounds, of: sender, preferredEdge: .maxY)
        }

        func contactPicker(_ picker: CNContactPicker, didSelect contact: CNContact) {
            onPick(contact)
        }
    }
}
