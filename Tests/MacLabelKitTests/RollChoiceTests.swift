import Foundation
import LabelMedia
import LabelProtocol
import LabelTransport
import Testing
@testable import MacLabelKit

@Suite struct RollChoiceTests {
    @Test func sameSizePrefersStandard() {
        guard case .resolved(let r, let alt) = RollChoice.choose(query: "32x57", catalog: .bundled, remembered: nil) else {
            Issue.record("not resolved"); return
        }
        #expect(r.id == "11354")
        #expect(alt.map(\.id).contains("1933084"))
    }

    @Test func exactSku() {
        guard case .resolved(let r, _) = RollChoice.choose(query: "S0722540", catalog: .bundled, remembered: nil) else {
            Issue.record("not resolved"); return
        }
        #expect(r.id == "11354")
    }

    @Test func rememberedUsedWithoutQuery() {
        guard case .resolved(let r, _) = RollChoice.choose(query: nil, catalog: .bundled, remembered: "30251") else {
            Issue.record("not resolved"); return
        }
        #expect(r.id == "30251")
    }

    @Test func noneWithoutQueryOrMemory() {
        guard case .none = RollChoice.choose(query: nil, catalog: .bundled, remembered: nil) else {
            Issue.record("expected none"); return
        }
    }

    @Test func differentSizesAmbiguous() {
        guard case .ambiguous(let list) = RollChoice.choose(query: "adress", catalog: .bundled, remembered: nil) else {
            Issue.record("expected ambiguous"); return
        }
        #expect(list.count > 1)
    }

    private func printer(_ pid: UInt16, serial: String? = nil) -> DiscoveredPrinter {
        DiscoveredPrinter(id: UInt64(pid), model: PrinterModel.lookup(productID: pid)!, serialNumber: serial, locationID: nil)
    }

    @Test func selectionPrefersClassic() throws {
        let se450 = printer(0x24), lw450 = printer(0x20)
        #expect(try PrinterSelection.select(serial: nil, from: [se450, lw450]) == lw450)
        #expect(throws: PrinterSelectionError.unsupported(modelName: "LabelWriter SE450")) {
            try PrinterSelection.select(serial: nil, from: [se450])
        }
        #expect(throws: PrinterSelectionError.noPrinter) { try PrinterSelection.select(serial: nil, from: []) }
    }

    @Test func selectionBySerial() throws {
        let a = printer(0x20, serial: "A"), b = printer(0x21, serial: "B"), se = printer(0x24, serial: "S")
        #expect(try PrinterSelection.select(serial: "B", from: [a, b]) == b)
        #expect(throws: PrinterSelectionError.serialNotFound("Z")) { try PrinterSelection.select(serial: "Z", from: [a]) }
        #expect(throws: PrinterSelectionError.unsupported(modelName: "LabelWriter SE450")) {
            try PrinterSelection.select(serial: "S", from: [a, se])
        }
    }
}
