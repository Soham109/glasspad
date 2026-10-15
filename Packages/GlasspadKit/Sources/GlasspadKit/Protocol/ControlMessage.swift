import Foundation

/// Haptic the phone should play.
public enum HapticKind: String, Codable, Sendable {
    case click, forceClick, detent, snap, error
}

/// Messages on the sealed TCP control channel. JSON with a `"t"` discriminator:
/// `{"t":"ping","id":1}`, `{"t":"settings","settings":{..}}`, `{"t":"haptic","kind":"click"}`,
/// `{"t":"mode","mode":{..}}`, `{"t":"bye","reason":".."}`.
public enum ControlMessage: Codable, Equatable, Sendable {
    /// Mac -> phone each second; the transport answers it automatically.
    case ping(id: UInt32)
    /// Phone -> Mac answer to `ping` with the same id. Used for RTT stats.
    case pong(id: UInt32)
    /// Mac -> phone, on connect and whenever the trackpad prefs change.
    case settings(TrackpadSettings)
    /// Mac -> phone, play a haptic now (e.g. a Space snapped into place).
    case haptic(HapticKind)
    /// Both ways, the extra modes (SPEC section 8).
    case mode(ModeMessage)
    /// Either side is closing the session on purpose.
    case bye(reason: String)

    private enum Keys: String, CodingKey { case t, id, settings, kind, mode, reason }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let t = try c.decode(String.self, forKey: .t)
        switch t {
        case "ping": self = .ping(id: try c.decode(UInt32.self, forKey: .id))
        case "pong": self = .pong(id: try c.decode(UInt32.self, forKey: .id))
        case "settings": self = .settings(try c.decode(TrackpadSettings.self, forKey: .settings))
        case "haptic": self = .haptic(try c.decode(HapticKind.self, forKey: .kind))
        case "mode": self = .mode(try c.decode(ModeMessage.self, forKey: .mode))
        case "bye": self = .bye(reason: try c.decode(String.self, forKey: .reason))
        default:
            throw DecodingError.dataCorruptedError(forKey: .t, in: c, debugDescription: "unknown message type \(t)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .ping(let id): try c.encode("ping", forKey: .t); try c.encode(id, forKey: .id)
        case .pong(let id): try c.encode("pong", forKey: .t); try c.encode(id, forKey: .id)
        case .settings(let s): try c.encode("settings", forKey: .t); try c.encode(s, forKey: .settings)
        case .haptic(let k): try c.encode("haptic", forKey: .t); try c.encode(k, forKey: .kind)
        case .mode(let m): try c.encode("mode", forKey: .t); try c.encode(m, forKey: .mode)
        case .bye(let r): try c.encode("bye", forKey: .t); try c.encode(r, forKey: .reason)
        }
    }

    /// JSON bytes for the wire.
    public func jsonData() throws -> Data { try JSONEncoder().encode(self) }

    /// Parses JSON bytes from the wire.
    public static func from(jsonData data: Data) throws -> ControlMessage {
        try JSONDecoder().decode(ControlMessage.self, from: data)
    }
}

// MARK: - Plaintext handshake (the only unsealed messages)

/// Phone -> Mac, first frame on a new TCP connection.
struct PhoneHello: Codable, Equatable {
    var t = "hello"
    var v = 1
    var phoneID: String
    var phoneName: String
    var macID: UUID
    var nonce: Data
}

/// Mac -> phone answer when the phone is known (or a pending pairing matches).
struct MacHello: Codable, Equatable {
    var t = "hello"
    var v = 1
    var nonce: Data
    var udpPort: UInt16
}

/// Mac -> phone when it refuses the connection; the Mac closes right after.
struct HandshakeReject: Codable, Equatable {
    var t = "reject"
    var reason: String
}

/// Mac -> phone, sealed, right after the handshake: how to wake this Mac. Handled inside the
/// transport (old clients fail to decode it as a `ControlMessage` and drop it).
struct WakeAnnouncement: Codable, Equatable {
    var t = "wake"
    var target: WakeTarget
}

/// Peek at the `t` field of a plaintext handshake frame.
struct HandshakeTag: Codable { var t: String }

/// First sealed frame each way after Hello. Proves both sides derived the same key
/// before the Mac stores a new pairing or the phone reports `connected`.
let handshakeConfirmToken = Data("glasspad confirm v1".utf8)
