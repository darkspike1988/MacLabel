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
