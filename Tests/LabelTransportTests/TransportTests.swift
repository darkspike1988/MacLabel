import Foundation
import IOKit
import Testing
@testable import LabelTransport

@Suite struct TransportTests {
    @Test func fileTransportRecordsBytesAndFakesReady() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let t = FileTransport(url: url)
        #expect(try await t.status().isReady)
        try await t.write([1, 2, 3])
        await t.close()
        #expect(try Data(contentsOf: url) == Data([0x1B, 0x41, 1, 2, 3]))
    }

    @Test func fileTransportHasNoVersion() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let t = FileTransport(url: url)
        #expect(try await t.version() == nil)
        await t.close()
    }

    @Test func fileTransportWriteAfterCloseFails() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let t = FileTransport(url: url)
        await t.close()
        await #expect(throws: TransportError.disconnected) { try await t.write([1]) }
    }

    @Test func mapsExclusiveAccess() { #expect(TransportError(ioReturn: kIOReturnExclusiveAccess) == .busy) }
    @Test func mapsNoDevice() { #expect(TransportError(ioReturn: kIOReturnNoDevice) == .disconnected) }
    @Test func mapsNotRespondingAndAborted() {
        #expect(TransportError(ioReturn: kIOReturnNotResponding) == .disconnected)
        #expect(TransportError(ioReturn: kIOReturnAborted) == .disconnected)
    }
    @Test func mapsTimeouts() {
        #expect(TransportError(ioReturn: kIOReturnTimeout) == .timeout)
        #expect(TransportError(ioReturn: Int32(bitPattern: 0xE000_4051)) == .timeout) // kIOUSBTransactionTimeout
    }
    @Test func mapsOtherToIOFailure() {
        #expect(TransportError(ioReturn: kIOReturnNotPermitted) == .ioFailure(kIOReturnNotPermitted))
    }
    @Test func mapsNSErrorCarryingIOReturn() {
        let err = NSError(domain: NSOSStatusErrorDomain, code: Int(kIOReturnExclusiveAccess))
        #expect(TransportError(error: err) == .busy)
    }
}
