import AppKit
import SwiftUI

/// Reports whether the hosting window is visible on screen (not closed, minimised or fully covered).
/// `onChange` is called only on transitions, so it can drive `PrinterMonitor.visibilityChanged`,
/// which counts visible windows. Leaving the window counts as becoming invisible.
struct VisibilityReporter: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> ReporterView {
        let view = ReporterView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ReporterView, context: Context) {
        view.onChange = onChange
    }

    static func dismantleNSView(_ view: ReporterView, coordinator: ()) {
        view.detach()
    }

    final class ReporterView: NSView {
        var onChange: (@MainActor (Bool) -> Void)?
        private var isReportedVisible = false
        private weak var observedWindow: NSWindow?

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            guard newWindow !== observedWindow else { return }
            stopObserving()
            if newWindow == nil { report(false) }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window !== observedWindow else { return }
            observedWindow = window
            NotificationCenter.default.addObserver(
                self, selector: #selector(occlusionChanged),
                name: NSWindow.didChangeOcclusionStateNotification, object: window
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowWillClose),
                name: NSWindow.willCloseNotification, object: window
            )
            occlusionChanged()
        }

        /// Called when SwiftUI removes the view.
        func detach() {
            stopObserving()
            report(false)
        }

        @objc private func occlusionChanged() {
            guard let window = observedWindow else { return }
            report(window.isVisible && window.occlusionState.contains(.visible))
        }

        @objc private func windowWillClose() {
            report(false)
        }

        private func stopObserving() {
            NotificationCenter.default.removeObserver(self)
            observedWindow = nil
        }

        private func report(_ visible: Bool) {
            guard visible != isReportedVisible else { return }
            isReportedVisible = visible
            onChange?(visible)
        }
    }
}
