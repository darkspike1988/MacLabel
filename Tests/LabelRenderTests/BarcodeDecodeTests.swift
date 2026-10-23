import CoreGraphics
import Foundation
import LabelProtocol
import Testing
import Vision
@testable import LabelRender

/// Scannability: the rendered preview must decode with Vision to the original value.
@Suite struct BarcodeDecodeTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let symbology: LabelRender.BarcodeSymbology
        let value: String
        let accepted: [String]
        var testDescription: String { "\(symbology) \(value)" }
    }

    static let cases: [Case] = [
        Case(symbology: .code128, value: "Box 08", accepted: ["Box 08"]),
        Case(symbology: .code128, value: "123456", accepted: ["123456"]),
        Case(symbology: .ean13, value: "4006381333931", accepted: ["4006381333931"]),
        Case(symbology: .ean8, value: "96385074", accepted: ["96385074"]),
        Case(symbology: .upcA, value: "036000291452", accepted: ["036000291452", "0036000291452"]),
        Case(symbology: .code39, value: "AB-1", accepted: ["AB-1", "*AB-1*"]),
        Case(symbology: .itf14, value: "15400141288763", accepted: ["15400141288763"]),
    ]

    @Test(arguments: cases)
    func barcodeDecodes(c: Case) throws {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .graphics)
        let res = try LabelRenderer.render(.barcode(.init(symbology: c.symbology, value: c.value)), geometry: g)
        let decoded = try decode(res.preview)
        #expect(decoded.contains { c.accepted.contains($0) }, "decoded: \(decoded)")
    }

    @Test(arguments: ["https://example.com", "Kühlschrank Größe Ä"])
    func qrDecodes(payload: String) throws {
        let g = LabelGeometry(roll: r11354, headDots: 672, quality: .graphics)
        let res = try LabelRenderer.render(.qr(.init(payload: payload, caption: "Regal 4")), geometry: g)
        #expect(try decode(res.preview).contains(payload))
    }

    @Test func rotatedCode128Decodes() throws {
        let g = LabelGeometry(roll: r99010, headDots: 672, quality: .graphics, rotation: .clockwise90)
        let res = try LabelRenderer.render(.barcode(.init(symbology: .code128, value: "Box 08")), geometry: g)
        #expect(try decode(res.preview).contains("Box 08"))
    }

    @Test func rotatedQRDecodes() throws {
        let g = LabelGeometry(roll: r99010, headDots: 672, quality: .graphics, rotation: .clockwise90)
        let res = try LabelRenderer.render(.qr(.init(payload: "https://example.com", caption: "Regal 4")), geometry: g)
        #expect(try decode(res.preview).contains("https://example.com"))
    }

    /// Upscales with nearest neighbour, adds a white border and runs Vision.
    func decode(_ image: CGImage, scale: Int = 3, border: Int = 60) throws -> [String] {
        let w = image.width * scale + 2 * border, h = image.height * scale + 2 * border
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { throw CocoaError(.featureUnsupported) }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: border, y: border, width: image.width * scale, height: image.height * scale))
        guard let big = ctx.makeImage() else { throw CocoaError(.featureUnsupported) }
        let request = VNDetectBarcodesRequest()
        try VNImageRequestHandler(cgImage: big, options: [:]).perform([request])
        return (request.results ?? []).compactMap(\.payloadStringValue)
    }
}
