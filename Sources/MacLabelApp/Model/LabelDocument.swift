import CoreGraphics
import Foundation
import LabelProtocol
import LabelRender
import MacLabelKit

public enum LabelLayout: String, CaseIterable, Sendable {
    case text, address, barcode, qr, image
}

public enum DocumentError: Error, Equatable {
    case missingImage
    case emptyCSV
}

extension DocumentError: LocalizedError {
    public var errorDescription: String? { text(bundle: L10n.bundle) }

    func text(bundle: Bundle) -> String {
        switch self {
        case .missingImage: String(localized: "Choose a picture first.", bundle: bundle)
        case .emptyCSV: String(localized: "The CSV file has no data rows.", bundle: bundle)
        }
    }
}

/// Everything the user edits for one label series.
public struct LabelDocument: Sendable, Equatable {
    public var layout: LabelLayout = .text

    public var text: String = ""
    public var bold: Bool = false
    public var alignment: TextContent.TextAlignment = .center

    public var addressText: String = ""

    public var symbology: BarcodeSymbology = .code128
    public var barcodeValue: String = ""
    public var showBarcodeText: Bool = true

    public var qrKind: QRKind = .text
    public var qrText: String = ""
    public var wifiSSID: String = ""
    public var wifiPassword: String = ""
    public var wifiSecurity: String = "WPA"
    public var contactName: String = ""
    public var contactPhone: String = ""
    public var contactEmail: String = ""
    public var qrCaption: String = ""

    public var image: CGImage?
    public var ditherImage: Bool = true

    public var copies: Int = 1
    public var counter: CounterSpec?
    public var csv: CSVTable?

    public var density: PrintDensity?
    public var quality: PrintQuality?
    public var rotation: ReadingRotation?
    public var continuousLengthMM: Double = 50

    public init() {}

    public static func == (a: LabelDocument, b: LabelDocument) -> Bool {
        let sameImage: Bool
        switch (a.image, b.image) {
        case (nil, nil): sameImage = true
        case let (x?, y?): sameImage = x === y
        default: sameImage = false
        }
        return sameImage
            && a.layout == b.layout && a.text == b.text && a.bold == b.bold && a.alignment == b.alignment
            && a.addressText == b.addressText
            && a.symbology == b.symbology && a.barcodeValue == b.barcodeValue && a.showBarcodeText == b.showBarcodeText
            && a.qrKind == b.qrKind && a.qrText == b.qrText && a.wifiSSID == b.wifiSSID
            && a.wifiPassword == b.wifiPassword && a.wifiSecurity == b.wifiSecurity
            && a.contactName == b.contactName && a.contactPhone == b.contactPhone && a.contactEmail == b.contactEmail
            && a.qrCaption == b.qrCaption && a.ditherImage == b.ditherImage
            && a.copies == b.copies && a.counter == b.counter && a.csv == b.csv
            && a.density == b.density && a.quality == b.quality && a.rotation == b.rotation
            && a.continuousLengthMM == b.continuousLengthMM
    }

    public func template() throws -> LabelContent {
        switch layout {
        case .text:
            return .text(TextContent(text: text, bold: bold, alignment: alignment))
        case .address:
            return .text(TextContent(text: addressText, bold: false, alignment: .leading))
        case .barcode:
            return .barcode(BarcodeContent(symbology: symbology, value: barcodeValue, showText: showBarcodeText))
        case .qr:
            return .qr(qrContent(
                text: qrText, ssid: wifiSSID, password: wifiPassword,
                name: contactName, phone: contactPhone, email: contactEmail, caption: qrCaption
            ))
        case .image:
            guard let image else { throw DocumentError.missingImage }
            return .image(ImageContent(image: image, dither: ditherImage))
        }
    }

    private func qrContent(text: String, ssid: String, password: String, name: String, phone: String, email: String, caption: String) -> QRContent {
        let payload = QRPayload.make(
            kind: qrKind, text: text, ssid: ssid, password: password, security: wifiSecurity,
            name: name, phone: phone, email: email
        )
        return QRContent(payload: payload, caption: caption.isEmpty ? nil : caption)
    }

    private func validate() throws {
        guard copies >= 1 else { throw BatchError.invalidCopies }
        if let csv, csv.rows.isEmpty { throw DocumentError.emptyCSV }
    }

    /// Expands the series in the order of `LabelBatch.expand` (rows, then copies), stopping at `limit`.
    public func contents(limit: Int? = nil) throws -> [LabelContent] {
        try validate()
        if let limit, limit <= 0 { return [] }
        let base = try template()
        let total = try labelCount()
        let count = min(total, limit ?? total)

        let rows = csv.map { Array($0.rows.prefix((count + copies - 1) / copies)) }
        var result: [LabelContent] = []
        result.reserveCapacity(count)
        var index = 0
        for rowIndex in 0..<(rows?.count ?? 1) {
            var lowered: [String: String]?
            if let rows, let csv {
                var l: [String: String] = [:]
                for header in csv.headers { l[header.lowercased()] = rows[rowIndex][header] }
                lowered = l
            }
            for _ in 0..<copies {
                guard index < count else { return result }
                let counterText = counter?.formatted(index: index)
                if layout == .qr {
                    func sub(_ s: String) throws -> String {
                        try LabelBatch.substitute(s, row: lowered, counter: counterText, strict: false)
                    }
                    result.append(.qr(qrContent(
                        text: try sub(qrText), ssid: try sub(wifiSSID), password: try sub(wifiPassword),
                        name: try sub(contactName), phone: try sub(contactPhone), email: try sub(contactEmail),
                        caption: try sub(qrCaption)
                    )))
                } else {
                    result.append(try Self.substitute(base, counter: counterText, row: lowered))
                }
                index += 1
            }
        }
        return result
    }

    private static func substitute(_ content: LabelContent, counter: String?, row: [String: String]?) throws -> LabelContent {
        func sub(_ s: String) throws -> String { try LabelBatch.substitute(s, row: row, counter: counter, strict: true) }
        switch content {
        case .text(var t):
            t.text = try sub(t.text)
            return .text(t)
        case .barcode(var b):
            b.value = try sub(b.value)
            return .barcode(b)
        case .qr(var q):
            q.payload = try sub(q.payload)
            if let c = q.caption { q.caption = try sub(c) }
            return .qr(q)
        case .image:
            return content
        }
    }

    public func labelCount() throws -> Int {
        try validate()
        return (csv?.rows.count ?? 1) * copies
    }

    public func placeholderNames() -> [String] {
        (csv?.headers ?? []) + (counter != nil ? ["n"] : [])
    }
}
