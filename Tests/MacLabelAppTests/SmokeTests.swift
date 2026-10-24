import Testing
@testable import MacLabelApp

@Suite struct AppSmokeTests {
    @Test func moduleLoads() { _ = MacLabelAppModule.self }
}
