import Contacts
import CoreGraphics
import Foundation
import ImageIO
import MacLabelKit
import Testing
import UniformTypeIdentifiers
@testable import MacLabelApp

@Suite struct ContactFormatterTests {
    private func germanAddress() -> CNMutablePostalAddress {
        let a = CNMutablePostalAddress()
        a.street = "Musterstraße 1"; a.postalCode = "12345"; a.city = "Musterstadt"; a.country = "Deutschland"; a.isoCountryCode = "de"
        return a
    }

    @Test func formatsGermanAddress() {
        let text = ContactFormatter.addressText(name: "Max Mustermann", organization: nil, postal: germanAddress(), region: "DE")
        #expect(text == "Max Mustermann\nMusterstraße 1\n12345 Musterstadt")
    }

    @Test func keepsForeignCountry() {
        let text = ContactFormatter.addressText(name: "Max Mustermann", organization: nil, postal: germanAddress(), region: "US")
        #expect(text.hasPrefix("Max Mustermann\nMusterstraße 1\n12345 Musterstadt\nDeutschland"))
        #expect(text.split(separator: "\n").count == 4)
    }

    @Test func putsOrganizationAfterName() {
        let text = ContactFormatter.addressText(name: "Max Mustermann", organization: "Muster GmbH", postal: germanAddress(), region: "DE")
        #expect(text == "Max Mustermann\nMuster GmbH\nMusterstraße 1\n12345 Musterstadt")
    }

    @Test func dropsEmptyLinesAndMissingAddress() {
        #expect(ContactFormatter.addressText(name: "", organization: "", postal: nil, region: "DE") == "")
        #expect(ContactFormatter.addressText(name: "Max", organization: "", postal: nil, region: "DE") == "Max")
    }
}

@Suite struct ImportHelperTests {
    private func temp(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "maclabel-\(UUID().uuidString)-\(name)")
    }

    @Test func windows1252CSV() throws {
        let url = temp("a.csv")
        defer { try? FileManager.default.removeItem(at: url) }
        try #require("Name\nMüller\n".data(using: .windowsCP1252)).write(to: url)
        let table = try ImportHelpers.loadCSV(url: url)
        #expect(table.rows[0]["Name"] == "Müller")
    }

    @Test func utf8CSV() throws {
        let url = temp("a.csv")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("Name\nMüller\n".utf8).write(to: url)
        #expect(try ImportHelpers.loadCSV(url: url).rows[0]["Name"] == "Müller")
    }

    @Test func emptyCSVRejected() throws {
        let url = temp("a.csv")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("Name\n".utf8).write(to: url)
        #expect(throws: DocumentError.emptyCSV) { try ImportHelpers.loadCSV(url: url) }
    }

    @Test func loadsPNG() throws {
        let url = temp("a.png")
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(width: 2, height: 2, to: url)
        #expect(try ImportHelpers.loadImage(url: url).width == 2)
    }

    @Test func rejectsNonImage() throws {
        let url = temp("a.png")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("nope".utf8).write(to: url)
        #expect(throws: (any Error).self) { try ImportHelpers.loadImage(url: url) }
    }

    @Test(arguments: [
        ("a.csv", ImportHelpers.Kind.csv), ("a.TXT", .csv), ("a.png", .image), ("a.jpg", .image),
        ("a.heic", .image), ("a.pdf", nil), ("a.zip", nil), ("noext", nil),
    ])
    func classifiesByExtension(name: String, kind: ImportHelpers.Kind?) {
        #expect(ImportHelpers.kind(of: URL(fileURLWithPath: "/tmp/\(name)")) == kind)
    }

    @Test @MainActor func droppedImageSwitchesToImageLayout() async throws {
        let url = temp("a.png")
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(width: 3, height: 2, to: url)
        let model = makeViewModel(printers: [], remembered: nil)
        let handled = try await ImportHelpers.importFiles([url], into: model)
        #expect(handled)
        #expect(model.document.layout == .image)
        #expect(model.document.image?.width == 3)
    }

    @Test @MainActor func droppedCSVSetsTable() async throws {
        let url = temp("a.csv")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("Name\nA\nB\n".utf8).write(to: url)
        let model = makeViewModel(printers: [], remembered: nil)
        #expect(try await ImportHelpers.importFiles([url], into: model))
        #expect(model.document.csv?.rows.count == 2)
        #expect(model.document.layout == .text)
    }

    @Test @MainActor func unsupportedFilesAreIgnored() async throws {
        let model = makeViewModel(printers: [], remembered: nil)
        let handled = try await ImportHelpers.importFiles([URL(fileURLWithPath: "/tmp/x.zip")], into: model)
        #expect(!handled)
        #expect(model.document.csv == nil && model.document.image == nil)
    }
}

private func writePNG(width: Int, height: Int, to url: URL) throws {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
}
