import CryptoKit
import Foundation
import Testing
@testable import GlasspadKit

/// The frozen handshake (WireGolden_2026_10_17_Handshake.swift): every hello still reads and is
/// written the same way, and the key agreement still gives the same keys.
@Suite struct HandshakeGoldenTests {
    private static func object(_ data: Data) throws -> NSObject {
        try JSONSerialization.jsonObject(with: data) as! NSObject
    }

    private static func sameShape<T: Codable>(_ type: T.Type, _ line: String) throws -> T {
        let decoded = try JSONDecoder().decode(T.self, from: Data(line.utf8))
        let again = try JSONEncoder().encode(decoded)
        #expect(try object(again) == object(Data(line.utf8)), "written differently now: \(line)")
        return decoded
    }

    @Test func phoneHellosStillReadAndAreWrittenTheSameWay() throws {
        let hellos = try WireGolden.phoneHello_2026_10_17.map { try Self.sameShape(PhoneHello.self, $0) }
        #expect(hellos.map(\.v) == [1, 2, 2])
        #expect(hellos.map(\.rekey) == [nil, true, nil])
        #expect(hellos[0].kx == nil && hellos[1].kx?.count == 32)
    }

    @Test func macHellosStillReadAndAreWrittenTheSameWay() throws {
        let hellos = try WireGolden.macHello_2026_10_17.map { try Self.sameShape(MacHello.self, $0) }
        #expect(hellos.map(\.v) == [1, 2, 2])
        #expect(hellos.map(\.rekey) == [nil, true, false])
        #expect(hellos.allSatisfy { $0.udpPort == 52_100 })
    }

    @Test func rejectAndKeySavedStillRead() throws {
        #expect(try Self.sameShape(HandshakeReject.self, WireGolden.reject_2026_10_17).reason == GlasspadService.updatePhoneReason)
        _ = try Self.sameShape(KeySaved.self, WireGolden.keySaved_2026_10_17)
        // The phone reads the Mac's sealed transport message as an unknown control message.
        #expect(try ControlMessage.from(jsonData: Data(WireGolden.keySaved_2026_10_17.utf8)) == .unknown(type: "keySaved"))
    }

    @Test func keyAgreementGivesTheFrozenKeys() throws {
        typealias V = WireGolden.KeyAgreement_2026_10_17
        func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
        let phone = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data((1...32).map { UInt8($0) }))
        let mac = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data((33...64).map { UInt8($0) }))
        let pp = phone.publicKey.rawRepresentation, mp = mac.publicKey.rawRepresentation
        #expect(pp.base64EncodedString() == V.phonePublic && mp.base64EncodedString() == V.macPublic)
        let key = Data(repeating: 0x11, count: 32), np = Data(repeating: 0xA1, count: 16), nm = Data(repeating: 0xB2, count: 16)
        for (mine, peer) in [(phone, mp), (mac, pp)] {
            let r = try KeyAgreement.derive(privateKey: mine, peerPublicKey: peer, pairKey: key, phoneNonce: np, macNonce: nm,
                                            phonePublicKey: pp, macPublicKey: mp, rekey: true)
            #expect(hex(r.sessionKey) == V.rekeySession)
            #expect(r.newPairKey.map(hex) == V.newPairKey)
            let n = try KeyAgreement.derive(privateKey: mine, peerPublicKey: peer, pairKey: key, phoneNonce: np, macNonce: nm,
                                            phonePublicKey: pp, macPublicKey: mp, rekey: false)
            #expect(hex(n.sessionKey) == V.plainSession && n.newPairKey == nil)
        }
        var sealer = SessionCrypto(sessionKey: try #require(Data(hexString: V.rekeySession)), role: .phone)
        #expect(hex(try sealer.sealTCP(handshakeConfirmToken)) == V.sealedConfirm)
        var opener = SessionCrypto(sessionKey: try #require(Data(hexString: V.rekeySession)), role: .mac)
        #expect(try opener.openTCP(try #require(Data(hexString: V.sealedConfirm))) == handshakeConfirmToken)
    }

    /// The tokens inside the sealed handshake are part of the wire too.
    @Test func handshakeTokensAreFrozen() {
        #expect(String(decoding: handshakeConfirmToken, as: UTF8.self) == "glasspad confirm v1")
        #expect(String(decoding: approvalWaitToken, as: UTF8.self) == "glasspad approval wait v2")
        #expect(String(decoding: approvalDeniedToken, as: UTF8.self) == "glasspad approval denied v2")
        #expect(GlasspadService.protocolVersion == 2 && GlasspadService.legacyProtocolVersion == 1)
    }
}

private extension Data {
    init?(hexString: String) {
        var bytes: [UInt8] = []
        var i = hexString.startIndex
        while i < hexString.endIndex {
            let j = hexString.index(i, offsetBy: 2)
            guard let b = UInt8(hexString[i..<j], radix: 16) else { return nil }
            bytes.append(b)
            i = j
        }
        self.init(bytes)
    }
}
