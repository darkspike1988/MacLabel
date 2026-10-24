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
    /// Chosen once per launch; macOS relaunches apps to change their language anyway.
    static let bundle: Bundle = localizedBundle(preferred: Locale.preferredLanguages)

    /// A user-facing text from the app catalog in the chosen language.
    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: bundle)
    }

    static func cancelledText(printed: Int, total: Int, preferred: [String] = Locale.preferredLanguages) -> String {
        String(
            localized: "Cancelled after \(printed) of \(total) labels. If needed, press the feed button to eject a partly printed label.",
            bundle: localizedBundle(preferred: preferred)
        )
    }
}
