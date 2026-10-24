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

    @Test func skipsOrganizationEqualToName() {
        let text = ContactFormatter.addressText(name: "Muster GmbH", organization: "muster gmbh", postal: germanAddress(), region: "DE")
        #expect(text == "Muster GmbH\nMusterstraße 1\n12345 Musterstadt")
    }

    @Test func dropsHomeCountryWithoutISOCode() {
        let a = CNMutablePostalAddress()
        a.street = "Musterstraße 1"; a.postalCode = "12345"; a.city = "Musterstadt"; a.country = "deutschland"
        let de = Locale(identifier: "de_DE")
        #expect(ContactFormatter.addressText(name: "Max", organization: nil, postal: a, region: "DE", locale: de)
            == "Max\nMusterstraße 1\n12345 Musterstadt")
        #expect(ContactFormatter.addressText(name: "Max", organization: nil, postal: a, region: "US", locale: de)
            .split(separator: "\n").count == 4)
    }

    @Test func contactUsesFirstOrChosenAddress() {
        let c = CNMutableContact()
        c.givenName = "Max"; c.familyName = "Mustermann"; c.organizationName = "Muster GmbH"
        let work = CNMutablePostalAddress(); work.street = "Werkstr. 2"; work.postalCode = "54321"; work.city = "Werkstadt"; work.isoCountryCode = "de"
        c.postalAddresses = [CNLabeledValue(label: CNLabelWork, value: germanAddress()), CNLabeledValue(label: CNLabelHome, value: work)]
        let first = ContactFormatter.addressText(for: c, chosen: nil, region: "DE")
        #expect(first == "Max Mustermann\nMuster GmbH\nMusterstraße 1\n12345 Musterstadt")
        let chosen = ContactFormatter.addressText(for: c, chosen: work, region: "DE")
        #expect(chosen == "Max Mustermann\nMuster GmbH\nWerkstr. 2\n54321 Werkstadt")
    }

    @Test func contactWithoutAddress() {
        let c = CNMutableContact()
        c.givenName = "Max"; c.familyName = "Mustermann"
        #expect(ContactFormatter.addressText(for: c, chosen: nil, region: "DE") == "Max Mustermann")
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

    @Test(arguments: [String.Encoding.utf16LittleEndian, .utf16BigEndian])
    func utf16CSVWithBOM(encoding: String.Encoding) throws {
        let url = temp("a.csv")
        defer { try? FileManager.default.removeItem(at: url) }
        let bom: [UInt8] = encoding == .utf16LittleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF]
        try (Data(bom) + #require("Name\nMüller\n".data(using: encoding))).write(to: url)
        #expect(try ImportHelpers.loadCSV(url: url).rows[0]["Name"] == "Müller")
    }

    @Test func largeImageIsCapped() throws {
        let url = temp("big.png")
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(width: 5000, height: 100, to: url)
        let image = try ImportHelpers.loadImage(url: url)
        #expect(image.width == 4096)
        #expect(image.height < 100)
    }

    @Test func exifOrientationIsApplied() throws {
        let url = temp("o.jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeImage(width: 40, height: 20, type: .jpeg, orientation: 6, to: url)
        let image = try ImportHelpers.loadImage(url: url)
        #expect(image.width == 20 && image.height == 40)
    }

    @Test @MainActor func latestImportWinsAndSuccessClearsError() async throws {
        let a = temp("a.csv"), b = temp("b.csv"), bad = temp("bad.csv")
        defer { for u in [a, b, bad] { try? FileManager.default.removeItem(at: u) } }
        try Data("N\n1\n".utf8).write(to: a)
        try Data("N\n1\n2\n".utf8).write(to: b)
        try Data("N\n".utf8).write(to: bad)
        let model = makeViewModel(printers: [], remembered: nil)
        model.startImport([bad])
        await model.finishImport()
        #expect(model.importError != nil && model.showsImportError)
        model.showsImportError = false
        model.startImport([a])
        model.startImport([b])
        await model.finishImport()
        #expect(model.document.csv?.rows.count == 2)
        #expect(model.importError == nil)
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
    try writeImage(width: width, height: height, type: .png, orientation: nil, to: url)
}

private func writeImage(width: Int, height: Int, type: UTType, orientation: Int?, to url: URL) throws {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
    let props: CFDictionary? = orientation.map { [kCGImagePropertyOrientation: $0] as CFDictionary }
    CGImageDestinationAddImage(destination, image, props)
    #expect(CGImageDestinationFinalize(destination))
}
