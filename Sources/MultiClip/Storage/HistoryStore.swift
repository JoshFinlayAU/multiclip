import Foundation

protocol HistoryStoreDelegate: AnyObject {
    func historyStoreDidChange(_ store: HistoryStore)
}

/// Holds the recent local copies (with payloads, persisted across restarts) and
/// the items announced by peers (metadata, payloads fetched on demand).
final class HistoryStore {
    weak var delegate: HistoryStoreDelegate?

    private(set) var local: [ClipboardItem] = []
    private(set) var remote: [ClipboardItem] = []

    /// Cap on remembered remote items (across all peers).
    private let remoteLimit = 25

    init() {
        load()
    }

    // MARK: - Local

    func addLocal(_ item: ClipboardItem) {
        local.removeAll { $0.id == item.id }
        local.insert(item, at: 0)
        trimLocal()
        save()
        notifyChanged()
    }

    private func trimLocal() {
        let limit = Preferences.shared.historyLimit
        if local.count > limit {
            local.removeSubrange(limit..<local.count)
        }
    }

    /// Re-apply the current history limit (e.g. after the user changes it).
    func applyHistoryLimit() {
        trimLocal()
        save()
        notifyChanged()
    }

    func localItem(id: String) -> ClipboardItem? {
        local.first { $0.id == id }
    }

    // MARK: - Remote

    func addRemote(_ meta: ItemMeta) {
        // Ignore our own announcements echoed back.
        guard meta.deviceId != Preferences.shared.deviceId else { return }
        if let existing = remote.first(where: { $0.id == meta.id }) {
            // Refresh ordering only.
            remote.removeAll { $0.id == existing.id }
            remote.insert(existing, at: 0)
        } else {
            let item = ClipboardItem(meta: meta, isLocal: false)
            remote.insert(item, at: 0)
        }
        if remote.count > remoteLimit {
            remote.removeSubrange(remoteLimit..<remote.count)
        }
        notifyChanged()
    }

    func remoteItem(id: String) -> ClipboardItem? {
        remote.first { $0.id == id }
    }

    var latestRemote: ClipboardItem? { remote.first }

    /// Drop remote items belonging to peers that are no longer reachable. We keep
    /// it simple: callers may clear all when the peer set empties.
    func clearRemote() {
        guard !remote.isEmpty else { return }
        remote.removeAll()
        notifyChanged()
    }

    // MARK: - Payload serving (for peers)

    /// Bytes for a locally-owned representation, used to serve peer requests.
    func payload(itemId: String, kind: ClipKind, fileIndex: Int?) -> Data? {
        guard let item = localItem(id: itemId) else { return nil }
        switch kind {
        case .plain:
            return item.plain.map { Data($0.utf8) }
        case .rtf:
            return item.rtf
        case .image:
            return item.image
        case .files:
            guard let urls = item.fileURLs else { return nil }
            guard let idx = fileIndex, idx >= 0, idx < urls.count else { return nil }
            return try? Data(contentsOf: urls[idx])
        }
    }

    private func notifyChanged() {
        delegate?.historyStoreDidChange(self)
    }

    // MARK: - Persistence

    private struct StoredItem: Codable {
        var meta: ItemMeta
        var plain: String?
        var rtf: Data?
        var image: Data?
        var filePaths: [String]?
    }

    private func save() {
        let stored: [StoredItem] = local.map { item in
            StoredItem(
                meta: item.meta,
                plain: item.plain,
                rtf: item.rtf,
                image: item.image,
                filePaths: item.fileURLs?.map { $0.path }
            )
        }
        do {
            let data = try WireCodec.encoder.encode(stored)
            try data.write(to: AppPaths.historyFile, options: .atomic)
        } catch {
            NSLog("MultiClip: failed to save history: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.historyFile) else { return }
        guard let stored = try? WireCodec.decoder.decode([StoredItem].self, from: data) else { return }
        local = stored.map { s in
            let item = ClipboardItem(meta: s.meta, isLocal: true)
            item.plain = s.plain
            item.rtf = s.rtf
            item.image = s.image
            item.fileURLs = s.filePaths?.map { URL(fileURLWithPath: $0) }
            return item
        }
        trimLocal()
    }
}
