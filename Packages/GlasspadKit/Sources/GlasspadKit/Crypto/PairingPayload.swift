import Foundation
import Security

/// What the Mac's QR code carries: `glasspad://pair?v=1&id=<macID>&name=<urlenc name>&k=<base64url pairKey>`.
public struct PairingPayload: Codable, Equatable, Sendable {
    public var macID: UUID
    public var macName: String
    public var pairKey: Data

    public static let keyLength = 32

    public init(macID: UUID, macName: String, pairKey: Data) {
        self.macID = macID
        self.macName = macName
        self.pairKey = pairKey
    }

    public var url: URL {
        var c = URLComponents()
        c.scheme = "glasspad"
        c.host = "pair"
        c.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "id", value: macID.uuidString),
            URLQueryItem(name: "name", value: macName),
            URLQueryItem(name: "k", value: Base64URL.encode(pairKey)),
        ]
        // URLComponents leaves "+" and "&"-free values alone; encode "+" so it never reads as a space.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url!
    }

    public init?(url: URL) {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme?.lowercased() == "glasspad", c.host?.lowercased() == "pair",
              let items = c.queryItems else { return nil }
        func value(_ n: String) -> String? { items.first { $0.name == n }?.value }
        guard value("v") == "1",
              let idString = value("id"), let id = UUID(uuidString: idString),
              let name = value("name"),
              let k = value("k"), let key = Base64URL.decode(k), key.count == Self.keyLength
        else { return nil }
        self.init(macID: id, macName: name, pairKey: key)
    }

    /// 32 fresh random bytes for a new phone's pair key.
    public static func generateKey() -> Data { randomBytes(keyLength) }
}

/// Cryptographically random bytes.
public func randomBytes(_ count: Int) -> Data {
    var d = Data(count: count)
    let ok = d.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
    precondition(ok == errSecSuccess, "SecRandomCopyBytes failed")
    return d
}

enum Base64URL {
    static func encode(_ d: Data) -> String {
        d.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b.append("=") }
        return Data(base64Encoded: b)
    }
}
