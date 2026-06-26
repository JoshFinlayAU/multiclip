import Foundation

/// Message types exchanged between peers.
enum WireType: String, Codable {
    case hello       // first message after connect: identifies sender + proves key
    case announce    // a new clipboard item is available (metadata only)
    case request     // please send the payload for an item/representation
    case payload     // here is the payload (binary appended after the header)
    case error       // a request could not be fulfilled
}

/// Header portion of every frame. The optional binary payload (for `.payload`
/// messages) is appended to the plaintext after this JSON header.
struct WireHeader: Codable {
    var type: WireType
    var deviceId: String
    var deviceName: String?

    // hello/announce
    var item: ItemMeta?

    // request / payload / error
    var requestId: String?
    var itemId: String?
    var kind: ClipKind?
    var payloadSize: Int?     // length of trailing binary blob
    var fileIndex: Int?       // which file (for multi-file items); nil = all
    var message: String?      // error text
}

/// Encodes/decodes a plaintext channel frame:
///   [UInt32 headerLength big-endian][header JSON bytes][optional binary payload]
enum WireCodec {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func encode(_ header: WireHeader, payload: Data? = nil) throws -> Data {
        let headerData = try encoder.encode(header)
        var out = Data()
        var len = UInt32(headerData.count).bigEndian
        withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
        out.append(headerData)
        if let payload = payload {
            out.append(payload)
        }
        return out
    }

    static func decode(_ frame: Data) throws -> (WireHeader, Data) {
        guard frame.count >= 4 else { throw WireError.malformed }
        let lenBytes = frame.prefix(4)
        let headerLen = lenBytes.withUnsafeBytes { rawBuffer -> UInt32 in
            var value: UInt32 = 0
            withUnsafeMutableBytes(of: &value) { $0.copyBytes(from: rawBuffer) }
            return UInt32(bigEndian: value)
        }
        let headerStart = 4
        let headerEnd = headerStart + Int(headerLen)
        guard frame.count >= headerEnd else { throw WireError.malformed }
        let headerData = frame.subdata(in: headerStart..<headerEnd)
        let header = try decoder.decode(WireHeader.self, from: headerData)
        let payload = frame.subdata(in: headerEnd..<frame.count)
        return (header, payload)
    }

    enum WireError: Error {
        case malformed
    }
}
