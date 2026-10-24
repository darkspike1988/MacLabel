import SwiftUI
import UniformTypeIdentifiers

/// A CSV series: choose or drop a file, see its columns and rows, remove it.
struct CSVSection: View {
    @Environment(AppModel.self) private var model
    @State private var choosingFile = false

    var body: some View {
        Section {
            if let csv = model.document.csv {
                LabeledContent(L10n.string("Columns"), value: csv.headers.joined(separator: ", "))
                LabeledContent(L10n.string("Rows"), value: csv.rows.count, format: .number)
                Button(L10n.string("Remove CSV"), systemImage: "trash", role: .destructive, action: remove)
            } else {
                Button(L10n.string("Choose CSV File …"), systemImage: "tablecells", action: chooseFile)
            }
        } header: {
            Text(verbatim: "CSV")
        } footer: {
            Text(L10n.string("Each row becomes a label. Use {column} placeholders, or drop a CSV file here."))
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]) { result in
            if case .success(let url) = result { model.startImport([url]) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let csvs = urls.filter { ImportHelpers.kind(of: $0) == .csv }
            guard !csvs.isEmpty else { return false }
            model.startImport(csvs)
            return true
        }
    }

    private func chooseFile() { choosingFile = true }

    private func remove() {
        model.document.csv = nil
    }
}
