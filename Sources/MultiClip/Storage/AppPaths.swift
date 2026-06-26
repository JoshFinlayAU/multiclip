import Foundation

/// Centralizes on-disk locations under Application Support/MultiClip.
enum AppPaths {
    static let folderName = "MultiClip"

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var historyFile: URL {
        supportDirectory.appendingPathComponent("history.json")
    }

    /// Directory holding file payloads received from peers.
    static var receivedDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("Received", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func receivedDirectory(forItem itemId: String) -> URL {
        let dir = receivedDirectory.appendingPathComponent(itemId, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
