import Foundation
import IOKit
import LabelProtocol

/// A DYMO printer interface found in the IORegistry.
public struct DiscoveredPrinter: Sendable, Hashable, Identifiable {
    /// Registry entry ID of the printer-class `IOUSBHostInterface`.
    public let id: UInt64
    public let model: PrinterModel
    public let serialNumber: String?
    public let locationID: UInt32?
}

public enum USBPrinterDiscovery {
    /// All attached DYMO printer interfaces with a known product ID (including `unsupported` models).
    public static func printers() -> [DiscoveredPrinter] {
        let matching = IOServiceMatching("IOUSBHostInterface") as NSMutableDictionary
        matching["IOPropertyMatch"] = ["idVendor": Int(PrinterModel.vendorID), "bInterfaceClass": 7] as NSDictionary
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching as CFDictionary, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var result: [DiscoveredPrinter] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let printer = printer(for: service) { result.append(printer) }
        }
        return result.sorted { $0.id < $1.id }
    }

    private static func printer(for interface: io_service_t) -> DiscoveredPrinter? {
        guard let productID = (property("idProduct", of: interface) as? NSNumber)?.uint16Value,
              let model = PrinterModel.lookup(productID: productID) else { return nil }
        var entryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(interface, &entryID) == KERN_SUCCESS else { return nil }

        let device = parentDevice(of: interface)
        defer { if device != 0 { IOObjectRelease(device) } }
        let serial = device == 0 ? nil
            : (property("USB Serial Number", of: device) ?? property("kUSBSerialNumberString", of: device)) as? String
        let location = device == 0 ? nil : (property("locationID", of: device) as? NSNumber)?.uint32Value
        return DiscoveredPrinter(id: entryID, model: model, serialNumber: serial, locationID: location)
    }

    /// Walks up the service plane to the owning `IOUSBHostDevice`. Returns a retained object or 0.
    private static func parentDevice(of interface: io_service_t) -> io_registry_entry_t {
        var current = interface
        IOObjectRetain(current)
        for _ in 0..<4 {
            var parent: io_registry_entry_t = 0
            let kr = IORegistryEntryGetParentEntry(current, "IOService", &parent)
            IOObjectRelease(current)
            guard kr == KERN_SUCCESS, parent != 0 else { return 0 }
            if IOObjectConformsTo(parent, "IOUSBHostDevice") != 0 { return parent }
            current = parent
        }
        IOObjectRelease(current)
        return 0
    }

    private static func property(_ key: String, of entry: io_registry_entry_t) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
