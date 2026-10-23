/// Pure helpers for reading replies from the bulk IN pipe.
///
/// A reply that arrives after a read has timed out stays in the pipe and would otherwise be returned
/// as the answer to the *next* request (e.g. a stale status byte). The connection therefore drains the
/// pipe after a timeout and, if a read still returns more bytes than expected, keeps the newest ones.
enum InPipeReply {
    static let maxDrainReads = 10

    /// Read buffer size: whole packets, so a device sending a full packet never overflows the buffer.
    static func bufferLength(maxLength: Int, packetSize: Int) -> Int {
        guard packetSize > 0 else { return maxLength }
        return (maxLength + packetSize - 1) / packetSize * packetSize
    }

    /// The reply for a request expecting at most `maxLength` bytes: the newest `maxLength` bytes
    /// (for a 1-byte status request, the last byte received).
    static func reply(from received: [UInt8], maxLength: Int) -> [UInt8] {
        received.count > maxLength ? Array(received.suffix(maxLength)) : received
    }

    /// Calls `readChunk` (a short-timeout read) until it returns nothing or fails, at most
    /// `maxDrainReads` times. Returns the number of bytes discarded.
    @discardableResult
    static func drain(readChunk: () throws -> [UInt8]) -> Int {
        var discarded = 0
        for _ in 0..<maxDrainReads {
            guard let chunk = try? readChunk(), !chunk.isEmpty else { break }
            discarded += chunk.count
        }
        return discarded
    }
}
