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
            let payload = QRPayload.make(
                kind: qrKind, text: qrText, ssid: wifiSSID, password: wifiPassword, security: wifiSecurity,
                name: contactName, phone: contactPhone, email: contactEmail
            )
            return .qr(QRContent(payload: payload, caption: qrCaption.isEmpty ? nil : qrCaption))
        case .image:
            guard let image else { throw DocumentError.missingImage }
            return .image(ImageContent(image: image, dither: ditherImage))
        }
    }

    public func contents(limit: Int? = nil) throws -> [LabelContent] {
        let all = try LabelBatch.expand(template(), copies: copies, counter: counter, table: csv)
        guard let limit else { return all }
        return Array(all.prefix(limit))
    }

    public func labelCount() throws -> Int {
        (csv?.rows.count ?? 1) * copies
    }

    public func placeholderNames() -> [String] {
        (csv?.headers ?? []) + (counter != nil ? ["n"] : [])
    }
}
