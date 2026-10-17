import CryptoKit
import Foundation
import Testing
@testable import GlasspadKit

/// Protocol 2's key agreement on its own (no network).
@Suite struct KeyAgreementTests {
    let pairKey = Data(repeating: 0x11, count: 32)
    let np = Data(repeating: 0xA1, count: 16), nm = Data(repeating: 0xB2, count: 16)

    func both(rekey: Bool, macRekey: Bool? = nil, pairKey: Data? = nil, macPairKey: Data? = nil) throws
        -> (phone: KeyAgreement.Keys, mac: KeyAgreement.Keys) {
        let p = KeyAgreement.makeKeyPair(), m = KeyAgreement.makeKeyPair()
        let pp = p.publicKey.rawRepresentation, mp = m.publicKey.rawRepresentation
        let phone = try KeyAgreement.derive(privateKey: p, peerPublicKey: mp, pairKey: pairKey ?? self.pairKey,
                                            phoneNonce: np, macNonce: nm, phonePublicKey: pp, macPublicKey: mp, rekey: rekey)
        let mac = try KeyAgreement.derive(privateKey: m, peerPublicKey: pp, pairKey: macPairKey ?? pairKey ?? self.pairKey,
                                          phoneNonce: np, macNonce: nm, phonePublicKey: pp, macPublicKey: mp,
                                          rekey: macRekey ?? rekey)
        return (phone, mac)
    }

    @Test func bothSidesAgree() throws {
        let k = try both(rekey: true)
        #expect(k.phone == k.mac)
        #expect(k.phone.newPairKey?.count == 32)
        #expect(k.phone.sessionKey.count == 32)
        #expect(k.phone.newPairKey != k.phone.sessionKey)
        let plain = try both(rekey: false)
        #expect(plain.phone == plain.mac && plain.phone.newPairKey == nil)
    }

    /// The new key needs this connection's private keys: the code's key alone does not give it,
    /// and two connections with the same code give different keys.
    @Test func newKeyIsNotTheCodeKeyAndNeverRepeats() throws {
        let a = try both(rekey: true), b = try both(rekey: true)
        #expect(a.phone.newPairKey != pairKey)
        #expect(a.phone.newPairKey != b.phone.newPairKey)
        #expect(a.phone.sessionKey != b.phone.sessionKey)
    }

    /// Someone who flips the rekey flag in either unencrypted hello, or holds a different key,
    /// ends up with different keys, so the key confirmation fails.
    @Test func tamperingOrAWrongKeyGivesDifferentKeys() throws {
        let flipped = try both(rekey: true, macRekey: false)
        #expect(flipped.phone.sessionKey != flipped.mac.sessionKey)
        let wrong = try both(rekey: false, macPairKey: Data(repeating: 0x22, count: 32))
        #expect(wrong.phone.sessionKey != wrong.mac.sessionKey)
    }

    @Test func badPublicKeysAreRefused() {
        let mine = KeyAgreement.makeKeyPair()
        let pub = mine.publicKey.rawRepresentation
        for bad in [Data(count: 31), Data(count: 33), Data(count: 32), Data([1] + [UInt8](repeating: 0, count: 31))] {
            #expect(throws: KeyAgreement.Failure.badPublicKey) {
                try KeyAgreement.derive(privateKey: mine, peerPublicKey: bad, pairKey: pairKey, phoneNonce: np, macNonce: nm,
                                        phonePublicKey: pub, macPublicKey: bad, rekey: true)
            }
        }
    }

    @Test func sessionCryptoFromAnAgreedKeyTalksBothWays() throws {
        let k = try both(rekey: false)
        var phone = SessionCrypto(sessionKey: k.phone.sessionKey, role: .phone)
        var mac = SessionCrypto(sessionKey: k.mac.sessionKey, role: .mac)
        #expect(try mac.openTCP(phone.sealTCP(handshakeConfirmToken)) == handshakeConfirmToken)
        #expect(try phone.openTCP(mac.sealTCP(handshakeConfirmToken)) == handshakeConfirmToken)
        // A protocol 1 session from the same pair key is a different key.
        var v1 = SessionCrypto(pairKey: pairKey, phoneNonce: np, macNonce: nm, role: .mac)
        #expect(throws: SessionCryptoError.authenticationFailed) { try v1.openTCP(phone.sealTCP(handshakeConfirmToken)) }
    }

    /// A phone saves the agreed key in place of the code's, and keeps the rest of the pairing.
    @Test func phoneStoreKeepsTheAgreedKey() throws {
        var macs = KnownMacs()
        let payload = PairingPayload(macID: UUID(), macName: "Mac", pairKey: pairKey)
        macs.add(payload)
        #expect(macs[payload.macID]?.keyAgreed == nil)
        let agreed = Data(repeating: 0x33, count: 32)
        macs.setAgreedKey(agreed, for: payload.macID)
        #expect(macs[payload.macID]?.pairing.pairKey == agreed)
        #expect(macs[payload.macID]?.keyAgreed == true)
        // Scanning the Mac's code again starts over with that code's key.
        macs.add(payload)
        #expect(macs[payload.macID]?.keyAgreed == nil)
        // A list saved by 0.2.x (no keyAgreed field) still reads, as code keys.
        let old = #"{"macs":[{"pairing":{"macID":"\#(payload.macID.uuidString)","macName":"Mac","pairKey":"\#(pairKey.base64EncodedString())"},"pairedAt":0}]}"#
        let read = try JSONDecoder().decode(KnownMacs.self, from: Data(old.utf8))
        #expect(read[payload.macID]?.keyAgreed == nil)
        #expect(read[payload.macID]?.pairing.pairKey == pairKey)
    }

    @Test func storeSaysWhetherTheKeyReachedStorage() {
        final class Failing: KnownMacsStorage, @unchecked Sendable {
            func load() -> Data? { nil }
            func save(_ data: Data) throws { throw KnownMacsStoreError.keychain(-25300) }
        }
        let ok = KnownMacsStore(storage: InMemoryKnownMacsStorage())
        #expect(ok.updateAndSave { $0.add(PairingPayload(macID: UUID(), macName: "M", pairKey: pairKey)) })
        let failing = KnownMacsStore(storage: Failing())
        #expect(!failing.updateAndSave { $0.add(PairingPayload(macID: UUID(), macName: "M", pairKey: pairKey)) })
        // The change that did not reach storage is undone in memory too.
        #expect(failing.current.macs.isEmpty)
    }
}

#if os(macOS)
/// Pairing and migration over loopback, phone and Mac both in this process.
@Suite("Protocol 2 pairing", .serialized)
struct PairingUpgradeTests {
    let macID = UUID()
    let code = PairingPayload.generateKey()
    let q = DispatchQueue(label: "test.pairing")

    func makeServer(_ book: KeyBook, configure: (GlasspadServer) -> Void = { _ in }) async throws -> (GlasspadServer, UInt16) {
        let server = GlasspadServer(macID: macID, macName: "Test Mac", advertise: false, delegateQueue: q,
                                    keyLookup: book.lookup, saveKey: book.save)
        configure(server)
        try server.start()
        #expect(await waitUntil { server.ports != nil })
        return (server, try #require(server.ports).tcp)
    }

    func makeClient(key: Data, agreed: Bool = false, phoneID: String = "phone-1") -> GlasspadClient {
        GlasspadClient(phoneID: phoneID, phoneName: "Test Phone",
                       pairing: PairingPayload(macID: macID, macName: "Test Mac", pairKey: key), keyAgreed: agreed,
                       delegateQueue: q)
    }

    final class Saved: @unchecked Sendable {
        private let lock = NSLock()
        private var keys: [Data] = []
        var all: [Data] { lock.withLock { keys } }
        func add(_ k: Data) { lock.withLock { keys.append(k) } }
    }

    /// A new phone: the code's key opens the first connection only. Both sides then keep an
    /// agreed key, and the code (a screenshot, a copied link) is useless from then on.
    @Test func aCopyOfTheCodeIsUselessAfterPairing() async throws {
        let book = KeyBook()
        let (server, port) = try await makeServer(book) { $0.pendingPairKey = code }
        defer { server.stop() }
        let client = makeClient(key: code)
        let saved = Saved()
        client.onNewPairKey = { saved.add($0); return true }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected && server.state.isConnected })
        let agreed = try #require(book["phone-1"])
        #expect(agreed.agreed && agreed.key != code)
        #expect(saved.all == [agreed.key] && client.pairKey == agreed.key)
        // The phone said it saved the key, so the Mac forgot the code's key.
        #expect(await waitUntil { book["phone-1"]?.previous == nil })
        client.disconnect()

        // Someone else with the code and the phone's ID, either protocol.
        for legacy in [false, true] {
            let thief = makeClient(key: code)
            thief.speaksOnlyProtocol1ForTesting = legacy
            thief.connect(host: "127.0.0.1", port: port)
            try await Task.sleep(nanoseconds: 600_000_000)
            #expect(!thief.state.isConnected)
            thief.disconnect()
        }
        #expect(server.stats.authFailures >= 1)
        #expect(book["phone-1"]?.key == agreed.key)

        // The real phone, with its agreed key, still connects.
        let again = makeClient(key: agreed.key, agreed: true)
        again.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { again.state.isConnected })
        again.disconnect()
    }

    /// A phone and Mac paired by 0.2.x (the code's key on both): the first protocol 2
    /// connection moves them to an agreed key without asking anything.
    @Test func aPhonePairedBefore2MovesToAnAgreedKey() async throws {
        let book = KeyBook(["phone-1": PhoneKey(key: code, agreed: false)])
        let asked = PairedBox()
        let (server, port) = try await makeServer(book) { s in
            s.approveNewPhone = { phone, answer in asked.add(phone); answer(true) }
        }
        defer { server.stop() }
        let client = makeClient(key: code)
        client.onNewPairKey = { _ in true }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected })
        #expect(await waitUntil { book["phone-1"].map { $0.agreed && $0.previous == nil } == true })
        #expect(book["phone-1"]?.key == client.pairKey && client.pairKey != code)
        #expect(asked.phones.isEmpty)
        client.disconnect()
        let next = makeClient(key: client.pairKey, agreed: true)
        next.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { next.state.isConnected })
        next.disconnect()
    }

    /// If the phone could not save the agreed key, the Mac keeps the old one for one more rekey,
    /// so the phone is not locked out.
    @Test func aPhoneThatCouldNotSaveIsNotLockedOut() async throws {
        let book = KeyBook(["phone-1": PhoneKey(key: code, agreed: false)])
        let (server, port) = try await makeServer(book)
        defer { server.stop() }
        let client = makeClient(key: code)
        client.onNewPairKey = { _ in false }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected })
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(book["phone-1"]?.previous == code)
        client.disconnect()
        // After a restart the phone still has the old key.
        let restarted = makeClient(key: code)
        restarted.onNewPairKey = { _ in true }
        restarted.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { restarted.state.isConnected })
        #expect(await waitUntil { book["phone-1"].map { $0.key == restarted.pairKey && $0.previous == nil } == true })
        restarted.disconnect()
    }

    /// The save fails, the phone reconnects in the same run, then restarts: it keeps using the
    /// key it has on disk, so the Mac never drops it, and the phone is never locked out.
    @Test func aFailedSaveThenAReconnectThenARestartStillConnects() async throws {
        let book = KeyBook(["phone-1": PhoneKey(key: code, agreed: false)])
        let (server, port) = try await makeServer(book)
        defer { server.stop() }
        let client = makeClient(key: code)
        client.onNewPairKey = { _ in false }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected })
        #expect(client.pairKey == code && !client.keyAgreed)
        client.disconnect()

        // Same run: connects again with the key it really has, and the Mac still knows it.
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected })
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(client.pairKey == code)
        #expect(book["phone-1"].map { $0.key == code || $0.previous == code } == true)
        client.disconnect()

        // A restart reads the code's key from disk, which still works and now saves.
        let restarted = makeClient(key: code)
        restarted.onNewPairKey = { _ in true }
        restarted.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { restarted.state.isConnected })
        #expect(restarted.keyAgreed)
        #expect(await waitUntil { book["phone-1"].map { $0.key == restarted.pairKey && $0.previous == nil } == true })
        restarted.disconnect()
    }

    /// A 0.2.x phone keeps working with a Mac on protocol 2 while its key is a code's key.
    @Test func aPhoneOn02xStillConnects() async throws {
        let book = KeyBook(["phone-1": PhoneKey(key: code, agreed: false)])
        let (server, port) = try await makeServer(book)
        defer { server.stop() }
        let old = makeClient(key: code)
        old.speaksOnlyProtocol1ForTesting = true
        old.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { old.state.isConnected && server.state.isConnected })
        old.send(message: .mode(.presentNext))
        #expect(book["phone-1"] == PhoneKey(key: code, agreed: false))
        old.disconnect()
    }

    /// A 0.2.x phone cannot pair with a Mac on protocol 2: that would make the code its key.
    @Test func aPhoneOn02xIsAskedToUpdateToPair() async throws {
        let book = KeyBook()
        let (server, port) = try await makeServer(book) { $0.pendingPairKey = code }
        defer { server.stop() }
        let old = makeClient(key: code)
        old.speaksOnlyProtocol1ForTesting = true
        old.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { old.state.failure != nil })
        #expect(old.state.failure == GlasspadService.updatePhoneReason)
        #expect(book["phone-1"] == nil && server.pendingPairKey == code)
        old.disconnect()
    }

    /// A new phone and a Mac still on 0.2.x: the phone falls back to protocol 1 and works as
    /// before; a phone with an agreed key never falls back.
    @Test func aNewPhoneTalksToAMacOn02x() async throws {
        let book = KeyBook(["phone-1": PhoneKey(key: code, agreed: false)])
        let (server, port) = try await makeServer(book) { $0.acceptsOnlyProtocol1ForTesting = true }
        defer { server.stop() }
        let client = makeClient(key: code)
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected })
        #expect(!client.keyAgreed && client.pairKey == code)
        client.disconnect()
        let agreed = makeClient(key: PairingPayload.generateKey(), agreed: true)
        agreed.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { agreed.state.failure != nil })
        #expect(agreed.state.failure == "unsupported version 2")
        agreed.disconnect()
    }

    @Test func dontAllowRefusesTheNewPhone() async throws {
        let book = KeyBook()
        let failures = Locked<[PairingFailure]>([])
        let (server, port) = try await makeServer(book) { s in
            s.pendingPairKey = code
            s.approveNewPhone = { _, answer in answer(false) }
            s.onPairingFailed = { _, why in failures.mutate { $0.append(why) } }
        }
        defer { server.stop() }
        let client = makeClient(key: code)
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.failure != nil })
        #expect(client.state.failure == GlasspadService.notAllowedFailure)
        #expect(book["phone-1"] == nil && !server.state.isConnected)
        #expect(await waitUntil { failures.get() == [.notAllowed] })
        // The code is used up: it does not work for a second try either.
        #expect(server.pendingPairKey == nil)
        client.disconnect()
    }

    /// The question can take longer than the handshake timeout; the phone waits and says why.
    @Test func allowAfterAWhileStillPairs() async throws {
        let book = KeyBook()
        let paired = PairedBox()
        let (server, port) = try await makeServer(book) { s in
            s.pendingPairKey = code
            s.handshakeTimeout = 1
            s.onPaired = { paired.add($0) }
            s.approveNewPhone = { _, answer in
                DispatchQueue.global().asyncAfter(deadline: .now() + GlasspadService.handshakeTimeout + 1) { answer(true) }
            }
        }
        defer { server.stop() }
        let client = makeClient(key: code)
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil(3) { client.issue == .awaitingApproval })
        #expect(paired.phones.isEmpty && book["phone-1"] == nil)
        #expect(await waitUntil(10) { client.state.isConnected })
        #expect(client.issue == nil)
        #expect(await waitUntil { paired.phones.count == 1 })
        #expect(book["phone-1"]?.key == client.pairKey)
        client.disconnect()
    }

    /// The server checks the code's end itself, so a missed UI timer cannot keep it working.
    @Test func anExpiredCodeIsRefusedByTheServer() async throws {
        let book = KeyBook()
        let (server, port) = try await makeServer(book) { $0.armPairing(key: code, expiresAt: Date().addingTimeInterval(-1)) }
        defer { server.stop() }
        #expect(server.pendingPairKey == nil)
        let client = makeClient(key: code)
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.failure != nil })
        #expect(client.state.failure == "not paired")
        client.disconnect()
    }
}
#endif
