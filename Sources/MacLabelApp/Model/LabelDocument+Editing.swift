import Foundation
import LabelMedia
import LabelRender
import MacLabelKit

/// Editing helpers the views bind to, kept here so they can be tested without a window.
extension LabelDocument {
    /// Appends `{name}` to the field the current layout (and QR kind) is mainly about.
    public mutating func insertPlaceholder(_ name: String) {
        let token = "{\(name)}"
        switch layout {
        case .text: text += token
        case .address: addressText += token
        case .barcode: barcodeValue += token
        case .image: break
        case .qr:
            switch qrKind {
            case .text, .url: qrText += token
            case .wifi: wifiSSID += token
            case .contact: contactName += token
            }
        }
    }

    /// Whether `{n}` counts; switching it on starts with the default counter.
    public var counterEnabled: Bool {
        get { counter != nil }
        set { counter = newValue ? (counter ?? CounterSpec()) : nil }
    }

    public var counterStart: Int {
        get { counter?.start ?? 1 }
        set { counter = CounterSpec(start: newValue, step: counter?.step ?? 1, minimumDigits: counterDigits) }
    }

    public var counterDigits: Int {
        get { counter?.minimumDigits ?? 1 }
        set { counter = CounterSpec(start: counterStart, step: counter?.step ?? 1, minimumDigits: newValue) }
    }

    /// What VoiceOver reads for the preview of label `index` (placeholders filled in).
    public func spokenText(at index: Int) -> String {
        let content = (try? contents(limit: index + 1).last) ?? (try? template())
        switch content {
        case .text(let t): return t.text
        case .barcode(let b): return String(localized: "Barcode \(b.value)", bundle: L10n.bundle)
        case .qr(let q):
            let code = String(localized: "QR code \(q.payload)", bundle: L10n.bundle)
            return q.caption.map { "\(code), \($0)" } ?? code
        case .image: return String(localized: "Picture", bundle: L10n.bundle)
        case nil: return ""
        }
    }

    /// The reading rotation the renderer uses for `roll` (same rule as `LabelGeometry`).
    public func effectiveRotation(for roll: LabelRoll) -> ReadingRotation {
        if let rotation { return rotation }
        guard let feedMM = roll.feedMM else { return .upright }
        return roll.acrossMM >= feedMM ? .upright : .clockwise90
    }
}
