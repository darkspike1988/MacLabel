import Foundation
import LabelTransport
@testable import MacLabelApp

@MainActor
func makeViewModel(printers: [DiscoveredPrinter], remembered: String?, blockFrom: Int? = nil, maxPages: Int = 1) -> AppModel {
    let factory = AppStubFactory(list: printers, blockFrom: blockFrom)
    let printer = LabelPrinter(factory: factory, preferences: appPrefs(remembered: remembered), formFeedClock: AppNoStampClock())
    return AppModel(printer: printer, preview: PreviewEngine(debounce: .zero, maxPages: maxPages))
}

@MainActor
func waitFor(timeout: Duration = .seconds(10), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
}
