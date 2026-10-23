import Foundation
import LabelProtocol

/// Writes every byte to a file instead of a printer (dry runs, tests).
/// `read` answers an `ESC A` request with a ready status (`0x03`) and anything else with no bytes.
public actor FileTransport: PrinterTransport {
    private let url: URL
    private var handle: FileHandle?
    private var lastWrite: [UInt8] = []
    private var isClosed = false

    public init(url: URL) {
        self.url = url
    }

    public func write(_ bytes: [UInt8]) throws {
        guard !isClosed else { throw TransportError.disconnected }
        if handle == nil {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
            }
            handle = try FileHandle(forWritingTo: url)
        }
        try handle?.write(contentsOf: bytes)
        lastWrite = bytes
    }

    public func read(maxLength: Int, timeout: Duration) throws -> [UInt8] {
        guard !isClosed else { throw TransportError.disconnected }
        return lastWrite == LWClassicEncoder.statusRequest && maxLength > 0 ? [0x03] : []
    }

    public func transact(_ request: [UInt8], maxLength: Int, timeout: Duration) throws -> [UInt8] {
        try write(request)
        return try read(maxLength: maxLength, timeout: timeout)
    }

    public func close() {
        guard !isClosed else { return }
        isClosed = true
        try? handle?.close()
        handle = nil
    }
}
