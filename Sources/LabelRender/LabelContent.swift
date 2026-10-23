import CoreGraphics

/// Plain text, laid out without automatic wrapping and auto-fitted to the label.
public struct TextContent: Sendable, Equatable {
    public enum TextAlignment: Sendable {
        case leading, center, trailing
    }

    public var text: String
    public var bold: Bool = false
    public var alignment: TextAlignment = .center

    public init(text: String, bold: Bool = false, alignment: TextAlignment = .center) {
        self.text = text
        self.bold = bold
        self.alignment = alignment
    }
}

/// A 1D barcode, optionally with its human-readable text.
public struct BarcodeContent: Sendable, Equatable {
    public var symbology: BarcodeSymbology
    public var value: String
    public var showText: Bool = true

    public init(symbology: BarcodeSymbology, value: String, showText: Bool = true) {
        self.symbology = symbology
        self.value = value
        self.showText = showText
    }
}

/// A QR code with an optional caption.
public struct QRContent: Sendable, Equatable {
    public var payload: String
    public var caption: String? = nil

    public init(payload: String, caption: String? = nil) {
        self.payload = payload
        self.caption = caption
    }
}

/// A raster image, optionally dithered to 1 bit.
public struct ImageContent: Sendable {
    public var image: CGImage
    public var dither: Bool = true

    public init(image: CGImage, dither: Bool = true) {
        self.image = image
        self.dither = dither
    }
}

/// What to put on a label.
public enum LabelContent: Sendable {
    case text(TextContent)
    case barcode(BarcodeContent)
    case qr(QRContent)
    case image(ImageContent)
}

public enum RenderError: Error, Equatable {
    case emptyContent
    case barcode(BarcodeError)
}
