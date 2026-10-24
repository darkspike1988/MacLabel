import Foundation
import LabelMedia

/// Chooses the language from the user's preferred languages (SwiftPM-built executables have no Info.plist).
/// Mirrors `MacLabelKit.localizedBundle(preferred:)`, but over the app's own catalog.
func localizedBundle(preferred: [String]) -> Bundle {
    let base = appResourceBundle
    let langs = Bundle.preferredLocalizations(from: base.localizations, forPreferences: preferred)
    for lang in langs {
        if let path = base.path(forResource: lang, ofType: "lproj"), let b = Bundle(path: path) { return b }
    }
    return base
}

private let appResourceBundle: Bundle = {
    ResourceLocator.bundle(named: "MacLabelKit_MacLabelApp", fallback: Bundle.module)!
}()

enum L10n {
    static var bundle: Bundle { localizedBundle(preferred: Locale.preferredLanguages) }
}
