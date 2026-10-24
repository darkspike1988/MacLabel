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
            if case .success(let url) = result { Task { _ = await load([url]) } }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.contains(where: { ImportHelpers.kind(of: $0) == .csv }) else { return false }
            Task { _ = await load(urls) }
            return true
        }
    }

    private func chooseFile() { choosingFile = true }

    private func remove() {
        model.document.csv = nil
        loadError = nil
    }

    private func load(_ urls: [URL]) async -> Bool {
        do {
            let handled = try await ImportHelpers.importFiles(urls, into: model)
            if handled { loadError = nil }
            return handled
        } catch {
            loadError = error.localizedDescription
            return false
        }
    }
}
