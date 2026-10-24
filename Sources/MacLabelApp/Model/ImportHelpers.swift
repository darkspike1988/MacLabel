import CoreGraphics
import Foundation
import ImageIO
import MacLabelKit
import UniformTypeIdentifiers

/// Reading CSV and picture files, and routing dropped or chosen files into the document.
public enum ImportHelpers {
    public enum Kind: Sendable, Equatable { case csv, image }

    struct UnreadableImage: Error, LocalizedError {
        var errorDescription: String? { String(localized: "This file is not a picture the app can read.", bundle: L10n.bundle) }
    }

    /// CSV (`csv`, `txt`) or a picture type, judged by the file extension; `nil` for anything else.
    public static func kind(of url: URL) -> Kind? {
        let ext = url.pathExtension.lowercased()
        if ext == "csv" || ext == "txt" { return .csv }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .image) { return .image }
        return nil
    }

    /// Reads the file in UTF-8 (falling back to Windows-1252, as Excel writes it) and parses it.
    public static func loadCSV(url: URL) throws -> CSVTable {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        let table = try CSVTable(parsing: text)
        guard !table.rows.isEmpty else { throw DocumentError.emptyCSV }
        return table
    }

    public static func loadImage(url: URL) throws -> CGImage {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw UnreadableImage() }
        return image
    }

    /// Off the main actor, so large files never block the window.
    @concurrent static func loadCSVInBackground(url: URL) async throws -> CSVTable { try loadCSV(url: url) }
    @concurrent static func loadImageInBackground(url: URL) async throws -> CGImage { try loadImage(url: url) }

    /// Uses the first supported file: a picture switches to the Image layout, a CSV becomes the series.
    /// Returns `false` (and changes nothing) when no file is supported; throws when reading fails.
    @MainActor
    @discardableResult
    public static func importFiles(_ urls: [URL], into model: AppModel) async throws -> Bool {
        guard let url = urls.first(where: { kind(of: $0) != nil }), let kind = kind(of: url) else { return false }
        switch kind {
        case .csv:
            model.document.csv = try await loadCSVInBackground(url: url)
        case .image:
            let image = try await loadImageInBackground(url: url)
            model.document.image = image
            model.document.layout = .image
        }
        return true
    }
}
