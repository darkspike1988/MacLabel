import Foundation
import Testing
@testable import LabelMedia

@Suite struct ResourceLocatorTests {
    @Test func locatorFindsBundleBesideSymlinkedExecutable() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("locator-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let macOS = root.appendingPathComponent("Contents/MacOS")
        let bundleDir = root.appendingPathComponent("Contents/Resources/LocatorTest.bundle")
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        let tool = macOS.appendingPathComponent("tool")
        try Data().write(to: tool)
        let linkDir = root.appendingPathComponent("bin")
        try fm.createDirectory(at: linkDir, withIntermediateDirectories: true)
        let link = linkDir.appendingPathComponent("tool")
        try fm.createSymbolicLink(at: link, withDestinationURL: tool)

        let found = ResourceLocator.bundle(named: "LocatorTest", fallback: nil, executableURL: link)
        #expect(found?.bundleURL.resolvingSymlinksInPath() == bundleDir.resolvingSymlinksInPath())
        #expect(ResourceLocator.bundle(named: "Missing", fallback: nil, executableURL: link) == nil)
    }
}
