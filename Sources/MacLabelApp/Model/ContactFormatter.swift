import Contacts
import Foundation

/// Turns a contact into the lines of an address label.
public enum ContactFormatter {
    /// Name, organisation (if any and different from the name), then the postal address in the
    /// country's own order. The country line is left out when the address is in `region`
    /// (default: the user's region), recognised by ISO code or by the localised country name.
    public static func addressText(
        name: String, organization: String?, postal: CNPostalAddress?,
        region: String? = Locale.current.region?.identifier, locale: Locale = .current
    ) -> String {
        var lines = [name.trimmingCharacters(in: .whitespaces)]
        if let org = organization?.trimmingCharacters(in: .whitespaces),
           org.caseInsensitiveCompare(lines[0]) != .orderedSame {
            lines.append(org)
        }
        if var postal {
            let home = isHome(postal, region: region, locale: locale)
            if home, postal.isoCountryCode.isEmpty, let region {
                // Without a code the formatter guesses the layout; use the home country's.
                let copy = postal.mutableCopy() as! CNMutablePostalAddress
                copy.isoCountryCode = region
                postal = copy
            }
            var rows = CNPostalAddressFormatter.string(from: postal, style: .mailingAddress).components(separatedBy: "\n")
            if home {
                rows.removeAll { $0.caseInsensitiveCompare(postal.country) == .orderedSame }
            }
            lines += rows
        }
        return lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// The label text for a picked contact. `chosen` is the postal address the user clicked in the
    /// picker; without it the first address is used. Fields the picker did not fetch are skipped.
    public static func addressText(
        for contact: CNContact, chosen: CNPostalAddress?,
        region: String? = Locale.current.region?.identifier, locale: Locale = .current
    ) -> String {
        let nameKeys: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]
        let name: String
        if contact.areKeysAvailable(nameKeys) {
            name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        } else {
            name = [CNContactGivenNameKey, CNContactFamilyNameKey]
                .filter { contact.isKeyAvailable($0) }
                .compactMap { $0 == CNContactGivenNameKey ? contact.givenName : contact.familyName }
                .joined(separator: " ")
        }
        let organization = contact.isKeyAvailable(CNContactOrganizationNameKey) ? contact.organizationName : nil
        let postal = chosen ?? (contact.isKeyAvailable(CNContactPostalAddressesKey) ? contact.postalAddresses.first?.value : nil)
        return addressText(name: name, organization: organization, postal: postal, region: region, locale: locale)
    }

    private static func isHome(_ postal: CNPostalAddress, region: String?, locale: Locale) -> Bool {
        guard let region, !postal.country.isEmpty else { return false }
        if postal.isoCountryCode.caseInsensitiveCompare(region) == .orderedSame { return true }
        guard postal.isoCountryCode.isEmpty, let local = locale.localizedString(forRegionCode: region) else { return false }
        return postal.country.caseInsensitiveCompare(local) == .orderedSame
    }
}
