import Foundation
import CryptoKit

/// Symmetric encryption for the peer channel. The shared key string is stretched
/// into a 256-bit key with HKDF; every frame is sealed with AES-GCM (which also
/// authenticates it, so a peer with the wrong key simply fails to decrypt).
enum Crypto {
    static func deriveKey(from secret: String) -> SymmetricKey {
        let ikm = SymmetricKey(data: Data(secret.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm,
            salt: Data("MultiClip.v1.salt".utf8),
            info: Data("MultiClip.channel".utf8),
            outputByteCount: 32
        )
    }

    /// Returns nonce || ciphertext || tag.
    static func seal(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else {
            throw CryptoError.sealFailed
        }
        return combined
    }

    static func open(_ data: Data, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }

    enum CryptoError: Error {
        case sealFailed
    }
}
