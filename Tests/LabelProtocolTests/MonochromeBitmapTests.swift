import Testing
@testable import LabelProtocol

@Suite struct MonochromeBitmapTests {
    @Test func bitOrderIsMSBLeft() {
        var b = MonochromeBitmap(width: 16, height: 1)
        b[0, 0] = true
        b[9, 0] = true
        #expect(Array(b.row(0)) == [0b1000_0000, 0b0100_0000])
    }

    @Test func widthNotMultipleOf8PadsRow() {
        let b = MonochromeBitmap(width: 10, height: 2)
        #expect(b.bytesPerRow == 2)
        #expect(b.row(1).count == 2)
    }

    @Test func blankRow() {
        var b = MonochromeBitmap(width: 8, height: 2)
        b[3, 1] = true
        #expect(b.isRowBlank(0))
        #expect(!b.isRowBlank(1))
    }
}
