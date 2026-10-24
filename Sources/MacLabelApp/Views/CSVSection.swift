import MacLabelKit
import SwiftUI
import UniformTypeIdentifiers

/// A CSV series: choose or drop a file, see its columns and rows, remove it.
struct CSVSection: View {
    @Environment(AppModel.self) private var model
    @State private var choosingFile = false
    @State private var loadError: String?

    var body: some View {
        Section {
            if let csv = model.document.csv {
                LabeledContent(L10n.string("Columns"), value: csv.headers.joined(separator: ", "))
                LabeledContent(L10n.string("Rows"), value: csv.rows.count, format: .number)
                Button(L10n.string("Remove CSV"), systemImage: "trash", role: .destructive, action: remove)
            } else {
                Button(L10n.string("Choose CSV File …"), systemImage: "tablecells", action: chooseFile)
            }
            if let loadError {
                Label(loadError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        } header: {
            Text(verbatim: "CSV")
        } footer: {
            Text(L10n.string("Each row becomes a label. Use {column} placeholders, or drop a CSV file here."))
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]) { result in
            if case .success(let url) = result { load(url) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            load(url)
            return true
        }
    }

    private func chooseFile() { choosingFile = true }

    private func remove() {
        model.document.csv = nil
        loadError = nil
    }

    /// Reads the file in UTF-8 (falling back to Windows-1252, as Excel writes it) and parses it.
    private func load(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            let table = try CSVTable(parsing: text)
            guard !table.rows.isEmpty else { throw DocumentError.emptyCSV }
            model.document.csv = table
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}
