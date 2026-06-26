import Foundation
import Network
import CryptoKit

/// Wraps an NWConnection with length-prefixed framing and AES-GCM encryption.
///
/// On-the-wire each message is: [UInt32 length big-endian][sealed bytes], where
/// the sealed bytes decrypt to a WireCodec plaintext frame. A peer presenting
/// the wrong shared key produces sealed bytes we cannot open, so we drop it.
final class SecureChannel {
    let connection: NWConnection
    private let key: SymmetricKey
    private let queue: DispatchQueue

    /// Decrypted (WireHeader, payload) pairs.
    var onMessage: ((WireHeader, Data) -> Void)?
    var onReady: (() -> Void)?
    var onClosed: (() -> Void)?

    private var buffer = Data()
    private var closed = false

    init(connection: NWConnection, key: SymmetricKey, queue: DispatchQueue) {
        self.connection = connection
        self.key = key
        self.queue = queue
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.onReady?()
                self.receiveLoop()
            case .failed, .cancelled:
                self.close()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func send(_ header: WireHeader, payload: Data? = nil) {
        guard !closed else { return }
        do {
            let plaintext = try WireCodec.encode(header, payload: payload)
            let sealed = try Crypto.seal(plaintext, key: key)
            var framed = Data()
            var len = UInt32(sealed.count).bigEndian
            withUnsafeBytes(of: &len) { framed.append(contentsOf: $0) }
            framed.append(sealed)
            connection.send(content: framed, completion: .contentProcessed { [weak self] error in
                if error != nil { self?.close() }
            })
        } catch {
            close()
        }
    }

    func close() {
        queue.async { [weak self] in
            guard let self = self, !self.closed else { return }
            self.closed = true
            self.connection.cancel()
            self.onClosed?()
        }
    }

    // MARK: - Receiving

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                self.buffer.append(data)
                self.drainFrames()
            }
            if isComplete || error != nil {
                self.close()
                return
            }
            self.receiveLoop()
        }
    }

    private func drainFrames() {
        while buffer.count >= 4 {
            let lenSlice = buffer.prefix(4)
            let frameLen = lenSlice.withUnsafeBytes { rawBuffer -> UInt32 in
                var value: UInt32 = 0
                withUnsafeMutableBytes(of: &value) { $0.copyBytes(from: rawBuffer) }
                return UInt32(bigEndian: value)
            }
            let total = 4 + Int(frameLen)
            guard buffer.count >= total else { return }
            let sealed = buffer.subdata(in: 4..<total)
            buffer.removeSubrange(0..<total)

            do {
                let plaintext = try Crypto.open(sealed, key: key)
                let (header, payload) = try WireCodec.decode(plaintext)
                onMessage?(header, payload)
            } catch {
                // Wrong key or corrupt frame: this peer cannot be trusted.
                close()
                return
            }
        }
    }
}
