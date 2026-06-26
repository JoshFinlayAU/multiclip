import Foundation
import Network
import CryptoKit

/// In-process smoke test for the crypto + wire framing + SecureChannel transport.
/// Run with `MultiClip --selftest`. Exits with status 0 on success, 1 on failure.
enum SelfTest {
    static func run() -> Never {
        var failures = 0
        func check(_ cond: Bool, _ name: String) {
            print(cond ? "  ✓ \(name)" : "  ✗ \(name)")
            if !cond { failures += 1 }
        }

        print("== Crypto round-trip ==")
        let key = Crypto.deriveKey(from: "shared-secret")
        let wrongKey = Crypto.deriveKey(from: "different")
        do {
            let plain = Data("hello world".utf8)
            let sealed = try Crypto.seal(plain, key: key)
            let opened = try Crypto.open(sealed, key: key)
            check(opened == plain, "seal/open returns original")
            check((try? Crypto.open(sealed, key: wrongKey)) == nil, "wrong key fails to open")
        } catch {
            check(false, "crypto threw: \(error)")
        }

        print("== Wire codec round-trip ==")
        do {
            var header = WireHeader(type: .payload, deviceId: "dev-1")
            header.requestId = "r1"
            header.itemId = "item-1"
            header.kind = .image
            let payload = Data((0..<5000).map { UInt8($0 & 0xFF) })
            let frame = try WireCodec.encode(header, payload: payload)
            let (decHeader, decPayload) = try WireCodec.decode(frame)
            check(decHeader.type == .payload, "type preserved")
            check(decHeader.itemId == "item-1", "itemId preserved")
            check(decPayload == payload, "payload preserved")
        } catch {
            check(false, "wire codec threw: \(error)")
        }

        print("== SecureChannel loopback (incl. 2 MB payload reassembly) ==")
        let loopbackOK = runLoopback(key: key)
        check(loopbackOK, "announce + large payload delivered over loopback")

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }

    private static func runLoopback(key: SymmetricKey) -> Bool {
        let queue = DispatchQueue(label: "selftest")
        let semaphore = DispatchSemaphore(value: 0)

        var receivedAnnounce = false
        var receivedPayloadCorrect = false

        let bigPayload = Data((0..<(2 * 1024 * 1024)).map { UInt8(($0 * 7) & 0xFF) })

        var serverChannel: SecureChannel?

        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp)
        } catch {
            print("  listener creation failed: \(error)")
            return false
        }

        listener.newConnectionHandler = { conn in
            let ch = SecureChannel(connection: conn, key: key, queue: queue)
            serverChannel = ch
            ch.onMessage = { header, payload in
                switch header.type {
                case .announce:
                    receivedAnnounce = (header.item?.preview == "hi there")
                case .payload:
                    receivedPayloadCorrect = (payload == bigPayload)
                    semaphore.signal()
                default:
                    break
                }
            }
            ch.start()
        }
        listener.stateUpdateHandler = { state in
            if case .ready = state, let port = listener.port {
                let conn = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
                let client = SecureChannel(connection: conn, key: key, queue: queue)
                client.onReady = {
                    let meta = ItemMeta(id: "i1", deviceId: "client", deviceName: "Client",
                                        timestamp: Date(), kinds: [.plain], preview: "hi there",
                                        totalSize: 8, files: nil)
                    var announce = WireHeader(type: .announce, deviceId: "client")
                    announce.item = meta
                    client.send(announce)

                    var payloadHeader = WireHeader(type: .payload, deviceId: "client")
                    payloadHeader.itemId = "i1"
                    payloadHeader.kind = .image
                    client.send(payloadHeader, payload: bigPayload)
                }
                client.start()
                // keep the client alive for the duration
                clientHolder = client
            }
        }
        listener.start(queue: queue)

        let result = semaphore.wait(timeout: .now() + 10)
        listener.cancel()
        serverChannel?.close()
        clientHolder?.close()
        clientHolder = nil

        if result == .timedOut { print("  timed out waiting for payload"); return false }
        return receivedAnnounce && receivedPayloadCorrect
    }

    // Holds the client channel so it isn't deallocated mid-test.
    private static var clientHolder: SecureChannel?
}
