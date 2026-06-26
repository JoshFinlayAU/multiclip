import Foundation
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, HistoryStoreDelegate, PeerManagerDelegate {
    private let store = HistoryStore()
    private let peers = PeerManager()
    private let monitor = ClipboardMonitor()
    private let hotKey = HotKeyManager()
    private var statusController: StatusItemController!
    private let settingsController = SettingsWindowController()

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar agent: no Dock icon, keeps running when windows close.
        NSApp.setActivationPolicy(.accessory)

        store.delegate = self
        peers.delegate = self

        statusController = StatusItemController(store: store)
        wireStatusController()

        settingsController.onSettingsSaved = { [weak self] in self?.applySettings() }

        monitor.onNewItem = { [weak self] item in self?.handleNewLocalCopy(item) }
        monitor.start()

        Notifier.requestAuthorization()

        applyHotKey()
        peers.restart()

        // First-run: guide the user to set a shared key.
        if !KeychainStore.hasSharedKey {
            DispatchQueue.main.async { [weak self] in self?.settingsController.show() }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func wireStatusController() {
        statusController.peerCountProvider = { [weak self] in self?.peers.peerCount ?? 0 }
        statusController.onSelectLocal = { [weak self] item in self?.applyLocalItem(item) }
        statusController.onSelectRemote = { [weak self] item in self?.fetchAndApply(item, paste: false) }
        statusController.onPasteLatestRemote = { [weak self] in self?.pasteLatestRemote() }
        statusController.onOpenSettings = { [weak self] in self?.settingsController.show() }
        statusController.onSetupKey = { [weak self] in self?.settingsController.show() }
        statusController.onQuit = { NSApp.terminate(nil) }
    }

    // MARK: - Settings application

    private func applySettings() {
        statusController.refreshIcon()
        store.applyHistoryLimit()
        applyHotKey()
        // Key or device name may have changed: rebuild networking.
        peers.restart()
    }

    private func applyHotKey() {
        let p = Preferences.shared
        if p.hotKeyEnabled {
            hotKey.onPressed = { [weak self] in self?.pasteLatestRemote() }
            hotKey.register(keyCode: p.hotKeyCode, modifiers: p.hotKeyModifiers)
        } else {
            hotKey.unregister()
        }
    }

    // MARK: - Local copies

    private func handleNewLocalCopy(_ item: ClipboardItem) {
        store.addLocal(item)
        // Announce metadata only; bytes are sent lazily on request.
        peers.broadcastAnnounce(item.meta)
    }

    private func applyLocalItem(_ item: ClipboardItem) {
        let changeCount = PasteboardHelper.write(item)
        monitor.ignoreChange(changeCount)
    }

    // MARK: - Remote selection / fetch

    private func pasteLatestRemote() {
        guard let latest = store.latestRemote else {
            NSSound.beep()
            return
        }
        fetchAndApply(latest, paste: true)
    }

    /// Fetch the payload(s) for a remote item, place them on the pasteboard, add
    /// to local history, and optionally synthesize a paste into the front app.
    private func fetchAndApply(_ remote: ClipboardItem, paste: Bool) {
        let meta = remote.meta
        let applied = ClipboardItem(meta: meta, isLocal: true)
        let group = DispatchGroup()
        var hadError = false

        // Non-file representations (text/image) — all are within the size limit.
        for kind in meta.kinds where kind != .files {
            group.enter()
            peers.requestPayload(itemId: meta.id, fromDevice: meta.deviceId, kind: kind, fileIndex: nil) { result in
                switch result {
                case .success(let data):
                    switch kind {
                    case .plain: applied.plain = String(data: data, encoding: .utf8)
                    case .rtf:   applied.rtf = data
                    case .image: applied.image = data
                    case .files: break
                    }
                case .failure:
                    hadError = true
                }
                group.leave()
            }
        }

        // Files — transferred per index into the received cache.
        if meta.hasFiles, let files = meta.files {
            let dir = AppPaths.receivedDirectory(forItem: meta.id)
            var urls: [URL?] = Array(repeating: nil, count: files.count)
            for (idx, file) in files.enumerated() {
                group.enter()
                peers.requestPayload(itemId: meta.id, fromDevice: meta.deviceId, kind: .files, fileIndex: idx) { result in
                    switch result {
                    case .success(let data):
                        let url = dir.appendingPathComponent(file.name)
                        do {
                            try data.write(to: url, options: .atomic)
                            urls[idx] = url
                        } catch {
                            hadError = true
                        }
                    case .failure:
                        hadError = true
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                applied.fileURLs = urls.compactMap { $0 }
                self.finishApply(applied, isFileTransfer: true, hadError: hadError, paste: paste)
            }
            return
        }

        group.notify(queue: .main) {
            self.finishApply(applied, isFileTransfer: false, hadError: hadError, paste: paste)
        }
    }

    private func finishApply(_ item: ClipboardItem, isFileTransfer: Bool, hadError: Bool, paste: Bool) {
        let hasPayload = item.plain != nil || item.rtf != nil || item.image != nil || !(item.fileURLs ?? []).isEmpty
        guard hasPayload else {
            if isFileTransfer {
                Notifier.fileTransferComplete(title: "Transfer failed",
                                              body: "Could not fetch files from \(item.meta.deviceName).")
            } else {
                NSSound.beep()
            }
            return
        }

        let changeCount = PasteboardHelper.write(item)
        monitor.ignoreChange(changeCount)
        store.addLocal(item)

        if isFileTransfer {
            let count = item.fileURLs?.count ?? 0
            let noun = count == 1 ? "file" : "files"
            Notifier.fileTransferComplete(
                title: "Files received",
                body: "\(count) \(noun) from \(item.meta.deviceName) \(count == 1 ? "is" : "are") on your clipboard.\(hadError ? " (some failed)" : "")"
            )
        }

        if paste {
            if Paster.isTrusted {
                Paster.pasteIntoFrontmostApp()
            } else {
                Paster.requestTrust()
            }
        }
    }

    // MARK: - HistoryStoreDelegate

    func historyStoreDidChange(_ store: HistoryStore) {
        // Menu is rebuilt lazily via menuNeedsUpdate; nothing required here.
    }

    // MARK: - PeerManagerDelegate

    func peerManager(_ manager: PeerManager, didReceiveAnnounce meta: ItemMeta) {
        store.addRemote(meta)
    }

    func peerManager(_ manager: PeerManager, payloadForItem itemId: String, kind: ClipKind, fileIndex: Int?) -> Data? {
        store.payload(itemId: itemId, kind: kind, fileIndex: fileIndex)
    }

    func peerManagerDidChangePeers(_ manager: PeerManager) {
        // Peer count is read on demand when the menu opens.
    }
}
