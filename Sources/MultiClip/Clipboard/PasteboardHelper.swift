import Foundation
import AppKit

/// Reads from and writes to the system pasteboard, mapping NSPasteboard
/// representations to MultiClip's ClipKind model.
enum PasteboardHelper {

    /// Snapshot the current general pasteboard into a ClipboardItem, or nil if
    /// there is nothing we can represent / it exceeds the size limit.
    static func snapshotCurrent() -> ClipboardItem? {
        let pb = NSPasteboard.general
        let limit = Preferences.shared.fileSizeLimitBytes

        var kinds: [ClipKind] = []
        var preview = ""
        var totalSize = 0
        var files: [FileInfo]?

        var plain: String?
        var rtf: Data?
        var image: Data?
        var fileURLs: [URL]?

        // Files take priority. fileURL items that are real files on disk.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            var infos: [FileInfo] = []
            var sum = 0
            for url in urls {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                infos.append(FileInfo(name: url.lastPathComponent, size: size))
                sum += size
            }
            if sum <= limit {
                kinds.append(.files)
                files = infos
                fileURLs = urls
                totalSize += sum
                preview = infos.count == 1 ? infos[0].name : "\(infos.count) files"
            }
        }

        // Image (PNG-normalized).
        if let imgData = readImagePNG(pb), imgData.count <= limit {
            kinds.append(.image)
            image = imgData
            totalSize += imgData.count
            if preview.isEmpty { preview = "Image (\(formatBytes(imgData.count)))" }
        }

        // Rich text.
        if let rtfData = pb.data(forType: .rtf), rtfData.count <= limit {
            kinds.append(.rtf)
            rtf = rtfData
            totalSize += rtfData.count
        }

        // Plain text.
        if let s = pb.string(forType: .string), !s.isEmpty {
            kinds.append(.plain)
            plain = s
            totalSize += s.utf8.count
            if preview.isEmpty { preview = singleLine(s) }
        }

        guard !kinds.isEmpty else { return nil }
        if preview.isEmpty { preview = "Clipboard item" }

        let meta = ItemMeta(
            id: UUID().uuidString,
            deviceId: Preferences.shared.deviceId,
            deviceName: Preferences.shared.deviceName,
            timestamp: Date(),
            kinds: kinds,
            preview: preview,
            totalSize: totalSize,
            files: files
        )
        let item = ClipboardItem(meta: meta, isLocal: true)
        item.plain = plain
        item.rtf = rtf
        item.image = image
        item.fileURLs = fileURLs
        return item
    }

    /// Place an item onto the general pasteboard. Returns the new changeCount so
    /// the monitor can ignore this self-induced change. For remote file items the
    /// `fileURLs` should already point at received local copies.
    @discardableResult
    static func write(_ item: ClipboardItem) -> Int {
        let pb = NSPasteboard.general
        pb.clearContents()

        if let urls = item.fileURLs, !urls.isEmpty {
            pb.writeObjects(urls as [NSURL])
        }
        if let img = item.image, let nsImage = NSImage(data: img) {
            pb.writeObjects([nsImage])
        }
        if let rtf = item.rtf {
            pb.setData(rtf, forType: .rtf)
        }
        if let plain = item.plain {
            pb.setString(plain, forType: .string)
        }
        return pb.changeCount
    }

    // MARK: - Helpers

    private static func readImagePNG(_ pb: NSPasteboard) -> Data? {
        if let png = pb.data(forType: .png) {
            return png
        }
        if let tiff = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        return nil
    }

    static func singleLine(_ s: String, max: Int = 60) -> String {
        let collapsed = s.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= max { return collapsed }
        return String(collapsed.prefix(max)) + "…"
    }

    static func formatBytes(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }
}
