import Testing
@testable import MacLabelKit

@Suite struct MacLabelKitPlaceholderTests {
    @Test func moduleLoads() {
        _ = MacLabelKitModule.self
    }
}
