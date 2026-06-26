import Foundation
import AppKit

/// Polls the general pasteboard for changes and reports newly-copied items.
/// Changes that MultiClip itself caused (by writing a remote selection) are
/// ignored so we never re-broadcast them.
final class ClipboardMonitor {
    var onNewItem: ((ClipboardItem) -> Void)?

    private var timer: Timer?
    private var lastChangeCount: Int
    /// A changeCount we produced ourselves and should not report.
    private var ignoredChangeCount: Int = -1

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Tell the monitor that the given changeCount was produced by us.
    func ignoreChange(_ changeCount: Int) {
        ignoredChangeCount = changeCount
        lastChangeCount = changeCount
    }

    private func poll() {
        let current = NSPasteboard.general.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        if current == ignoredChangeCount { return }

        if let item = PasteboardHelper.snapshotCurrent() {
            onNewItem?(item)
        }
    }
}
