import Foundation
import LabelMedia
import LabelProtocol
import LabelRender
import SwiftUI

// Display names and symbols for model values, shared by the window's views.

extension LabelLayout: Identifiable {
    public var id: Self { self }

    var title: String {
        switch self {
        case .text: L10n.string("Text")
        case .address: L10n.string("Address")
        case .barcode: L10n.string("Barcode")
        case .qr: L10n.string("QR Code")
        case .image: L10n.string("Picture")
        }
    }

    var systemImage: String {
        switch self {
        case .text: "textformat"
        case .address: "envelope"
        case .barcode: "barcode"
        case .qr: "qrcode"
        case .image: "photo"
        }
    }

    /// ⌘1 … ⌘5 in segment order.
    var shortcut: KeyEquivalent {
        KeyEquivalent(Character(String((Self.allCases.firstIndex(of: self) ?? 0) + 1)))
    }
}

extension QRKind {
    var title: String {
        switch self {
        case .text: L10n.string("Text")
        case .url: L10n.string("Link")
        case .wifi: L10n.string("Wi-Fi")
        case .contact: L10n.string("Contact")
        }
    }
}

extension BarcodeSymbology {
    /// Product names, not translated.
    var title: String {
        switch self {
        case .code128: "Code 128"
        case .ean13: "EAN-13"
        case .ean8: "EAN-8"
        case .upcA: "UPC-A"
        case .code39: "Code 39"
        case .itf14: "ITF-14"
        }
    }
}

extension PrintDensity {
    var title: String {
        switch self {
        case .light: L10n.string("Light")
        case .medium: L10n.string("Medium")
        case .normal: L10n.string("Normal")
        case .dark: L10n.string("Dark")
        }
    }
}

extension PrintQuality {
    var title: String {
        switch self {
        case .text: L10n.string("Text (300 dpi)")
        case .graphics: L10n.string("Graphics (600 dpi)")
        }
    }
}

extension ReadingRotation {
    static let all: [ReadingRotation] = [.upright, .clockwise90, .upsideDown, .counterClockwise90]

    /// Degrees are universal and need no translation.
    var title: String {
        switch self {
        case .upright: "0°"
        case .clockwise90: "90°"
        case .upsideDown: "180°"
        case .counterClockwise90: "270°"
        }
    }
}

extension TextContent.TextAlignment {
    static let all: [TextContent.TextAlignment] = [.leading, .center, .trailing]

    var title: String {
        switch self {
        case .leading: L10n.string("Left")
        case .center: L10n.string("Center")
        case .trailing: L10n.string("Right")
        }
    }

    var systemImage: String {
        switch self {
        case .leading: "text.alignleft"
        case .center: "text.aligncenter"
        case .trailing: "text.alignright"
        }
    }
}

extension LabelRoll {
    /// "57 × 32 mm", or "57 mm continuous".
    var sizeText: String {
        let size = readingSizeMM
        let width = Int(size.width.rounded())
        guard let height = size.height else { return L10n.string("\(width) mm continuous") }
        return "\(width) × \(Int(height.rounded())) mm"
    }

    var materialText: String? {
        material == "durable" ? L10n.string("Durable") : nil
    }
}

extension PrinterState {
    var statusText: String { statusText(bundle: L10n.bundle) }

    func statusText(bundle: Bundle) -> String {
        switch self {
        case .noPrinter: String(localized: "No printer", bundle: bundle)
        case .unsupported(let name): String(localized: "\(name) · not supported", bundle: bundle)
        case .ready(let name): String(localized: "\(name) · ready", bundle: bundle)
        case .notReady(let name, let reason): "\(name) · \(reason)"
        case .busy(let name): String(localized: "\(name) · busy", bundle: bundle)
        case .disconnected: String(localized: "Disconnected", bundle: bundle)
        case .error(let text): text
        case .printing(let name): String(localized: "\(name) · printing …", bundle: bundle)
        }
    }

    var tint: Color {
        switch self {
        case .ready: .green
        case .printing: .blue
        case .busy, .notReady, .unsupported: .orange
        case .disconnected, .error: .red
        case .noPrinter: .secondary
        }
    }
}
