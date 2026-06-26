import Foundation
import AppKit
import SwiftUI

/// Lazily creates and shows the SwiftUI settings window. Because MultiClip is an
/// accessory (menu-bar) app, we explicitly activate it so the window comes front.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    var onSettingsSaved: (() -> Void)?

    func show() {
        if let window = window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let model = SettingsModel()
        model.onSaved = { [weak self] in self?.onSettingsSaved?() }

        let root = SettingsView(model: model, onClose: { [weak self] in
            self?.window?.close()
        })
        let hosting = NSHostingController(rootView: root)

        let win = NSWindow(contentViewController: hosting)
        win.title = "MultiClip Settings"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        self.window = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Drop the window so the next open rebuilds with fresh values.
        window = nil
    }
}
