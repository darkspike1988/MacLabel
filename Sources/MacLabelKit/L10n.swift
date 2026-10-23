import Foundation

/// SwiftPM executables have no Info.plist, so the system would always pick English.
/// Choose the language from the user's preferred languages ourselves.
func localizedBundle(preferred: [String]) -> Bundle {
    let langs = Bundle.preferredLocalizations(from: Bundle.module.localizations, forPreferences: preferred)
    for lang in langs {
        if let path = Bundle.module.path(forResource: lang, ofType: "lproj"), let b = Bundle(path: path) { return b }
    }
    return Bundle.module
}

enum L10n {
    static var bundle: Bundle { localizedBundle(preferred: Locale.preferredLanguages) }
}

/// Looks up a user-facing string in the kit's catalog (German or English by preferred languages).
/// Used by the CLI so all texts live in `Localizable.xcstrings`.
public func localizedString(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: L10n.bundle)
}
