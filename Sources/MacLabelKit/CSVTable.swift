import Foundation

public enum CSVError: Error, Equatable {
    case noHeader
    /// 1-based physical line on which the unterminated quoted field starts.
    case unterminatedQuote(line: Int)
}

extension CSVError: LocalizedError {
    public var errorDescription: String? { text(bundle: L10n.bundle) }

    func text(bundle: Bundle) -> String {
        switch self {
        case .noHeader: String(localized: "The CSV file is empty.", bundle: bundle)
        case .unterminatedQuote(let line): String(localized: "CSV: unterminated quote on line \(line).", bundle: bundle)
        }
    }
}

/// A parsed CSV file (German Excel flavour supported: `;` delimiter, UTF-8 BOM, CRLF).
///
/// - The delimiter (`;`, `,` or tab) is detected from the first non-blank line, counting only
///   occurrences outside quotes. If that line has none, the file is single-column and is never split. Ties prefer `;`, then `,`, then tab.
/// - Header names are trimmed. With duplicate header names the later column wins.
/// - Rows with fewer fields than headers get `""` for the missing ones; extra fields are ignored.
/// - Blank lines are ignored.
public struct CSVTable: Sendable, Equatable {
    public let headers: [String]
    public let rows: [[String: String]]

    public init(parsing text: String) throws {
        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }

        let delimiter = Self.detectDelimiter(scalars)
        let records = try Self.parseRecords(scalars, delimiter: delimiter)
        guard let headerRecord = records.first else { throw CSVError.noHeader }

        let headers = headerRecord.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var rows: [[String: String]] = []
        for record in records.dropFirst() {
            var row: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                row[header] = index < record.count ? record[index] : ""
            }
            rows.append(row)
        }
        self.headers = headers
        self.rows = rows
    }

    /// Looks only at the first non-blank line. No delimiter there means a single-column file (nil).
    private static func detectDelimiter(_ scalars: [Unicode.Scalar]) -> Unicode.Scalar? {
        var counts: [Unicode.Scalar: Int] = [";": 0, ",": 0, "\t": 0]
        var inQuotes = false
        var sawContent = false
        for s in scalars {
            if s == "\"" { inQuotes.toggle(); sawContent = true; continue }
            if inQuotes { continue }
            if s == "\n" || s == "\r" {
                if sawContent { break }
                continue // skip genuinely blank lines
            }
            sawContent = true
            if counts[s] != nil { counts[s]! += 1 }
        }
        var best: Unicode.Scalar?
        var bestCount = 0
        for candidate in [";", ",", "\t"] as [Unicode.Scalar] where counts[candidate]! > bestCount {
            best = candidate
            bestCount = counts[candidate]!
        }
        return best
    }

    private static func parseRecords(_ scalars: [Unicode.Scalar], delimiter: Unicode.Scalar?) throws -> [[String]] {
        var records: [[String]] = []
        var fields: [String] = []
        var field = String.UnicodeScalarView()
        var fieldWasQuoted = false
        var inQuotes = false
        var line = 1
        var quoteStartLine = 1
        var i = 0

        func endField() {
            fields.append(String(field))
            field = String.UnicodeScalarView()
            fieldWasQuoted = false
        }
        func endRecord() {
            endField()
            // Ignore blank lines (a single empty unquoted field).
            let blank = fields.count == 1 && fields[0].isEmpty && !recordHadQuote
            if !blank { records.append(fields) }
            fields = []
            recordHadQuote = false
        }
        var recordHadQuote = false

        while i < scalars.count {
            let s = scalars[i]
            if inQuotes {
                if s == "\"" {
                    if i + 1 < scalars.count, scalars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    if s == "\n" { line += 1 }
                    field.append(s)
                }
            } else if s == "\"" && field.isEmpty && !fieldWasQuoted {
                inQuotes = true
                fieldWasQuoted = true
                recordHadQuote = true
                quoteStartLine = line
            } else if s == delimiter {
                endField()
            } else if s == "\n" || s == "\r" {
                if s == "\r", i + 1 < scalars.count, scalars[i + 1] == "\n" { i += 1 }
                endRecord()
                line += 1
            } else {
                field.append(s)
            }
            i += 1
        }
        if inQuotes { throw CSVError.unterminatedQuote(line: quoteStartLine) }
        if !field.isEmpty || !fields.isEmpty || recordHadQuote { endRecord() }
        return records
    }
}
