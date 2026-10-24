import Foundation

/// Finds SwiftPM resource bundles without the `fatalError` of the generated `Bundle.module`.
///
/// A command-line tool embedded in an app (or reached through a symlink) has its resources in
/// `Contents/Resources` next to `Contents/MacOS`, where the generated accessor never looks.
public enum ResourceLocator {
    /// Order: bundles beside the main bundle, `../Resources/<name>.bundle` and `<name>.bundle` relative to the
    /// symlink-resolved executable, and only then `fallback()` (the caller's `Bundle.module`, which aborts when
    /// the bundle is missing, so it is the last resort). The executable comes from `Bundle.main.executableURL`
    /// (correct even when started by bare name through a symlink on PATH), then `_NSGetExecutablePath`,
    /// and `argv[0]` only as a last resort.
    public static func bundle(named name: String, fallback: @autoclosure () -> Bundle?) -> Bundle? {
        bundle(named: name, fallback: fallback(), executableURL: currentExecutableURL())
    }

    static func currentExecutableURL() -> URL {
        if let url = Bundle.main.executableURL { return url }
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size))
        if _NSGetExecutablePath(&buffer, &size) == 0 {
            return URL(fileURLWithPath: String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
        }
        return URL(fileURLWithPath: CommandLine.arguments[0])
    }

    static func bundle(named name: String, fallback: @autoclosure () -> Bundle?, executableURL: URL) -> Bundle? {
        let directory = executableURL.resolvingSymlinksInPath().deletingLastPathComponent()
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("\(name).bundle"),
            Bundle.main.resourceURL?.appendingPathComponent("\(name).bundle"),
            directory.appendingPathComponent("../Resources/\(name).bundle").standardizedFileURL,
            directory.appendingPathComponent("\(name).bundle"),
        ]
        for url in candidates.compactMap({ $0 }) {
            if let bundle = Bundle(path: url.path) { return bundle }
        }
        return fallback()
    }
}
