import Testing
@testable import maclabel

@Suite struct MacLabelCLIPlaceholderTests {
    @Test func commandNameIsMaclabel() {
        #expect(MacLabel.configuration.commandName == "maclabel")
    }
}
