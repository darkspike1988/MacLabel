import Foundation
import LabelProtocol
import LabelTransport

/// Finds printers and opens a byte pipe to one of them.
public protocol TransportFactory: Sendable {
    func printers() -> [DiscoveredPrinter]
    func open(_ printer: DiscoveredPrinter) throws -> any PrinterTransport
}

/// Real USB printers via IOUSBHost.
public struct USBTransportFactory: TransportFactory {
    public init() {}

    public func printers() -> [DiscoveredPrinter] { USBPrinterDiscovery.printers() }

    public func open(_ printer: DiscoveredPrinter) throws -> any PrinterTransport {
        try USBPrinterConnection(printer: printer)
    }
}

#if DEBUG
/// Pretends a LabelWriter 450 is attached and writes every job to `fileURL` (development only).
public struct FakeTransportFactory: TransportFactory {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func printers() -> [DiscoveredPrinter] {
        [DiscoveredPrinter(id: 1, model: PrinterModel.lookup(productID: 0x20)!, serialNumber: "FAKE", locationID: nil)]
    }

    public func open(_ printer: DiscoveredPrinter) throws -> any PrinterTransport {
        FileTransport(url: fileURL)
    }
}
#endif

extension LabelPrinter {
    /// USB printers; in debug builds `MACLABEL_FAKE_PRINTER=<path>` swaps in `FakeTransportFactory`.
    public static func makeDefault(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any TransportFactory {
        #if DEBUG
        if let path = environment["MACLABEL_FAKE_PRINTER"], !path.isEmpty {
            return FakeTransportFactory(fileURL: URL(fileURLWithPath: path))
        }
        #endif
        return USBTransportFactory()
    }
}
