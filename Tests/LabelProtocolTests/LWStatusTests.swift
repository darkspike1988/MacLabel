import Testing
@testable import LabelProtocol

@Suite struct LWStatusTests {
    @Test func readyStatus() {
        let s = LWStatus(raw: 0x03)
        #expect(s.isReady && s.isTopOfForm && s.canPrint && !s.isPaperOut)
    }
    @Test func paperOut() {
        let s = LWStatus(raw: 0xA0)
        #expect(s.isPaperOut && s.hasError && !s.canPrint)
    }
    @Test func jam() { #expect(LWStatus(raw: 0x41).isJammed) }
    @Test func versionFromRealDevice() {
        let v = LWVersion(response: Array("1750111f0J".utf8))!
        #expect(v.modelNumber == "1750111")
        #expect(v.firmware == "f0J")
    }
    @Test func versionTooShort() { #expect(LWVersion(response: Array("123".utf8)) == nil) }
    @Test func versionNonDigits() { #expect(LWVersion(response: Array("17501x1f0J".utf8)) == nil) }
    @Test func versionTrimsPadding() {
        let v = LWVersion(response: Array("1750111f0J".utf8) + [0x20, 0x00])!
        #expect(v.firmware == "f0J")
    }
}
