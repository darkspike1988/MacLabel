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
        let utf16 = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
        guard let text = (utf16 ? String(data: data, encoding: .utf16) : nil)
            ?? String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        let table = try CSVTable(parsing: text)
        guard !table.rows.isEmpty else { throw DocumentError.emptyCSV }
        return table
    }

    /// Longest edge, in pixels, of a loaded picture; smaller pictures keep their size.
    static let maxImagePixels = 4096

    /// Decodes eagerly (inside the sandbox access window), applies EXIF orientation and caps the size.
    public static func loadImage(url: URL) throws -> CGImage {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxImagePixels,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw UnreadableImage() }
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
            let table = try await loadCSVInBackground(url: url)
            try Task.checkCancellation()
            model.document.csv = table
        case .image:
            let image = try await loadImageInBackground(url: url)
            try Task.checkCancellation()
            model.document.image = image
            model.document.layout = .image
        }
        return true
    }
}
