import Testing
@testable import LabelTransport

@Suite struct LabelTransportPlaceholderTests {
    @Test func moduleLoads() {
        _ = LabelTransportModule.self
    }
}
