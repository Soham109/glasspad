import Foundation
import CryptoKit

public enum SessionCryptoError: Error, Equatable, Sendable {
    /// Shorter than counter + tag.
    case tooShort
    /// Counter already used or too old for the replay window.
    case replay
    /// Wrong key or tampered bytes.
    case authenticationFailed
    /// Send counter ran out (never happens in practice).
    case counterExhausted
}

/// Per-connection AEAD state (SPEC section 3).
///
/// `sessionKey = HKDF-SHA256(pairKey, salt: phoneNonce || macNonce, info: "glasspad v1 session")`.
/// Sealed format: `counter(8, BE) || ciphertext || tag(16)`. Nonce = 4-byte direction tag + counter.
/// TCP receive counters must strictly increase; UDP accepts a 64-wide sliding window.
public struct SessionCrypto: Sendable {
    public enum Role: Sendable { case phone, mac }

    public static let replayWindow: UInt64 = 64
    static let info = Data("glasspad v1 session".utf8)

    private let key: SymmetricKey
    private let sendTCPTag: [UInt8]
    private let recvTCPTag: [UInt8]
    private let sendUDPTag: [UInt8]
    private let recvUDPTag: [UInt8]

    private var tcpSendCounter: UInt64 = 0
    private var tcpLastReceived: UInt64?
    private var udpSendCounter: UInt64 = 0
    private var udpHighest: UInt64?
    /// Bit i set = counter (udpHighest - i) has been seen.
    private var udpSeen: UInt64 = 0

    public init(pairKey: Data, phoneNonce: Data, macNonce: Data, role: Role) {
        var salt = phoneNonce
        salt.append(macNonce)
        key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: pairKey), salt: salt,
                                     info: Self.info, outputByteCount: 32)
        let p2m: [UInt8] = Array("P2M\0".utf8), m2p: [UInt8] = Array("M2P\0".utf8)
        let p2mu: [UInt8] = Array("P2MU".utf8), m2pu: [UInt8] = Array("M2PU".utf8)
        switch role {
        case .phone:
            sendTCPTag = p2m; recvTCPTag = m2p; sendUDPTag = p2mu; recvUDPTag = m2pu
        case .mac:
            sendTCPTag = m2p; recvTCPTag = p2m; sendUDPTag = m2pu; recvUDPTag = p2mu
        }
    }

    public mutating func sealTCP(_ plaintext: Data) throws -> Data {
        try Self.seal(plaintext, key: key, tag: sendTCPTag, counter: &tcpSendCounter)
    }

    public mutating func openTCP(_ sealed: Data) throws -> Data {
        let (counter, body) = try Self.split(sealed)
        if let last = tcpLastReceived, counter <= last { throw SessionCryptoError.replay }
        let plain = try Self.open(body, counter: counter, key: key, tag: recvTCPTag)
        tcpLastReceived = counter
        return plain
    }

    public mutating func sealUDP(_ plaintext: Data) throws -> Data {
        try Self.seal(plaintext, key: key, tag: sendUDPTag, counter: &udpSendCounter)
    }

    public mutating func openUDP(_ sealed: Data) throws -> Data {
        let (counter, body) = try Self.split(sealed)
        if let high = udpHighest, counter <= high {
            let behind = high - counter
            if behind >= Self.replayWindow { throw SessionCryptoError.replay }
            if udpSeen & (1 << behind) != 0 { throw SessionCryptoError.replay }
        }
        let plain = try Self.open(body, counter: counter, key: key, tag: recvUDPTag)
        if let high = udpHighest, counter <= high {
            udpSeen |= 1 << (high - counter)
        } else {
            let shift = udpHighest.map { counter - $0 } ?? Self.replayWindow
            udpSeen = shift >= Self.replayWindow ? 1 : (udpSeen << shift) | 1
            udpHighest = counter
        }
        return plain
    }

    // MARK: internals

    private static func nonce(tag: [UInt8], counter: UInt64) throws -> ChaChaPoly.Nonce {
        var bytes = tag
        withUnsafeBytes(of: counter.bigEndian) { bytes.append(contentsOf: $0) }
        return try ChaChaPoly.Nonce(data: bytes)
    }

    private static func seal(_ plaintext: Data, key: SymmetricKey, tag: [UInt8], counter: inout UInt64) throws -> Data {
        guard counter < UInt64.max else { throw SessionCryptoError.counterExhausted }
        let c = counter
        counter += 1
        let box = try ChaChaPoly.seal(plaintext, using: key, nonce: nonce(tag: tag, counter: c))
        var out = Data(capacity: 8 + plaintext.count + 16)
        withUnsafeBytes(of: c.bigEndian) { out.append(contentsOf: $0) }
        out.append(box.ciphertext)
        out.append(box.tag)
        return out
    }

    private static func split(_ sealed: Data) throws -> (UInt64, Data) {
        guard sealed.count >= 8 + 16 else { throw SessionCryptoError.tooShort }
        var counter: UInt64 = 0
        for b in sealed.prefix(8) { counter = (counter << 8) | UInt64(b) }
        return (counter, Data(sealed.dropFirst(8)))
    }

    private static func open(_ body: Data, counter: UInt64, key: SymmetricKey, tag: [UInt8]) throws -> Data {
        do {
            let box = try ChaChaPoly.SealedBox(nonce: nonce(tag: tag, counter: counter),
                                               ciphertext: body.dropLast(16), tag: body.suffix(16))
            return try ChaChaPoly.open(box, using: key)
        } catch {
            throw SessionCryptoError.authenticationFailed
        }
    }
}
