import Foundation

/// Headless end-to-end harness. Run with `MultiClip --integration` on two
/// processes (distinct MULTICLIP_DEVICE_ID, same MULTICLIP_SHARED_KEY): each
/// announces a unique clipboard item and tries to fetch the peer's payload over
/// real Bonjour discovery. Exits 0 if it successfully fetched a peer's payload.
final class IntegrationHarness: PeerManagerDelegate {
    private let store = HistoryStore()
    private let peers = PeerManager()
    private var fetched = false
    private let name = Preferences.shared.deviceName

    func run() -> Never {
        peers.delegate = self
        store.delegate = nil

        // Publish a unique local item.
        let meta = ItemMeta(id: "item-\(name)", deviceId: Preferences.shared.deviceId,
                            deviceName: name, timestamp: Date(), kinds: [.plain],
                            preview: "hello from \(name)", totalSize: 32, files: nil)
        let item = ClipboardItem(meta: meta, isLocal: true)
        item.plain = "secret payload from \(name)"
        store.addLocal(item)

        peers.restart()
        print("[\(name)] started; announcing in 2s…")

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.peers.broadcastAnnounce(meta)
        }
        // Re-announce periodically in case a peer connects late.
        let timer = Timer(timeInterval: 2, repeats: true) { _ in
            self.peers.broadcastAnnounce(meta)
        }
        RunLoop.main.add(timer, forMode: .common)

        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            print(self.fetched ? "[\(self.name)] RESULT: SUCCESS" : "[\(self.name)] RESULT: FAILURE (no payload fetched)")
            exit(self.fetched ? 0 : 1)
        }

        RunLoop.main.run()
        exit(2)
    }

    func peerManager(_ manager: PeerManager, didReceiveAnnounce meta: ItemMeta) {
        print("[\(name)] received announce \(meta.id) from \(meta.deviceName)")
        peers.requestPayload(itemId: meta.id, fromDevice: meta.deviceId, kind: .plain, fileIndex: nil) { result in
            switch result {
            case .success(let data):
                let text = String(data: data, encoding: .utf8) ?? "<binary>"
                print("[\(self.name)] FETCHED payload: \(text)")
                self.fetched = true
            case .failure(let error):
                print("[\(self.name)] fetch failed: \(error)")
            }
        }
    }

    func peerManager(_ manager: PeerManager, payloadForItem itemId: String, kind: ClipKind, fileIndex: Int?) -> Data? {
        store.payload(itemId: itemId, kind: kind, fileIndex: fileIndex)
    }

    func peerManagerDidChangePeers(_ manager: PeerManager) {
        print("[\(name)] peers now: \(manager.peerCount)")
    }
}
