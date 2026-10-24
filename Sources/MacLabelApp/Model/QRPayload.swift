import Foundation

public enum QRKind: String, CaseIterable, Sendable {
    case text, url, wifi, contact
}

/// Builds the text encoded into a QR code for each kind of content.
public enum QRPayload {
    public static func make(
        kind: QRKind,
        text: String,
        ssid: String,
        password: String,
        security: String,
        name: String,
        phone: String,
        email: String
    ) -> String {
        switch kind {
        case .text:
            return text
        case .url:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            if trimmed.isEmpty || lower.contains("://") || keepSchemes.contains(where: lower.hasPrefix) { return trimmed }
            return "https://" + trimmed
        case .wifi:
            return "WIFI:T:\(security);S:\(escapeWifi(ssid));P:\(escapeWifi(password));;"
        case .contact:
            var lines = ["BEGIN:VCARD", "VERSION:3.0"]
            if !name.isEmpty {
                lines.append("N:;\(escapeVCard(name));;;")
                lines.append("FN:\(escapeVCard(name))")
            }
            if !phone.isEmpty { lines.append("TEL:\(escapeVCard(phone))") }
            if !email.isEmpty { lines.append("EMAIL:\(escapeVCard(email))") }
            lines.append("END:VCARD")
            return lines.joined(separator: "\r\n")
        }
    }

    private static let keepSchemes = ["mailto:", "tel:", "sms:", "smsto:", "geo:", "wifi:", "http:", "https:", "ftp:"]

    /// RFC 2426 text escaping.
    private static func escapeVCard(_ s: String) -> String {
        var out = ""
        for c in s {
            switch c {
            case "\\": out += "\\\\"
            case ",": out += "\\,"
            case ";": out += "\\;"
            case "\n", "\r\n", "\r": out += "\\n"
            default: out.append(c)
            }
        }
        return out
    }

    private static func escapeWifi(_ s: String) -> String {
        var out = ""
        for c in s {
            if #"\;,:""#.contains(c) { out.append("\\") }
            out.append(c)
        }
        return out
    }
}
