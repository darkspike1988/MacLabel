import Testing
@testable import LabelRender

@Suite struct LabelRenderPlaceholderTests {
    @Test func moduleLoads() {
        _ = LabelRenderModule.self
    }
}
