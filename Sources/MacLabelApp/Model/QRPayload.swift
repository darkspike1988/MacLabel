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
            if trimmed.isEmpty || trimmed.contains("://") { return trimmed }
            return "https://" + trimmed
        case .wifi:
            return "WIFI:T:\(security);S:\(escapeWifi(ssid));P:\(escapeWifi(password));;"
        case .contact:
            var lines = ["BEGIN:VCARD", "VERSION:3.0"]
            if !name.isEmpty { lines.append("FN:\(name)") }
            if !phone.isEmpty { lines.append("TEL:\(phone)") }
            if !email.isEmpty { lines.append("EMAIL:\(email)") }
            lines.append("END:VCARD")
            return lines.joined(separator: "\r\n")
        }
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
