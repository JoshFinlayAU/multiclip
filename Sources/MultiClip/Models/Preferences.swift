import Foundation
import AppKit

/// User-configurable settings, backed by UserDefaults. The shared key lives in
/// the Keychain (see KeychainStore), not here.
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let historyLimit = "historyLimit"
        static let fileSizeLimitMB = "fileSizeLimitMB"
        static let deviceName = "deviceName"
        static let deviceId = "deviceId"
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let iconStyle = "iconStyle"
        static let hotKeyEnabled = "hotKeyEnabled"
    }

    private init() {
        defaults.register(defaults: [
            Key.historyLimit: 5,
            Key.fileSizeLimitMB: 50,
            Key.hotKeyEnabled: true,
            // Default hotkey: Command+Option+V. Carbon keycode for 'V' is 9.
            Key.hotKeyCode: 9,
            Key.hotKeyModifiers: Int(HotKeyModifiers.command.rawValue | HotKeyModifiers.option.rawValue),
            Key.iconStyle: "outline"
        ])
    }

    var historyLimit: Int {
        get { max(1, defaults.integer(forKey: Key.historyLimit)) }
        set { defaults.set(max(1, newValue), forKey: Key.historyLimit) }
    }

    /// Maximum size, in bytes, of an item that will be offered/transferred.
    var fileSizeLimitBytes: Int {
        get { max(1, defaults.integer(forKey: Key.fileSizeLimitMB)) * 1_000_000 }
        set { defaults.set(max(1, newValue / 1_000_000), forKey: Key.fileSizeLimitMB) }
    }

    var fileSizeLimitMB: Int {
        get { max(1, defaults.integer(forKey: Key.fileSizeLimitMB)) }
        set { defaults.set(max(1, newValue), forKey: Key.fileSizeLimitMB) }
    }

    /// Human-friendly name advertised to peers. Defaults to the computer name.
    var deviceName: String {
        get {
            if let env = ProcessInfo.processInfo.environment["MULTICLIP_DEVICE_NAME"], !env.isEmpty { return env }
            if let n = defaults.string(forKey: Key.deviceName), !n.isEmpty { return n }
            return Host.current().localizedName ?? "Mac"
        }
        set { defaults.set(newValue, forKey: Key.deviceName) }
    }

    /// Stable per-install identifier used to dedupe peers and ignore self.
    var deviceId: String {
        // Test override so multiple instances can run on one machine.
        if let env = ProcessInfo.processInfo.environment["MULTICLIP_DEVICE_ID"], !env.isEmpty { return env }
        if let id = defaults.string(forKey: Key.deviceId), !id.isEmpty { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: Key.deviceId)
        return id
    }

    var hotKeyEnabled: Bool {
        get { defaults.bool(forKey: Key.hotKeyEnabled) }
        set { defaults.set(newValue, forKey: Key.hotKeyEnabled) }
    }

    var hotKeyCode: UInt32 {
        get { UInt32(defaults.integer(forKey: Key.hotKeyCode)) }
        set { defaults.set(Int(newValue), forKey: Key.hotKeyCode) }
    }

    var hotKeyModifiers: UInt32 {
        get { UInt32(defaults.integer(forKey: Key.hotKeyModifiers)) }
        set { defaults.set(Int(newValue), forKey: Key.hotKeyModifiers) }
    }

    /// One of "outline", "black", "color".
    var iconStyle: String {
        get { defaults.string(forKey: Key.iconStyle) ?? "outline" }
        set { defaults.set(newValue, forKey: Key.iconStyle) }
    }
}
