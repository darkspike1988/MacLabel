import Testing
@testable import LabelProtocol

@Suite struct LWClassicEncoderTests {
    @Test func headerTextNormal() {
        let h = LWClassicEncoder.jobHeader(.init(labels: [], labelLengthLines: 100, quality: .text, density: .normal))
        #expect(h.count == 156 + 2 + 4 + 3 + 2 + 2)
        #expect(Array(h.prefix(156)) == Array(repeating: 0x1B, count: 156))
        #expect(Array(h.suffix(13)) == [0x1B,0x40, 0x1B,0x51,0,0, 0x1B,0x42,0, 0x1B,0x68, 0x1B,0x65])
    }
    @Test func headerGraphicsDarkTwinLeft() {
        let h = LWClassicEncoder.jobHeader(.init(labels: [], labelLengthLines: 1, quality: .graphics, density: .dark, twinRoll: .left))
        #expect(Array(h.suffix(7)) == [0x1B,0x69, 0x1B,0x67, 0x1B,0x71,0x31])
    }
    @Test func labelLengthBigEndian() {
        #expect(Array(LWClassicEncoder.label(MonochromeBitmap(width: 16, height: 0), lengthLines: 0x0123).prefix(4)) == [0x1B,0x4C,0x01,0x23])
    }
    @Test func continuousLength() {
        #expect(Array(LWClassicEncoder.label(MonochromeBitmap(width: 16, height: 0), lengthLines: nil).prefix(4)) == [0x1B,0x4C,0xFF,0xFF])
    }
    @Test func tieUsesSYN() {
        var b = MonochromeBitmap(width: 16, height: 1); for x in 0..<8 { b[x,0] = true }
        #expect(Array(LWClassicEncoder.label(b, lengthLines: 1).dropFirst(7)) == [0x16, 0xFF, 0x00])
    }
    @Test func allBlackUsesETB() {
        var b = MonochromeBitmap(width: 16, height: 1); for x in 0..<16 { b[x,0] = true }
        #expect(Array(LWClassicEncoder.label(b, lengthLines: 1).dropFirst(7)) == [0x17, 0x8F])
    }
    @Test func rleSplitsRunsLongerThan128() {
        var b = MonochromeBitmap(width: 672, height: 1); for x in 0..<672 { b[x,0] = true }
        #expect(Array(LWClassicEncoder.label(b, lengthLines: 1).dropFirst(7)) == [0x17, 0xFF,0xFF,0xFF,0xFF,0xFF, 0x9F])
    }
    @Test func blankRowsCollapse() {
        let b = MonochromeBitmap(width: 16, height: 300)
        #expect(Array(LWClassicEncoder.label(b, lengthLines: 300).dropFirst(7)) == [0x1B,0x66,0x01,0xFF, 0x1B,0x66,0x01,0x2D])
    }
    @Test func bytesPerLineSent() {
        #expect(Array(LWClassicEncoder.label(MonochromeBitmap(width: 672, height: 0), lengthLines: 1)[4..<7]) == [0x1B,0x44,84])
    }
    @Test func twoLabelJob() {
        let b = MonochromeBitmap(width: 16, height: 0)
        let bytes = LWClassicEncoder.encode(.init(labels: [b, b], labelLengthLines: 5, quality: .text, density: .normal))
        let l = LWClassicEncoder.label(b, lengthLines: 5)
        #expect(bytes == LWClassicEncoder.jobHeader(.init(labels: [], labelLengthLines: 5, quality: .text, density: .normal)) + l + [0x1B,0x47] + l + [0x1B,0x45])
    }
    @Test func zeroLabelJob() {
        let job = LWClassicJob(labels: [], labelLengthLines: 5, quality: .text, density: .normal)
        #expect(LWClassicEncoder.encode(job) == LWClassicEncoder.jobHeader(job) + [0x1B,0x45])
    }
    @Test func blankRunsBetweenInkRows() {
        var b = MonochromeBitmap(width: 16, height: 3)
        b[0, 1] = true
        let body = Array(LWClassicEncoder.label(b, lengthLines: 3).dropFirst(7))
        #expect(body == [0x1B,0x66,0x01,0x01, 0x16,0x80,0x00, 0x1B,0x66,0x01,0x01])
    }
    @Test func constants() {
        #expect(LWClassicEncoder.resync == Array(repeating: 0x1B, count: 156))
        #expect(LWClassicEncoder.statusRequest == [0x1B,0x41])
        #expect(LWClassicEncoder.versionRequest == [0x1B,0x56])
        #expect(LWClassicEncoder.betweenLabels == [0x1B,0x47])
        #expect(LWClassicEncoder.endOfJob == [0x1B,0x45])
    }
}
