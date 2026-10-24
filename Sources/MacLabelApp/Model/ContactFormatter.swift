import Contacts
import Foundation

/// Turns a contact into the lines of an address label.
public enum ContactFormatter {
    /// Name, organisation (if any), then the postal address in the country's own order.
    /// The country line is left out when the address is in `region` (default: the user's region).
    public static func addressText(
        name: String, organization: String?, postal: CNPostalAddress?,
        region: String? = Locale.current.region?.identifier
    ) -> String {
        var lines = [name, organization ?? ""]
        if let postal {
            var text = CNPostalAddressFormatter.string(from: postal, style: .mailingAddress)
            if let region, postal.isoCountryCode.caseInsensitiveCompare(region) == .orderedSame, !postal.country.isEmpty {
                let country = postal.country
                lines += text.components(separatedBy: "\n").filter { $0.caseInsensitiveCompare(country) != .orderedSame }
                text = ""
            }
            if !text.isEmpty { lines += text.components(separatedBy: "\n") }
        }
        return lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
