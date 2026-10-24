import Foundation
import Testing
@testable import MacLabelKit

@Test func rememberedRollPerSerial() {
    let d = UserDefaults(suiteName: UUID().uuidString)!
    let p = RollPreferences(defaults: d)
    p.setLastRollID("11354", forPrinterSerial: "A")
    #expect(p.lastRollID(forPrinterSerial: "A") == "11354")
    #expect(p.lastRollID(forPrinterSerial: "B") == nil)
    #expect(p.lastRollID(forPrinterSerial: nil) == nil)
    p.setLastRollID("99012", forPrinterSerial: nil)
    #expect(p.lastRollID(forPrinterSerial: nil) == "99012")
    #expect(d.string(forKey: "maclabel.lastRoll.default") == "99012")
}
