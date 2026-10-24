import Foundation

/// Finds SwiftPM resource bundles without the `fatalError` of the generated `Bundle.module`.
///
/// A command-line tool embedded in an app (or reached through a symlink) has its resources in
/// `Contents/Resources` next to `Contents/MacOS`, where the generated accessor never looks.
public enum ResourceLocator {
    /// Order: bundles beside the main bundle, `../Resources/<name>.bundle` and `<name>.bundle` relative to the
    /// symlink-resolved executable, and only then `fallback()` (the caller's `Bundle.module`, which aborts when
    /// the bundle is missing, so it is the last resort).
    public static func bundle(named name: String, fallback: @autoclosure () -> Bundle?) -> Bundle? {
        bundle(named: name, fallback: fallback(), executableURL: URL(fileURLWithPath: CommandLine.arguments[0]))
    }

    static func bundle(named name: String, fallback: @autoclosure () -> Bundle?, executableURL: URL) -> Bundle? {
        let directory = executableURL.resolvingSymlinksInPath().deletingLastPathComponent()
        var candidates = [
            Bundle.main.bundleURL.appendingPathComponent("\(name).bundle"),
            directory.appendingPathComponent("../Resources/\(name).bundle").standardizedFileURL,
            directory.appendingPathComponent("\(name).bundle"),
        ]
        if let resources = Bundle.main.resourceURL {
            candidates.insert(resources.appendingPathComponent("\(name).bundle"), at: 1)
        }
        for url in candidates {
            if let bundle = Bundle(path: url.path) { return bundle }
        }
        return fallback()
    }
}
