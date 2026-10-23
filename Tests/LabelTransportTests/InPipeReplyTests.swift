import Testing
@testable import LabelTransport

@Suite struct InPipeReplyTests {
    @Test func statusTakesLastByteWhenSeveralArrive() {
        #expect(InPipeReply.reply(from: [0x23, 0x03], maxLength: 1) == [0x03])
        #expect(InPipeReply.reply(from: [0x03], maxLength: 1) == [0x03])
        #expect(InPipeReply.reply(from: [], maxLength: 1) == [])
    }
    @Test func replyWithinLimitIsUnchanged() {
        #expect(InPipeReply.reply(from: [1, 2, 3], maxLength: 64) == [1, 2, 3])
    }
    @Test func bufferIsAtLeastOnePacket() {
        #expect(InPipeReply.bufferLength(maxLength: 1, packetSize: 64) == 64)
        #expect(InPipeReply.bufferLength(maxLength: 64, packetSize: 64) == 64)
        #expect(InPipeReply.bufferLength(maxLength: 65, packetSize: 64) == 128)
        #expect(InPipeReply.bufferLength(maxLength: 1, packetSize: 0) == 1)
    }
    @Test func drainStopsWhenPipeIsEmpty() {
        var chunks: [[UInt8]] = [[0x03], [0x03], []]
        var calls = 0
        let drained = InPipeReply.drain { calls += 1; return chunks.removeFirst() }
        #expect(calls == 3 && drained == 2)
    }
    @Test func drainStopsOnTimeout() {
        var calls = 0
        let drained = InPipeReply.drain { calls += 1; throw TransportError.timeout }
        #expect(calls == 1 && drained == 0)
    }
    @Test func drainIsBounded() {
        var calls = 0
        let drained = InPipeReply.drain { calls += 1; return [0x03] }
        #expect(calls == 10 && drained == 10)
    }
}
