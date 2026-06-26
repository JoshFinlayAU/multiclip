import Foundation

/// The kinds of clipboard content MultiClip understands, in priority order.
enum ClipKind: String, Codable, CaseIterable {
    case files
    case image
    case rtf
    case plain
}

/// Metadata describing a single file inside a "files" clipboard item.
struct FileInfo: Codable, Equatable {
    var name: String
    var size: Int
}

/// Lightweight, network-serializable description of a clipboard item.
/// Contains everything needed to display the item in a menu, but none of the
/// heavy payload bytes (those are fetched lazily on demand).
struct ItemMeta: Codable, Equatable {
    var id: String
    var deviceId: String
    var deviceName: String
    var timestamp: Date
    /// Representations available for this item, highest-fidelity first.
    var kinds: [ClipKind]
    /// Short human-readable preview shown in the menu.
    var preview: String
    /// Total payload size in bytes (sum across files for file items).
    var totalSize: Int
    /// Present when `kinds` contains `.files`.
    var files: [FileInfo]?

    var hasFiles: Bool { kinds.contains(.files) }
}

/// A clipboard item as held in memory. For local items the payloads are
/// populated immediately; for remote items they remain nil until fetched.
final class ClipboardItem {
    let meta: ItemMeta
    /// True when this item originated on this Mac.
    let isLocal: Bool

    var plain: String?
    var rtf: Data?
    var image: Data?           // PNG-encoded
    /// For local file items: the original file URLs on this Mac.
    /// For fetched remote file items: URLs of the received copies in the cache.
    var fileURLs: [URL]?

    init(meta: ItemMeta, isLocal: Bool) {
        self.meta = meta
        self.isLocal = isLocal
    }

    var id: String { meta.id }
}
