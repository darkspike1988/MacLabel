import Testing
@testable import LabelProtocol

@Suite struct PrinterModelTests {
    @Test func lw450Lookup() {
        let m = PrinterModel.lookup(productID: 0x20)!
        #expect(m.name == "LabelWriter 450")
        #expect(m.family == .lwClassic)
        #expect(m.headDots == 672)
        #expect(m.supports600lpi)
    }
    @Test func fourXL() { #expect(PrinterModel.lookup(productID: 0x1F)!.headDots == 1248) }
    @Test func twinTurbo() { #expect(PrinterModel.lookup(productID: 0x22)!.hasTwinRolls) }
    @Test func lw550IsV2() { #expect(PrinterModel.lookup(productID: 0x28)!.family == .lwV2) }
    @Test func se450Unsupported() { #expect(PrinterModel.lookup(productID: 0x24)!.family == .unsupported) }
    @Test func unknownPID() { #expect(PrinterModel.lookup(productID: 0x7777) == nil) }
    @Test func vendorID() { #expect(PrinterModel.vendorID == 0x0922) }
    @Test func uniquePIDs() { #expect(Set(PrinterModel.all.map(\.productID)).count == PrinterModel.all.count) }
    @Test func only450Family600lpi() {
        let with600 = Set(PrinterModel.all.filter(\.supports600lpi).map(\.productID))
        #expect(with600 == [0x20, 0x21, 0x22, 0x23])
    }
    @Test func twinRollsOnly() {
        #expect(Set(PrinterModel.all.filter(\.hasTwinRolls).map(\.productID)) == [0x18, 0x22])
    }
    @Test func unsupportedHeads() {
        #expect(PrinterModel.lookup(productID: 0x2A)!.headDots == 1248)
        #expect(PrinterModel.lookup(productID: 0x24)!.headDots == 448)
        #expect(PrinterModel.lookup(productID: 0x06)!.headDots == 464)
        #expect(PrinterModel.lookup(productID: 0x27)!.headDots == 672)
    }
    @Test func qualityLines() {
        #expect(PrintQuality.text.linesPerInch == 300)
        #expect(PrintQuality.graphics.linesPerInch == 600)
    }
}
