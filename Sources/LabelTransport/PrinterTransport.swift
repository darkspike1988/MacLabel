import Foundation
import IOKit
import LabelProtocol

/// A byte pipe to a label printer (USB device, file, ...).
public protocol PrinterTransport: Sendable {
    func write(_ bytes: [UInt8]) async throws
    func read(maxLength: Int, timeout: Duration) async throws -> [UInt8]
    func close() async
}

public enum TransportError: Error, Equatable {
    case notFound
    /// The interface is held exclusively by another client (CUPS, DYMO software): `kIOReturnExclusiveAccess`.
    case busy
    case timeout
    case disconnected
    /// Any other IOReturn code.
    case ioFailure(Int32)
}

extension TransportError {
    /// `kIOUSBTransactionTimeout` (iokit_usb_err(0x51)); not exported by the macOS SDK headers.
    static let usbTransactionTimeout = Int32(bitPattern: 0xE000_4051)

    init(ioReturn: IOReturn) {
        switch ioReturn {
        case kIOReturnExclusiveAccess: self = .busy
        case kIOReturnTimeout, Self.usbTransactionTimeout: self = .timeout
        case kIOReturnNoDevice, kIOReturnNotResponding, kIOReturnAborted: self = .disconnected
        default: self = .ioFailure(ioReturn)
        }
    }

    /// Maps an error thrown by IOUSBHost (an `NSError` whose code is the IOReturn) to a `TransportError`.
    init(error: any Error) {
        if let transportError = error as? TransportError {
            self = transportError
            return
        }
        self.init(ioReturn: IOReturn(truncatingIfNeeded: (error as NSError).code))
    }
}

extension PrinterTransport {
    /// Sends `ESC A` and decodes the single status byte.
    public func status() async throws -> LWStatus {
        try await write(LWClassicEncoder.statusRequest)
        guard let byte = try await read(maxLength: 1, timeout: .seconds(2)).first else {
            throw TransportError.timeout
        }
        return LWStatus(raw: byte)
    }

    /// Sends `ESC V` and parses the reply; `nil` if the reply is not a version string.
    public func version() async throws -> LWVersion? {
        try await write(LWClassicEncoder.versionRequest)
        return LWVersion(response: try await read(maxLength: 64, timeout: .seconds(2)))
    }
}
