import Foundation

enum Fixtures {
    static var directory: URL {
        Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
    }

    static func bytes(_ name: String) throws -> [UInt8] {
        [UInt8](try Data(contentsOf: directory.appendingPathComponent(name)))
    }
}
