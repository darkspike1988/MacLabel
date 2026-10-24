import Foundation
import LabelTransport

extension LabelPrinter {
    /// USB printers; in debug builds `MACLABEL_FAKE_PRINTER=<path>` swaps in `FakeTransportFactory`
    /// (shared with the CLI, see `TransportFactories`).
    public static func makeDefault(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any TransportFactory {
        TransportFactories.makeDefault(environment: environment)
    }
}
