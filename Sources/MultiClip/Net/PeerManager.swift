import Foundation
import Network
import CryptoKit

protocol PeerManagerDelegate: AnyObject {
    /// A peer announced a new clipboard item (metadata only).
    func peerManager(_ manager: PeerManager, didReceiveAnnounce meta: ItemMeta)
    /// The manager needs payload bytes for a locally-owned item to serve a peer.
    func peerManager(_ manager: PeerManager, payloadForItem itemId: String, kind: ClipKind, fileIndex: Int?) -> Data?
    /// Connected-peer set changed.
    func peerManagerDidChangePeers(_ manager: PeerManager)
}

/// Discovers peers over Bonjour and maintains encrypted channels to them.
/// There is no central server: every instance both advertises and browses.
final class PeerManager {
    weak var delegate: PeerManagerDelegate?

    private let serviceType = "_multiclip._tcp"
    private let queue = DispatchQueue(label: "com.athenanetworks.multiclip.net")

    private var key: SymmetricKey?
    private var listener: NWListener?
    private var browser: NWBrowser?

    /// Live channels keyed by remote deviceId (deduped to one per device).
    private var channels: [String: SecureChannel] = [:]
    /// Channels that have connected but not yet sent a usable hello, keyed by endpoint.
    private var connecting: [NWEndpoint: SecureChannel] = [:]
    /// Latest Bonjour browse results, for self-healing reconnects.
    private var discovered: Set<NWBrowser.Result> = []

    private var pendingRequests: [String: (Result<Data, Error>) -> Void] = [:]

    private var reconnectTimer: DispatchSourceTimer?

    private var deviceId: String { Preferences.shared.deviceId }
    private var deviceName: String { Preferences.shared.deviceName }

    enum PeerError: Error { case noPayload, timeout, notConnected }

    // MARK: - Lifecycle

    /// (Re)start networking using the current shared key. Safe to call repeatedly.
    func restart() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.teardownLocked()
            guard let secret = KeychainStore.sharedKey(), !secret.isEmpty else {
                NSLog("MultiClip: no shared key set; networking idle")
                return
            }
            self.key = Crypto.deriveKey(from: secret)
            self.startListenerLocked()
            self.startBrowserLocked()
            self.startReconnectTimerLocked()
        }
    }

    func stop() {
        queue.async { [weak self] in self?.teardownLocked() }
    }

    private func teardownLocked() {
        reconnectTimer?.cancel()
        reconnectTimer = nil
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil
        for c in channels.values { c.close() }
        for c in connecting.values { c.close() }
        channels.removeAll()
        connecting.removeAll()
        discovered.removeAll()
        for (_, cb) in pendingRequests { cb(.failure(PeerError.notConnected)) }
        pendingRequests.removeAll()
    }

    // MARK: - Listener

    private func startListenerLocked() {
        do {
            let params = NWParameters.tcp
            let listener = try NWListener(using: params)
            var txt = NWTXTRecord()
            txt["id"] = deviceId
            listener.service = NWListener.Service(name: deviceName, type: serviceType, txtRecord: txt)
            listener.newConnectionHandler = { [weak self] conn in
                self?.queue.async { self?.adoptIncomingLocked(conn) }
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let err) = state {
                    NSLog("MultiClip: listener failed: \(err)")
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            NSLog("MultiClip: failed to start listener: \(error)")
        }
    }

    private func adoptIncomingLocked(_ conn: NWConnection) {
        guard let key = key else { conn.cancel(); return }
        let channel = SecureChannel(connection: conn, key: key, queue: queue)
        let endpoint = conn.endpoint
        connecting[endpoint] = channel
        configure(channel, endpoint: endpoint, sendHelloOnReady: true)
        channel.start()
    }

    // MARK: - Browser

    private func startBrowserLocked() {
        let params = NWParameters()
        params.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: serviceType, domain: nil), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.queue.async {
                self?.discovered = results
                self?.reconcileConnectionsLocked()
            }
        }
        browser.stateUpdateHandler = { state in
            if case .failed(let err) = state {
                NSLog("MultiClip: browser failed: \(err)")
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    private func startReconnectTimerLocked() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in self?.reconcileConnectionsLocked() }
        timer.resume()
        reconnectTimer = timer
    }

    /// Ensure there is an outgoing connection attempt for every discovered peer
    /// that is not ourselves and not already connected.
    private func reconcileConnectionsLocked() {
        guard let key = key else { return }
        for result in discovered {
            // Identify the peer via its TXT record; skip ourselves.
            var peerId: String?
            if case let .bonjour(txt) = result.metadata {
                peerId = txt["id"]
            }
            if let peerId = peerId, peerId == deviceId { continue }
            if let peerId = peerId, channels[peerId] != nil { continue }

            // Deterministic initiator: only the peer with the smaller id dials
            // out; the other accepts the inbound connection. This guarantees a
            // single channel per pair and avoids a dual-connection race.
            if let peerId = peerId, deviceId >= peerId { continue }

            let endpoint = result.endpoint
            if connecting[endpoint] != nil { continue }
            // Already connected to this endpoint under some deviceId?
            if channels.values.contains(where: { $0.connection.endpoint == endpoint }) { continue }

            let conn = NWConnection(to: endpoint, using: .tcp)
            let channel = SecureChannel(connection: conn, key: key, queue: queue)
            connecting[endpoint] = channel
            configure(channel, endpoint: endpoint, sendHelloOnReady: true)
            channel.start()
        }
    }

    // MARK: - Channel wiring

    private func configure(_ channel: SecureChannel, endpoint: NWEndpoint, sendHelloOnReady: Bool) {
        channel.onReady = { [weak self, weak channel] in
            guard let self = self, let channel = channel else { return }
            if sendHelloOnReady {
                var header = WireHeader(type: .hello, deviceId: self.deviceId)
                header.deviceName = self.deviceName
                channel.send(header)
            }
        }
        channel.onMessage = { [weak self, weak channel] header, payload in
            guard let self = self, let channel = channel else { return }
            self.handleMessageLocked(header, payload: payload, channel: channel, endpoint: endpoint)
        }
        channel.onClosed = { [weak self, weak channel] in
            self?.queue.async {
                guard let self = self, let channel = channel else { return }
                self.connecting.removeValue(forKey: endpoint)
                for (id, c) in self.channels where c === channel {
                    self.channels.removeValue(forKey: id)
                }
                self.notifyPeersChanged()
            }
        }
    }

    private func handleMessageLocked(_ header: WireHeader, payload: Data, channel: SecureChannel, endpoint: NWEndpoint) {
        switch header.type {
        case .hello:
            let peerId = header.deviceId
            if peerId == deviceId {
                // Connected to ourselves; drop quietly.
                channel.close()
                return
            }
            connecting.removeValue(forKey: endpoint)
            if let existing = channels[peerId], existing !== channel {
                existing.close()
            }
            channels[peerId] = channel
            NSLog("MultiClip: connected to peer \(header.deviceName ?? peerId)")
            notifyPeersChanged()

        case .announce:
            if let meta = header.item {
                DispatchQueue.main.async {
                    self.delegate?.peerManager(self, didReceiveAnnounce: meta)
                }
            }

        case .request:
            serveRequestLocked(header, channel: channel)

        case .payload:
            if let reqId = header.requestId, let cb = pendingRequests.removeValue(forKey: reqId) {
                cb(.success(payload))
            }

        case .error:
            if let reqId = header.requestId, let cb = pendingRequests.removeValue(forKey: reqId) {
                cb(.failure(PeerError.noPayload))
            }
        }
    }

    private func serveRequestLocked(_ header: WireHeader, channel: SecureChannel) {
        guard let itemId = header.itemId, let kind = header.kind, let reqId = header.requestId else { return }
        // Ask the delegate (on main) for the bytes, then reply on the net queue.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let data = self.delegate?.peerManager(self, payloadForItem: itemId, kind: kind, fileIndex: header.fileIndex)
            self.queue.async {
                if let data = data {
                    var reply = WireHeader(type: .payload, deviceId: self.deviceId)
                    reply.requestId = reqId
                    reply.itemId = itemId
                    reply.kind = kind
                    reply.fileIndex = header.fileIndex
                    reply.payloadSize = data.count
                    channel.send(reply, payload: data)
                } else {
                    var reply = WireHeader(type: .error, deviceId: self.deviceId)
                    reply.requestId = reqId
                    reply.message = "payload unavailable"
                    channel.send(reply)
                }
            }
        }
    }

    private func notifyPeersChanged() {
        DispatchQueue.main.async { self.delegate?.peerManagerDidChangePeers(self) }
    }

    // MARK: - Public API

    func broadcastAnnounce(_ meta: ItemMeta) {
        queue.async { [weak self] in
            guard let self = self else { return }
            var header = WireHeader(type: .announce, deviceId: self.deviceId)
            header.deviceName = self.deviceName
            header.item = meta
            for channel in self.channels.values {
                channel.send(header)
            }
        }
    }

    /// Request a payload from a specific peer. Completion runs on the main queue.
    func requestPayload(itemId: String, fromDevice peerId: String, kind: ClipKind, fileIndex: Int?,
                        timeout: TimeInterval = 120,
                        completion: @escaping (Result<Data, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let channel = self.channels[peerId] else {
                DispatchQueue.main.async { completion(.failure(PeerError.notConnected)) }
                return
            }
            let reqId = UUID().uuidString
            self.pendingRequests[reqId] = { result in
                DispatchQueue.main.async { completion(result) }
            }
            var header = WireHeader(type: .request, deviceId: self.deviceId)
            header.requestId = reqId
            header.itemId = itemId
            header.kind = kind
            header.fileIndex = fileIndex
            channel.send(header)

            self.queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                if let cb = self?.pendingRequests.removeValue(forKey: reqId) {
                    cb(.failure(PeerError.timeout))
                }
            }
        }
    }

    var peerCount: Int {
        queue.sync { channels.count }
    }
}
