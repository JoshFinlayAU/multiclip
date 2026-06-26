import Foundation
import AppKit

/// Owns the menu-bar status item and builds its menu from the history store.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let store: HistoryStore

    var onSelectLocal: ((ClipboardItem) -> Void)?
    var onSelectRemote: ((ClipboardItem) -> Void)?
    var onPasteLatestRemote: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onSetupKey: (() -> Void)?
    var onQuit: (() -> Void)?
    var peerCountProvider: (() -> Int)?

    init(store: HistoryStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = IconProvider.menuBarImage(style: Preferences.shared.iconStyle)
            button.toolTip = "MultiClip"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func refreshIcon() {
        statusItem.button?.image = IconProvider.menuBarImage(style: Preferences.shared.iconStyle)
    }

    // MARK: - Menu construction

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let hasKey = KeychainStore.hasSharedKey
        let peers = peerCountProvider?() ?? 0

        let status = NSMenuItem(title: statusLine(hasKey: hasKey, peers: peers), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if !hasKey {
            menu.addItem(.separator())
            let setup = NSMenuItem(title: "Set Shared Key…", action: #selector(setupKey), keyEquivalent: "")
            setup.target = self
            menu.addItem(setup)
        }

        // From other devices
        if !store.remote.isEmpty {
            menu.addItem(.separator())
            menu.addItem(sectionHeader("From Other Devices"))
            for item in store.remote {
                menu.addItem(remoteMenuItem(item))
            }
        }

        // Recent local copies
        menu.addItem(.separator())
        menu.addItem(sectionHeader("Recent Copies (This Mac)"))
        if store.local.isEmpty {
            let empty = NSMenuItem(title: "  (nothing copied yet)", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for item in store.local {
                menu.addItem(localMenuItem(item))
            }
        }

        // Actions
        menu.addItem(.separator())
        if store.latestRemote != nil {
            let paste = NSMenuItem(title: "Paste Latest Remote Item", action: #selector(pasteLatestRemote), keyEquivalent: "")
            paste.target = self
            menu.addItem(paste)
        }
        let prefs = NSMenuItem(title: "Preferences…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        let about = NSMenuItem(title: "About MultiClip", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit MultiClip", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func statusLine(hasKey: Bool, peers: Int) -> String {
        if !hasKey { return "MultiClip — no shared key" }
        switch peers {
        case 0: return "MultiClip — searching for peers…"
        case 1: return "MultiClip — 1 peer connected"
        default: return "MultiClip — \(peers) peers connected"
        }
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func remoteMenuItem(_ item: ClipboardItem) -> NSMenuItem {
        let title = "  \(icon(for: item)) \(item.meta.deviceName): \(item.meta.preview)"
        let mi = NSMenuItem(title: title, action: #selector(selectRemote(_:)), keyEquivalent: "")
        mi.target = self
        mi.representedObject = item.id
        if item.meta.hasFiles {
            mi.toolTip = "Files: " + (item.meta.files?.map { "\($0.name) (\(PasteboardHelper.formatBytes($0.size)))" }.joined(separator: ", ") ?? "")
        }
        return mi
    }

    private func localMenuItem(_ item: ClipboardItem) -> NSMenuItem {
        let title = "  \(icon(for: item)) \(item.meta.preview)"
        let mi = NSMenuItem(title: title, action: #selector(selectLocal(_:)), keyEquivalent: "")
        mi.target = self
        mi.representedObject = item.id
        return mi
    }

    private func icon(for item: ClipboardItem) -> String {
        if item.meta.hasFiles { return "📎" }
        if item.meta.kinds.contains(.image) { return "🖼" }
        return "📝"
    }

    // MARK: - Actions

    @objc private func selectRemote(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let item = store.remoteItem(id: id) else { return }
        onSelectRemote?(item)
    }

    @objc private func selectLocal(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let item = store.localItem(id: id) else { return }
        onSelectLocal?(item)
    }

    @objc private func pasteLatestRemote() { onPasteLatestRemote?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func setupKey() { onSetupKey?() }
    @objc private func quit() { onQuit?() }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "MultiClip"
        alert.informativeText = "Peer-to-peer clipboard sharing for Macs on your local network.\n\nCopies are announced to trusted devices (same shared key) and offered here for you to paste. Nothing is written to a remote clipboard automatically."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
