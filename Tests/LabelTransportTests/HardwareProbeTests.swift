import Foundation
import Testing
@testable import LabelTransport

/// Talks to a real LabelWriter 450. Only discovery, open, `ESC A` and `ESC V` — never raster or feed commands.
@Suite struct HardwareProbeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACLABEL_HW"] == "1"))
    func realLW450StatusAndVersionOnly() async throws {
        let p = try #require(USBPrinterDiscovery.printers().first { $0.model.productID == 0x20 })
        #expect(p.serialNumber != nil && p.locationID != nil)
        let c = try USBPrinterConnection(printer: p)
        defer { Task { await c.close() } }
        // A second open of the same interface must report the exclusive-access conflict as `.busy`.
        #expect(throws: TransportError.busy) { _ = try USBPrinterConnection(printer: p) }
        #expect(try await c.status().raw & 0x01 == 0x01)
        #expect(try await c.version()?.modelNumber == "1750111")
    }
}
