import Foundation
import LabelRender

public enum BatchError: Error, Equatable {
    case unknownPlaceholder(String)
    case invalidCopies
}

extension BatchError: LocalizedError {
    public var errorDescription: String? { text(bundle: L10n.bundle) }

    func text(bundle: Bundle) -> String {
        switch self {
        case .unknownPlaceholder(let name): String(localized: "Unknown placeholder {\(name)}.", bundle: bundle)
        case .invalidCopies: String(localized: "Copies must be at least 1.", bundle: bundle)
        }
    }
}

public struct CounterSpec: Sendable, Equatable {
    public var start: Int = 1
    public var step: Int = 1
    public var minimumDigits: Int = 1

    public init(start: Int = 1, step: Int = 1, minimumDigits: Int = 1) {
        self.start = start
        self.step = step
        self.minimumDigits = minimumDigits
    }

    public func formatted(index: Int) -> String {
        let value = start + step * index
        let digits = String(abs(value))
        let padded = String(repeating: "0", count: max(0, minimumDigits - digits.count)) + digits
        return value < 0 ? "-" + padded : padded
    }
}

/// Expands one label template into a series (copies, counter, CSV rows).
///
/// Placeholders: `{n}` is the counter, `{column}` a CSV column (case-insensitive, trimmed).
/// `{n}` means the counter only when a counter is given; otherwise a CSV column "n" is used.
/// `{{` and `}}` produce literal braces. Image content passes through unchanged.
public enum LabelBatch {
    public static func expand(
        _ template: LabelContent,
        copies: Int,
        counter: CounterSpec?,
        table: CSVTable?
    ) throws -> [LabelContent] {
        guard copies >= 1 else { throw BatchError.invalidCopies }

        let rows: [[String: String]?]
        if let table {
            rows = table.rows.map { row in
                var lowered: [String: String] = [:]
                for header in table.headers { lowered[header.lowercased()] = row[header] }
                return lowered
            }
        } else {
            rows = [nil]
        }

        var result: [LabelContent] = []
        var index = 0
        for row in rows {
            for _ in 0..<copies {
                let counterText = counter?.formatted(index: index)
                result.append(try substitute(in: template, counter: counterText, row: row))
                index += 1
            }
        }
        return result
    }

    private static func substitute(in content: LabelContent, counter: String?, row: [String: String]?) throws -> LabelContent {
        func sub(_ s: String) throws -> String { try replace(s, counter: counter, row: row) }
        switch content {
        case .text(var t):
            t.text = try sub(t.text)
            return .text(t)
        case .barcode(var b):
            b.value = try sub(b.value)
            return .barcode(b)
        case .qr(var q):
            q.payload = try sub(q.payload)
            if let caption = q.caption { q.caption = try sub(caption) }
            return .qr(q)
        case .image:
            return content
        }
    }

    /// Substitutes placeholders in one string. `row` keys must be lowercased; `counter` is the formatted value.
    /// With `strict == false` unknown placeholders stay literal (`{x}`) instead of throwing.
    public static func substitute(_ text: String, row: [String: String]?, counter: String?, strict: Bool) throws -> String {
        try replace(text, counter: counter, row: row, strict: strict)
    }

    private static func replace(_ s: String, counter: String?, row: [String: String]?, strict: Bool = true) throws -> String {
        var out = ""
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "{" {
                if i + 1 < chars.count, chars[i + 1] == "{" {
                    out.append("{")
                    i += 2
                } else if let close = chars[(i + 1)...].firstIndex(of: "}") {
                    let name = String(chars[(i + 1)..<close]).trimmingCharacters(in: .whitespaces)
                    let key = name.lowercased()
                    if key == "n", let counter {
                        out += counter
                    } else if let value = row?[key] {
                        out += value
                    } else if strict {
                        throw BatchError.unknownPlaceholder(name)
                    } else {
                        out += String(chars[i...close])
                    }
                    i = close + 1
                } else {
                    out.append(c) // unclosed brace stays literal
                    i += 1
                }
            } else if c == "}" {
                out.append("}")
                i += (i + 1 < chars.count && chars[i + 1] == "}") ? 2 : 1
            } else {
                out.append(c)
                i += 1
            }
        }
        return out
    }
}
