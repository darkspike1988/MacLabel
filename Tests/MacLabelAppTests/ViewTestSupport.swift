import AppKit
import Foundation
import LabelTransport
import SwiftUI
import Testing
@testable import MacLabelApp

@MainActor
func makeViewModel(printers: [DiscoveredPrinter], remembered: String?, blockFrom: Int? = nil, maxPages: Int = 1,
                    defaults: UserDefaults = tempDefaults()) -> AppModel {
    let factory = AppStubFactory(list: printers, blockFrom: blockFrom)
    let printer = LabelPrinter(factory: factory, preferences: appPrefs(remembered: remembered), formFeedClock: AppNoStampClock())
    return AppModel(printer: printer, preview: PreviewEngine(debounce: .zero, maxPages: maxPages), defaults: defaults)
}

@MainActor
func waitFor(timeout: Duration = .seconds(10), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
}

/// A throwaway `UserDefaults` suite; every suite created here is removed again when the test process exits.
func tempDefaults() -> UserDefaults {
    TempDefaultsRegistry.make()
}

private enum TempDefaultsRegistry {
    nonisolated(unsafe) private static var names: [String] = []
    private static let lock = NSLock()

    static func make() -> UserDefaults {
        let name = "maclabel-test-\(UUID().uuidString)"
        lock.withLock {
            if names.isEmpty {
                atexit { TempDefaultsRegistry.cleanup() }
            }
            names.append(name)
        }
        return UserDefaults(suiteName: name)!
    }

    static func cleanup() {
        let all = lock.withLock { names }
        for name in all { UserDefaults().removePersistentDomain(forName: name) }
    }
}

// MARK: - Snapshot helpers

/// An offscreen window (never ordered in) hosting `root`.
@MainActor
func makeWindow(_ root: some View, size: CGSize, appearance: NSAppearance.Name) -> NSWindow {
    _ = NSApplication.shared
    let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: size),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: appearance)
    window.contentViewController = NSHostingController(rootView: root)
    window.setContentSize(size)
    window.layoutIfNeeded()
    return window
}

@MainActor
func snapshot(of view: NSView) throws -> NSBitmapImageRep {
    view.layoutSubtreeIfNeeded()
    let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
}

/// Whether the right part of the window (the preview) holds a (near-)black pixel, i.e. printed ink on the paper.
func hasBlackPixel(_ rep: NSBitmapImageRep, inRight fraction: Double) -> Bool {
    let startX = Int(Double(rep.pixelsWide) * (1 - fraction))
    for y in stride(from: 0, to: rep.pixelsHigh * 4 / 5, by: 2) {
        for x in stride(from: startX, to: rep.pixelsWide, by: 2) {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            if c.redComponent < 0.1, c.greenComponent < 0.1, c.blueComponent < 0.1 { return true }
        }
    }
    return false
}

func distinctColors(_ rep: NSBitmapImageRep) -> Int {
    var seen = Set<UInt32>()
    let stepX = max(1, rep.pixelsWide / 60), stepY = max(1, rep.pixelsHigh / 60)
    for y in stride(from: 0, to: rep.pixelsHigh, by: stepY) {
        for x in stride(from: 0, to: rep.pixelsWide, by: stepX) {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            let key = UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8 | UInt32(c.blueComponent * 255)
            seen.insert(key)
            if seen.count > 8 { return seen.count }
        }
    }
    return seen.count
}

/// Writes a PNG only when `MACLABEL_SNAPSHOTS=1` (directory: `MACLABEL_SNAPSHOTS_DIR` or the temp dir).
func saveIfRequested(_ rep: NSBitmapImageRep, name: String) throws {
    let env = ProcessInfo.processInfo.environment
    guard env["MACLABEL_SNAPSHOTS"] == "1" else { return }
    let dir = URL(fileURLWithPath: env["MACLABEL_SNAPSHOTS_DIR"] ?? NSTemporaryDirectory())
        .appending(path: env["MACLABEL_SNAPSHOTS_DIR"] == nil ? "maclabel-app-shots" : "")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let data = try #require(rep.representation(using: .png, properties: [:]))
    try data.write(to: dir.appending(path: "\(name).png"))
}


// MARK: - Deterministic sleepers

/// Replaces `Task.sleep`: records every requested duration and suspends until `advance()`.
/// A cancelled sleeper throws `CancellationError`, like the real one.
actor ManualSleeper {
    private(set) var requests: [Duration] = []
    private var waiters: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var nextID = 0

    func sleep(_ duration: Duration) async throws {
        let id = nextID
        nextID += 1
        requests.append(duration)
        try await withTaskCancellationHandler {
            try await suspend(id)
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func suspend(_ id: Int) async throws {
        if Task.isCancelled { throw CancellationError() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            waiters[id] = continuation
        }
    }

    /// Lets every suspended sleep return.
    func advance() {
        let all = waiters
        waiters = [:]
        for continuation in all.values { continuation.resume() }
    }

    private func cancel(_ id: Int) {
        waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    var sleepCount: Int { requests.count }
}

/// Polls (no fixed sleep) until `condition` holds.
func waitForAsync(timeout: Duration = .seconds(10), _ condition: @Sendable () async -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(2))
    }
}
