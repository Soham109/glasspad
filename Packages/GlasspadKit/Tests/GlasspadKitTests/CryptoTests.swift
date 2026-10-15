import Foundation
import Testing
@testable import GlasspadKit

@Suite("Session crypto")
struct SessionCryptoTests {
    let key = PairingPayload.generateKey()
    let pn = randomBytes(16)
    let mn = randomBytes(16)

    func pair() -> (phone: SessionCrypto, mac: SessionCrypto) {
        (SessionCrypto(pairKey: key, phoneNonce: pn, macNonce: mn, role: .phone),
         SessionCrypto(pairKey: key, phoneNonce: pn, macNonce: mn, role: .mac))
    }

    @Test func tcpRoundTripBothWays() throws {
        var (p, m) = pair()
        for i in 0..<50 {
            let msg = Data("hello \(i)".utf8)
            #expect(try m.openTCP(p.sealTCP(msg)) == msg)
            #expect(try p.openTCP(m.sealTCP(msg)) == msg)
        }
        #expect(try m.openTCP(p.sealTCP(Data())) == Data())
    }

    @Test func udpRoundTripBothWays() throws {
        var (p, m) = pair()
        let msg = Data(repeating: 0xAB, count: 98)
        #expect(try m.openUDP(p.sealUDP(msg)) == msg)
        #expect(try p.openUDP(m.sealUDP(msg)) == msg)
    }

    @Test func sealedFormat() throws {
        var (p, _) = pair()
        _ = try p.sealTCP(Data([1]))
        let s = try p.sealTCP(Data([1, 2, 3]))
        #expect(s.count == 8 + 3 + 16)
        #expect(Array(s.prefix(8)) == [0, 0, 0, 0, 0, 0, 0, 1])   // big-endian counter
    }

    @Test func tamperingIsRejected() throws {
        var (p, _) = pair()
        let sealed = try p.sealTCP(Data("secret".utf8))
        for i in 0..<sealed.count {
            var t = sealed
            t[t.startIndex + i] ^= 0x01
            var (_, fresh) = pair()
            #expect(throws: (any Error).self) { try fresh.openTCP(t) }
        }
        var (_, m) = pair()
        #expect(throws: SessionCryptoError.tooShort) { try m.openTCP(Data(count: 23)) }
    }

    @Test func wrongKeyOrNonceIsRejected() throws {
        var (p, _) = pair()
        let sealed = try p.sealTCP(Data("x".utf8))
        var other = SessionCrypto(pairKey: PairingPayload.generateKey(), phoneNonce: pn, macNonce: mn, role: .mac)
        #expect(throws: SessionCryptoError.authenticationFailed) { try other.openTCP(sealed) }
        var otherNonce = SessionCrypto(pairKey: key, phoneNonce: randomBytes(16), macNonce: mn, role: .mac)
        #expect(throws: SessionCryptoError.authenticationFailed) { try otherNonce.openTCP(sealed) }
    }

    @Test func reflectionAndChannelMixupAreRejected() throws {
        var (p, m) = pair()
        let tcp = try p.sealTCP(Data("x".utf8))
        var p2 = SessionCrypto(pairKey: key, phoneNonce: pn, macNonce: mn, role: .phone)
        #expect(throws: SessionCryptoError.authenticationFailed) { try p2.openTCP(tcp) }   // own direction
        #expect(throws: SessionCryptoError.authenticationFailed) { try m.openUDP(tcp) }    // TCP packet on UDP
    }

    @Test func tcpReplayAndReorderRejected() throws {
        var (p, m) = pair()
        let a = try p.sealTCP(Data("a".utf8))
        let b = try p.sealTCP(Data("b".utf8))
        _ = try m.openTCP(a)
        #expect(throws: SessionCryptoError.replay) { try m.openTCP(a) }
        _ = try m.openTCP(b)
        #expect(throws: SessionCryptoError.replay) { try m.openTCP(a) }
        #expect(throws: SessionCryptoError.replay) { try m.openTCP(b) }
    }

    @Test func udpReplayWindow() throws {
        var (p, m) = pair()
        let packets = try (0..<200).map { try p.sealUDP(Data([UInt8($0 % 256)])) }
        // Out of order within the window is fine, duplicates are not.
        _ = try m.openUDP(packets[10])
        _ = try m.openUDP(packets[5])
        #expect(throws: SessionCryptoError.replay) { try m.openUDP(packets[5]) }
        #expect(throws: SessionCryptoError.replay) { try m.openUDP(packets[10]) }
        _ = try m.openUDP(packets[100])
        // 100 - 37 = 63 behind: last slot inside the window.
        _ = try m.openUDP(packets[37])
        // 64 behind: outside.
        #expect(throws: SessionCryptoError.replay) { try m.openUDP(packets[36]) }
        #expect(throws: SessionCryptoError.replay) { try m.openUDP(packets[0]) }
        _ = try m.openUDP(packets[99])
        #expect(throws: SessionCryptoError.replay) { try m.openUDP(packets[99]) }
        // A large jump clears history but remembers the new highest.
        _ = try m.openUDP(packets[199])
        #expect(throws: SessionCryptoError.replay) { try m.openUDP(packets[199]) }
        _ = try m.openUDP(packets[150])
        #expect(throws: SessionCryptoError.replay) { try m.openUDP(packets[120]) }
    }

    @Test func forgedPacketDoesNotMoveWindow() throws {
        var (p, m) = pair()
        let packets = try (0..<5).map { _ in try p.sealUDP(Data([1])) }
        var forged = Data([0, 0, 0, 0, 0, 0, 0x10, 0])   // counter 4096
        forged.append(Data(repeating: 0, count: 17))
        #expect(throws: SessionCryptoError.authenticationFailed) { try m.openUDP(forged) }
        for pk in packets { _ = try m.openUDP(pk) }      // still accepted: the forgery advanced nothing
    }

    @Test func differentSessionsDeriveDifferentKeys() throws {
        var p1 = SessionCrypto(pairKey: key, phoneNonce: pn, macNonce: mn, role: .phone)
        var p2 = SessionCrypto(pairKey: key, phoneNonce: pn, macNonce: randomBytes(16), role: .phone)
        #expect(try p1.sealTCP(Data("x".utf8)) != p2.sealTCP(Data("x".utf8)))
    }
}

@Suite("Pairing payload")
struct PairingPayloadTests {
    @Test func urlRoundTrip() throws {
        for name in ["Soham's MacBook Pro", "a+b&c=d?e#f/g", "日本語 Mac", ""] {
            let p = PairingPayload(macID: UUID(), macName: name, pairKey: PairingPayload.generateKey())
            let url = p.url
            #expect(url.scheme == "glasspad")
            #expect(url.absoluteString.hasPrefix("glasspad://pair?v=1&id="))
            #expect(PairingPayload(url: url) == p)
            #expect(PairingPayload(url: URL(string: url.absoluteString)!) == p)
        }
    }

    @Test func keyIsBase64URLWithoutPadding() {
        let key = Data(repeating: 0xFB, count: 32)     // encodes to +/ characters in plain base64
        let url = PairingPayload(macID: UUID(), macName: "M", pairKey: key).url.absoluteString
        let k = url.components(separatedBy: "k=").last!
        #expect(!k.contains("+") && !k.contains("/") && !k.contains("="))
        #expect(k.contains("-") || k.contains("_"))
    }

    @Test func invalidURLsAreRejected() {
        let id = UUID().uuidString
        let k = PairingPayload(macID: UUID(), macName: "x", pairKey: Data(repeating: 1, count: 32)).url
            .absoluteString.components(separatedBy: "k=").last!
        let bad = [
            "https://pair?v=1&id=\(id)&name=x&k=\(k)",
            "glasspad://other?v=1&id=\(id)&name=x&k=\(k)",
            "glasspad://pair?v=2&id=\(id)&name=x&k=\(k)",
            "glasspad://pair?v=1&id=nope&name=x&k=\(k)",
            "glasspad://pair?v=1&id=\(id)&k=\(k)",
            "glasspad://pair?v=1&id=\(id)&name=x",
            "glasspad://pair?v=1&id=\(id)&name=x&k=AAAA",
            "glasspad://pair?v=1&id=\(id)&name=x&k=***",
        ]
        for s in bad { #expect(PairingPayload(url: URL(string: s)!) == nil, "\(s)") }
        #expect(PairingPayload(url: URL(string: "glasspad://pair?v=1&id=\(id)&name=x&k=\(k)")!) != nil)
    }

    @Test func codable() throws {
        let p = PairingPayload(macID: UUID(), macName: "Mac", pairKey: PairingPayload.generateKey())
        #expect(try JSONDecoder().decode(PairingPayload.self, from: JSONEncoder().encode(p)) == p)
    }
}
