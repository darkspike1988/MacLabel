import Testing
@testable import LabelMedia

@Suite struct LabelMediaPlaceholderTests {
    @Test func moduleLoads() {
        _ = LabelMediaModule.self
    }
}
