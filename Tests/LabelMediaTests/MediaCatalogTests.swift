import Foundation
import Testing
@testable import LabelMedia

@Suite struct MediaCatalogTests {
    @Test func s0722540IsMultipurpose() {
        let r = MediaCatalog.bundled.roll(sku: "S0722540")!
        #expect(r.id == "11354")
        #expect(r.skus.contains("30334"))
        #expect(abs(r.acrossMM - 57.1) < 0.05)
        #expect(abs(r.feedMM! - 31.8) < 0.05)
        #expect(r.printable.widthDots == 651)
        #expect(r.feedDots == 375)
        #expect(r.kind == .dieCut)
        #expect(r.minHeadDots == 672)
    }
    @Test func searchBySizeAnyOrder() {
        #expect(MediaCatalog.bundled.search("32x57").first?.id == "11354")
        #expect(MediaCatalog.bundled.search("57 × 32 mm").first?.id == "11354")
    }
    @Test func searchCaseAndSpaces() {
        #expect(MediaCatalog.bundled.search(" s0722540 ").first?.id == "11354")
    }
    @Test func addressRollIsPortraitOnHead() {
        let r = MediaCatalog.bundled.roll(sku: "99010")!
        #expect(r.acrossMM < r.feedMM!)
    }
    @Test func noDuplicateSkus() {
        let all = MediaCatalog.bundled.rolls.flatMap(\.skus)
        #expect(Set(all).count == all.count)
    }
    @Test func continuousExists() {
        #expect(MediaCatalog.bundled.rolls.contains { $0.kind == .continuous && $0.feedMM == nil })
    }
    @Test func noDymoTextLeaks() throws {
        let s = try String(contentsOf: MediaCatalog.bundledResourceURL, encoding: .utf8)
        #expect(!s.contains("SearchTerms"))
        #expect(!s.contains("Étiquette"))
        #expect(!s.contains("EnglishName"))
    }

    @Test func materialsAreNotMerged() {
        let std = MediaCatalog.bundled.roll(sku: "S0722540")!
        let dur = MediaCatalog.bundled.roll(sku: "1933084")!
        #expect(std.material == "standard")
        #expect(dur.material == "durable")
        #expect(std.id != dur.id)
        #expect(std.id == "11354")
        #expect(std.skus.contains("30334"))
        #expect(dur.skus.contains("2112289"))
    }
    @Test func searchRanksStandardBeforeDurable() {
        let ids = MediaCatalog.bundled.search("32x57").map(\.id)
        #expect(ids.first == "11354")
        #expect(ids.contains(MediaCatalog.bundled.roll(sku: "1933084")!.id))
    }
    @Test func minHeadDotsFollowsPrintableWidth() {
        #expect(MediaCatalog.bundled.roll(sku: "30256")!.minHeadDots == 672)
        #expect(MediaCatalog.bundled.roll(sku: "30270")!.minHeadDots == 672)
        #expect(MediaCatalog.bundled.roll(sku: "S0904980")!.minHeadDots == 1248)
        #expect(MediaCatalog.bundled.rolls.allSatisfy { ($0.printable.widthDots > 672) == ($0.minHeadDots == 1248) })
    }
}
