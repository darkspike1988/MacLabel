import Foundation
import IOKit
import IOUSBHost
import LabelProtocol

/// An open bulk connection to a printer-class USB interface.
///
/// The IOUSBHost objects are not `Sendable`; they are created in `init`, stored only in actor-isolated
/// properties and never leave the actor. Transfers use the synchronous `sendIORequest` API, so a call
/// occupies the actor (and one executor thread) for at most its completion timeout.
public actor USBPrinterConnection: PrinterTransport {
    private static let chunkSize = 4096
    private static let writeTimeout: TimeInterval = 10

    private var interface: IOUSBHostInterface?
    private let outPipe: IOUSBHostPipe
    private let inPipe: IOUSBHostPipe

    public init(printer: DiscoveredPrinter) throws {
        guard let matching = IORegistryEntryIDMatching(printer.id) else { throw TransportError.notFound }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { throw TransportError.notFound }
        defer { IOObjectRelease(service) }

        let interface: IOUSBHostInterface
        do {
            interface = try IOUSBHostInterface(__ioService: service, options: [], queue: nil, interestHandler: nil)
        } catch {
            // IOUSBHost reports an interface held by another client (CUPS, DYMO software, another
            // process) as kIOReturnInternalError ("Failed [super init]"), not kIOReturnExclusiveAccess.
            // An attached user client identifies that case.
            throw Self.hasUserClient(service) ? TransportError.busy : TransportError(error: error)
        }
        do {
            let (outAddress, inAddress) = try Self.bulkEndpoints(of: interface)
            outPipe = try interface.copyPipe(withAddress: Int(outAddress))
            inPipe = try interface.copyPipe(withAddress: Int(inAddress))
        } catch {
            interface.destroy()
            throw TransportError(error: error)
        }
        self.interface = interface
    }

    isolated deinit {
        interface?.destroy()
    }

    public func write(_ bytes: [UInt8]) throws {
        guard interface != nil else { throw TransportError.disconnected }
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + Self.chunkSize, bytes.count)
            let chunk = NSMutableData(bytes: Array(bytes[offset..<end]), length: end - offset)
            var sent = 0
            do {
                try outPipe.__sendIORequest(with: chunk, bytesTransferred: &sent, completionTimeout: Self.writeTimeout)
            } catch {
                throw TransportError(error: error)
            }
            guard sent == end - offset else { throw TransportError.ioFailure(kIOReturnUnderrun) }
            offset = end
        }
    }

    public func read(maxLength: Int, timeout: Duration) throws -> [UInt8] {
        guard interface != nil else { throw TransportError.disconnected }
        guard maxLength > 0, let buffer = NSMutableData(length: maxLength) else { return [] }
        var received = 0
        do {
            try inPipe.__sendIORequest(with: buffer, bytesTransferred: &received, completionTimeout: timeout.timeInterval)
        } catch {
            throw TransportError(error: error)
        }
        return Array(UnsafeRawBufferPointer(start: buffer.bytes, count: min(received, maxLength)))
    }

    public func close() {
        interface?.destroy()
        interface = nil
    }

    /// Whether another client currently holds the interface open (a child entry with `IOUserClientCreator`).
    private static func hasUserClient(_ service: io_service_t) -> Bool {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, "IOService", &iterator) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }
        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            if let creator = IORegistryEntryCreateCFProperty(child, "IOUserClientCreator" as CFString, kCFAllocatorDefault, 0) {
                creator.release()
                return true
            }
        }
        return false
    }

    /// Bulk OUT / bulk IN endpoint addresses of the interface (0x02 / 0x82 on the LW450).
    private static func bulkEndpoints(of interface: IOUSBHostInterface) throws -> (out: UInt8, in: UInt8) {
        let configuration = interface.configurationDescriptor
        var current: UnsafePointer<IOUSBDescriptorHeader>?
        var outAddress: UInt8?
        var inAddress: UInt8?
        while let endpoint = IOUSBGetNextEndpointDescriptor(configuration, interface.interfaceDescriptor, current) {
            let address = endpoint.pointee.bEndpointAddress
            if endpoint.pointee.bmAttributes & 0x03 == 0x02 {
                if address & 0x80 != 0 { inAddress = inAddress ?? address } else { outAddress = outAddress ?? address }
            }
            current = UnsafeRawPointer(endpoint).assumingMemoryBound(to: IOUSBDescriptorHeader.self)
        }
        guard let outAddress, let inAddress else { throw TransportError.ioFailure(kIOReturnNotFound) }
        return (outAddress, inAddress)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
