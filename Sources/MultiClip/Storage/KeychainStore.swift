import Foundation
import Security

/// Stores the MultiClip shared key in the login Keychain as a generic password.
/// An app's own generic-password items are accessible under ad-hoc signing, so
/// this works without special entitlements.
enum KeychainStore {
    private static let service = "com.athenanetworks.multiclip.sharedkey"
    private static let account = "shared-key"

    static func setSharedKey(_ key: String) {
        let data = Data(key.utf8)
        // Remove any existing item first, then add.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        guard !key.isEmpty else { return }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func sharedKey() -> String? {
        // Test override so instances can share a key without touching the Keychain.
        if let env = ProcessInfo.processInfo.environment["MULTICLIP_SHARED_KEY"], !env.isEmpty { return env }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static var hasSharedKey: Bool {
        guard let k = sharedKey() else { return false }
        return !k.isEmpty
    }
}
