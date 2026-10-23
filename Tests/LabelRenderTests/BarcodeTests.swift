import Testing
@testable import LabelRender

@Suite struct BarcodeTests {
    @Test func ean13KnownValue() throws {
        let m = try Barcode.modules(.ean13, "4006381333931")
        #expect(m.count == 95)
        #expect(Array(m.prefix(3)) == [true, false, true])
        #expect(Array(m.suffix(3)) == [true, false, true])
        #expect(Array(m[45..<50]) == [false, true, false, true, false])
    }
    @Test func ean13AppendsCheckDigit() throws { #expect(try Barcode.humanReadable(.ean13, "400638133393") == "4006381333931") }
    @Test func ean13BadCheck() { #expect(throws: BarcodeError.badCheckDigit) { try Barcode.modules(.ean13, "4006381333932") } }
    @Test func ean13BadLength() { #expect(throws: BarcodeError.invalidLength(expected: [12, 13], got: 5)) { try Barcode.modules(.ean13, "12345") } }
    @Test func ean8Length() throws {
        #expect(try Barcode.modules(.ean8, "9638507").count == 67)
        #expect(try Barcode.humanReadable(.ean8, "9638507") == "96385074")
    }
    @Test func upcALength() throws {
        #expect(try Barcode.modules(.upcA, "03600029145").count == 95)
        #expect(try Barcode.humanReadable(.upcA, "03600029145") == "036000291452")
    }
    @Test func code128Checksum() { #expect(LabelRender.code128Checksum([104, 33, 34]) == 102) }
    @Test func code128Structure() throws {
        let m = try Barcode.modules(.code128, "AB")
        #expect(m.count == 11 * 4 + 13)
        #expect(m.prefix(11).map { $0 ? "1" : "0" }.joined() == "11010010000")
        #expect(m.suffix(13).map { $0 ? "1" : "0" }.joined() == "1100011101011")
    }
    @Test func code128UsesSetCForDigits() throws { #expect(try Barcode.modules(.code128, "123456").count == 11 * 5 + 13) }
    @Test func code128OddDigitRunStartsInB() throws {
        // StartB, '1', CodeC, 2 pairs, check, stop
        #expect(try Barcode.modules(.code128, "12345").count == 11 * 6 + 13)
    }
    @Test func code128SwitchesToCMidString() throws {
        // StartB, 'A', CodeC, 2 pairs, check, stop
        #expect(try Barcode.modules(.code128, "A1234").count == 11 * 6 + 13)
    }
    @Test func code128RejectsUmlaut() { #expect(throws: BarcodeError.invalidCharacter("ä")) { try Barcode.modules(.code128, "ä") } }
    @Test func code39Uppercases() throws { #expect(try Barcode.humanReadable(.code39, "ab-1") == "*AB-1*") }
    @Test func code39Modules() throws {
        // 6 narrow + 3 wide (x3) = 15 modules per char, 1-module gaps
        #expect(try Barcode.modules(.code39, "A").count == 15 * 3 + 2)
    }
    @Test func code39RejectsStar() { #expect(throws: BarcodeError.invalidCharacter("*")) { try Barcode.modules(.code39, "A*B") } }
    @Test func itf14() throws { #expect(try Barcode.humanReadable(.itf14, "1540014128876") == "15400141288763") }
    @Test func itf14Modules() throws {
        let m = try Barcode.modules(.itf14, "1540014128876")
        #expect(m.prefix(4).map { $0 } == [true, false, true, false])
        #expect(m.suffix(5).map { $0 } == [true, true, true, false, true])
        #expect(m.count == 4 + 14 * 9 + 5)
    }
    @Test func qrMatrixSquare() throws {
        let q = try QRMatrix.modules("https://example.com")
        #expect(q.count == q[0].count)
        #expect(q.count >= 21)
        #expect(q[0][0] && q[0][6] && q[6][0]) // finder pattern corner
    }
    @Test func emptyRejected() {
        #expect(throws: BarcodeError.empty) { try Barcode.modules(.code128, "") }
        #expect(throws: BarcodeError.empty) { try QRMatrix.modules("") }
    }
}
