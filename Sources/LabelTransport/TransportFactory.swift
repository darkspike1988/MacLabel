import Foundation
import LabelProtocol

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
/// Pretends a LabelWriter 450 (serial FAKE) is attached and writes every job to `fileURL`
/// (development and tests only). Never discovers or opens a USB device.
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

public enum TransportFactories {
    /// USB printers; in debug builds `MACLABEL_FAKE_PRINTER=<path>` swaps in `FakeTransportFactory`
    /// (used by the app and the CLI). Release builds contain no fake.
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
