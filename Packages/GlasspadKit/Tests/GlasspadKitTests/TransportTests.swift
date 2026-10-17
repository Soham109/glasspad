#if os(macOS)
import Foundation
import CoreGraphics
import Network
import Testing
@testable import GlasspadKit

final class Recorder: GlasspadLinkDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _states: [LinkState] = []
    private var _messages: [ControlMessage] = []
    private var _frames: [TouchFrame] = []

    var states: [LinkState] { lock.withLock { _states } }
    var messages: [ControlMessage] { lock.withLock { _messages } }
    var frames: [TouchFrame] { lock.withLock { _frames } }

    func link(didChangeState state: LinkState) { lock.withLock { _states.append(state) } }
    func link(didReceive message: ControlMessage) { lock.withLock { _messages.append(message) } }
    func link(didReceive frame: TouchFrame) { lock.withLock { _frames.append(frame) } }
}

func waitUntil(_ timeout: TimeInterval = 5, _ cond: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if cond() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return cond()
}

extension LinkState {
    var isConnected: Bool { if case .connected = self { return true }; return false }
    var failure: String? { if case .failed(let s) = self { return s }; return nil }
}

/// What the Mac's Keychain would hold, for servers that save keys.
final class KeyBook: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String: PhoneKey]
    private var _saves = 0
    init(_ keys: [String: PhoneKey] = [:]) { self.keys = keys }
    subscript(id: String) -> PhoneKey? { lock.withLock { keys[id] } }
    var saves: Int { lock.withLock { _saves } }
    var lookup: @Sendable (String) -> PhoneKey? { { [self] id in self[id] } }
    var save: @Sendable (PairedPhone, PhoneKey) throws -> Void {
        { [self] phone, key in lock.withLock { keys[phone.phoneID] = key; _saves += 1 } }
    }
    func remove(_ id: String) { _ = lock.withLock { keys.removeValue(forKey: id) } }
}

final class PairedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _phones: [PairedPhone] = []
    var phones: [PairedPhone] { lock.withLock { _phones } }
    func add(_ p: PairedPhone) { lock.withLock { _phones.append(p) } }
}

@Suite("Loopback transport", .serialized)
struct TransportTests {
    let macID = UUID()
    let key = PairingPayload.generateKey()
    let q = DispatchQueue(label: "test.delegate")

    func makeServer(lookup: @escaping @Sendable (String) -> Data?) async throws -> (GlasspadServer, Recorder, UInt16) {
        let rec = Recorder()
        let server = GlasspadServer(macID: macID, macName: "Test Mac", advertise: false, delegateQueue: q, pairKeyLookup: lookup)
        server.delegate = rec
        try server.start()
        #expect(await waitUntil { server.ports != nil })
        let port = try #require(server.ports).tcp
        #expect(await waitUntil { server.state == .searching })
        return (server, rec, port)
    }

    func makeClient(phoneID: String = "phone-1", key: Data? = nil, macID: UUID? = nil) -> (GlasspadClient, Recorder) {
        let rec = Recorder()
        let pairing = PairingPayload(macID: macID ?? self.macID, macName: "Test Mac", pairKey: key ?? self.key)
        let c = GlasspadClient(phoneID: phoneID, phoneName: "Test Phone", pairing: pairing, delegateQueue: q)
        c.delegate = rec
        return (c, rec)
    }

    /// A raw TCP connection that has not paired: records when the Mac closes it.
    final class RawConnection: @unchecked Sendable {
        let conn: NWConnection
        private let lock = NSLock()
        private var _closed = false
        var closed: Bool { lock.withLock { _closed } }
        init(port: UInt16, queue: DispatchQueue) {
            conn = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            conn.start(queue: queue)
            receive()
        }
        private func receive() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [self] _, _, done, error in
                if done || error != nil { lock.withLock { _closed = true }; return }
                receive()
            }
        }
        func send(_ d: Data) { conn.send(content: d, completion: .idempotent) }
    }

    /// Before the handshake only a hello-sized frame is accepted: a frame header that announces
    /// 1 MB closes the connection at once instead of buffering it.
    @Test func bigFrameBeforeHandshakeIsRefused() async throws {
        let key = self.key
        let (server, _, port) = try await makeServer { _ in key }
        defer { server.stop() }
        let raw = RawConnection(port: port, queue: q)
        defer { raw.conn.cancel() }
        var header = Data()
        withUnsafeBytes(of: UInt32(1 << 20).bigEndian) { header.append(contentsOf: $0) }
        raw.send(header + Data(repeating: 1, count: 4096))
        #expect(await waitUntil(1.5) { raw.closed })
    }

    /// Idle connections that never say hello are capped (the oldest is dropped), time out, and do
    /// not lock out a real phone.
    @Test func unauthenticatedConnectionsAreCapped() async throws {
        let key = self.key
        let (server, _, port) = try await makeServer { _ in key }
        defer { server.stop() }
        server.handshakeTimeout = 2
        let raws = (0..<20).map { _ in RawConnection(port: port, queue: q) }
        defer { raws.forEach { $0.conn.cancel() } }
        #expect(await waitUntil(1.5) { raws.filter(\.closed).count >= 20 - GlasspadServer.maxPendingHandshakes })
        let (client, _) = makeClient()
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil(1.5) { client.state.isConnected && server.state.isConnected })
        // The rest time out on their own.
        #expect(await waitUntil(3) { raws.allSatisfy(\.closed) })
        client.disconnect()
    }

    /// A TCP listener that fails is replaced after a pause; the state shows the failure meanwhile.
    @Test func failedTCPListenerIsRestarted() async throws {
        let key = self.key
        let (server, srec, _) = try await makeServer { _ in key }
        defer { server.stop() }
        server.listenerBackoff = [0.2]
        server.failListenerForTesting(tcp: true)
        #expect(await waitUntil(1) { server.state.failure != nil })
        #expect(await waitUntil(2) { server.state == .searching && server.ports != nil })
        #expect(srec.states.contains { $0.failure?.contains("TCP listener") == true })
        let (client, _) = makeClient()
        client.connect(host: "127.0.0.1", port: try #require(server.ports).tcp)
        #expect(await waitUntil { client.state.isConnected && server.state.isConnected })
        client.disconnect()
    }

    /// A UDP listener that fails under a connected phone is replaced, and the phone reconnects
    /// and sends touches to the new port.
    @Test func failedUDPListenerIsRestartedUnderAConnectedPhone() async throws {
        let key = self.key
        let (server, srec, port) = try await makeServer { _ in key }
        defer { server.stop() }
        server.listenerBackoff = [0.2]
        let (client, _) = makeClient()
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected && server.state.isConnected })
        let oldUDP = try #require(server.ports).udp
        server.failListenerForTesting(tcp: false)
        #expect(await waitUntil(1) { !server.state.isConnected })
        #expect(await waitUntil(4) { server.state.isConnected && server.ports != nil })
        #expect(try #require(server.ports).udp != oldUDP)
        let surface = CGSize(width: 390, height: 844)
        #expect(await waitUntil(3) {
            client.send(frame: TouchFrame(seq: 0, timestamp: 1, touches: [Touch(id: 1, phase: .began, x: 5, y: 5)], surface: surface))
            return !srec.frames.isEmpty
        })
    }

    @Test func clientConnectsAndFramesArrive() async throws {
        let key = self.key
        let (server, srec, port) = try await makeServer { $0 == "phone-1" ? key : nil }
        defer { server.stop() }
        let (client, crec) = makeClient()
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)

        #expect(await waitUntil { client.state.isConnected && server.state.isConnected })
        #expect(server.connectedPhone?.phoneID == "phone-1")
        #expect(server.connectedPhone?.phoneName == "Test Phone")
        #expect(crec.states.contains(.connecting))

        let surface = CGSize(width: 390, height: 844)
        let xs: [Double] = [10, 20, 30, 40, 50]
        for (i, x) in xs.enumerated() {
            client.send(frame: TouchFrame(seq: 0, timestamp: 100 + Double(i) * 0.008,
                                          touches: [Touch(id: 3, phase: i == 0 ? .began : .moved, x: x, y: 200)],
                                          surface: surface))
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        client.send(frame: TouchFrame(seq: 0, timestamp: 100.05, touches: [Touch(id: 3, phase: .ended, x: 50, y: 200)],
                                      surface: surface))
        #expect(await waitUntil { srec.frames.contains { $0.touches.first?.phase == .ended } })
        let frames = srec.frames
        let moving = frames.filter { $0.touches.first.map { $0.phase == .began || $0.phase == .moved } ?? false }
        #expect(moving.map { ($0.touches[0].x * 10).rounded() / 10 } == xs)
        #expect(moving.first?.touches.first?.id == 3)
        #expect(frames.allSatisfy { $0.surface == surface })
        let seqs = frames.map(\.seq)
        #expect(seqs == seqs.sorted())
        #expect(server.stats.framesReceived == frames.count)
        #expect(server.stats.authFailures == 0)

        // Control messages both ways.
        client.send(message: .mode(.keysText("hi")))
        #expect(await waitUntil { srec.messages.contains(.mode(.keysText("hi"))) })
        server.send(.haptic(.snap))
        #expect(await waitUntil { crec.messages.contains(.haptic(.snap)) })

        // Keep-awake heartbeats.
        client.heartbeatsEnabled = true
        #expect(await waitUntil { server.stats.heartbeatsReceived >= 10 })
        client.heartbeatsEnabled = false

        // Ping/pong RTT stats (server pings each second).
        #expect(await waitUntil(4) { server.stats.rttMedianMs != nil })
        let stats = server.stats
        #expect(stats.rttP95Ms != nil)
        #expect((stats.rttMedianMs ?? 999) < 200)
        #expect(!crec.messages.contains { if case .ping = $0 { return true }; return false })

        client.disconnect()
        #expect(await waitUntil { server.state == .searching })
        #expect(server.connectedPhone == nil)
    }

    @Test func restingFingerIsResent() async throws {
        let key = self.key
        let (server, srec, port) = try await makeServer { _ in key }
        defer { server.stop() }
        let (client, _) = makeClient()
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected && server.state.isConnected })
        client.send(frame: TouchFrame(seq: 0, timestamp: 1, touches: [Touch(id: 1, phase: .began, x: 5, y: 5)],
                                      surface: CGSize(width: 390, height: 844)))
        #expect(await waitUntil { srec.frames.filter { $0.touches.first?.phase == .stationary }.count >= 5 })
        let resent = srec.frames.filter { $0.touches.first?.phase == .stationary }
        #expect(resent.allSatisfy { $0.touches.count == 1 && $0.touches[0].id == 1 })
    }

    /// Resends only cover fingers still down. After the last lift an empty snapshot follows, so
    /// a lost "ended" packet does not leave the finger down on the Mac (a lost tap, or a drag
    /// held until the stale guard).
    @Test func lastLiftIsFollowedByEmptySnapshots() async throws {
        let key = self.key
        let (server, srec, port) = try await makeServer { _ in key }
        defer { server.stop() }
        let (client, _) = makeClient()
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected && server.state.isConnected })
        let surface = CGSize(width: 390, height: 844)
        client.send(frame: TouchFrame(seq: 0, timestamp: 1, touches: [Touch(id: 1, phase: .began, x: 5, y: 5)], surface: surface))
        client.send(frame: TouchFrame(seq: 0, timestamp: 1.05, touches: [Touch(id: 1, phase: .ended, x: 5, y: 5)], surface: surface))
        #expect(await waitUntil { srec.frames.filter { $0.touches.isEmpty }.count >= GlasspadClient.liftResendCount })
        try await Task.sleep(nanoseconds: 200_000_000)
        let afterLift = srec.frames.drop { $0.touches.first?.phase != .ended }.dropFirst()
        #expect(afterLift.count == GlasspadClient.liftResendCount)
        #expect(afterLift.allSatisfy { $0.touches.isEmpty && $0.surface == surface })
    }

    @Test func pendingPairingAcceptsNewPhoneOnce() async throws {
        let (server, _, port) = try await makeServer { _ in nil }
        defer { server.stop() }
        let paired = PairedBox()
        server.onPaired = { paired.add($0) }
        server.pendingPairKey = key
        let (client, _) = makeClient(phoneID: "new-phone")
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected && server.state.isConnected })
        #expect(await waitUntil { paired.phones.count == 1 })
        // The phone's key is agreed on this connection, never the one in the code.
        #expect(paired.phones.first == PairedPhone(phoneID: "new-phone", phoneName: "Test Phone", pairKey: client.pairKey))
        #expect(client.pairKey != key && client.keyAgreed)
        #expect(server.pendingPairKey == nil)
    }

    /// A phone that is already paired scans the Mac's QR code again (the phone replaces its key
    /// for that Mac). The Mac still holds the old key, so it must accept the pending one.
    @Test func pairedPhoneCanPairAgainWithNewQRCode() async throws {
        let oldKey = PairingPayload.generateKey()
        let book = KeyBook(["phone-1": PhoneKey(key: oldKey, agreed: true)])
        let server = GlasspadServer(macID: macID, macName: "Test Mac", advertise: false, delegateQueue: q,
                                    keyLookup: book.lookup, saveKey: book.save)
        try server.start()
        #expect(await waitUntil { server.ports != nil })
        let port = try #require(server.ports).tcp
        defer { server.stop() }
        let paired = PairedBox()
        server.onPaired = { paired.add($0) }
        server.pendingPairKey = key
        let (client, _) = makeClient(phoneID: "phone-1")
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected && server.state.isConnected })
        #expect(await waitUntil { paired.phones.count == 1 })
        #expect(paired.phones.first == PairedPhone(phoneID: "phone-1", phoneName: "Test Phone", pairKey: client.pairKey))
        #expect(book["phone-1"]?.key == client.pairKey && client.pairKey != key)
        #expect(server.pendingPairKey == nil)
    }

    /// While the QR code is up, a known phone with its old key still connects as before.
    @Test func pairedPhoneKeepsOldKeyWhilePairingIsOpen() async throws {
        let key = self.key
        let (server, _, port) = try await makeServer { $0 == "phone-1" ? key : nil }
        defer { server.stop() }
        let paired = PairedBox()
        server.onPaired = { paired.add($0) }
        let pending = PairingPayload.generateKey()
        server.pendingPairKey = pending
        let (client, _) = makeClient(phoneID: "phone-1")
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected && server.state.isConnected })
        #expect(paired.phones.isEmpty)
        #expect(server.pendingPairKey == pending)
    }

    @Test func unknownPhoneIsRejectedWithoutRetry() async throws {
        let (server, _, port) = try await makeServer { _ in nil }
        defer { server.stop() }
        let (client, _) = makeClient()
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.failure != nil })
        #expect(client.state.failure == "not paired")
    }

    @Test func phoneRevokedMidHandshakeNeverConnects() async throws {
        // The key is there for the hello, then gone (Forget on the Mac) before the confirmation.
        let key = self.key
        let calls = PairedBox()
        let (server, _, port) = try await makeServer { id in
            calls.add(PairedPhone(phoneID: id, phoneName: "", pairKey: Data()))
            return calls.phones.count == 1 ? key : nil
        }
        defer { server.stop() }
        let (client, _) = makeClient()
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.failure != nil })
        #expect(client.state.failure == "not paired")
        #expect(!server.state.isConnected && server.connectedPhone == nil)
    }

    @Test func wrongMacIsRejected() async throws {
        let key = self.key
        let (server, _, port) = try await makeServer { _ in key }
        defer { server.stop() }
        let (client, _) = makeClient(macID: UUID())
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.failure != nil })
        #expect(client.state.failure == "wrong mac")
    }

    @Test func wrongKeyNeverConnectsAndKeepsPendingKey() async throws {
        let (server, _, port) = try await makeServer { _ in nil }
        defer { server.stop() }
        server.pendingPairKey = key
        let (client, _) = makeClient(phoneID: "attacker", key: PairingPayload.generateKey())
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { server.stats.authFailures >= 1 })
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(!client.state.isConnected)
        #expect(!server.state.isConnected)
        #expect(server.pendingPairKey == key)
    }

    @Test func reconnectsAfterServerDrop() async throws {
        let key = self.key
        let (server, srec, port) = try await makeServer { _ in key }
        defer { server.stop() }
        let (client, crec) = makeClient()
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected && server.state.isConnected })
        server.disconnect(reason: "test drop")
        #expect(await waitUntil { crec.messages.contains(.bye(reason: "test drop")) })
        #expect(await waitUntil { srec.states.filter { $0.isConnected }.count >= 2 && server.state.isConnected })
        #expect(await waitUntil { client.state.isConnected })
        client.send(message: .mode(.presentNext))
        #expect(await waitUntil { srec.messages.contains(.mode(.presentNext)) })
    }

    /// A message too big for the peer's frame limit (a large clipboard image, base64 in JSON)
    /// must be dropped by the sender, not sent and answered with a closed connection.
    @Test func oversizedMessageIsDroppedAndSessionSurvives() async throws {
        let key = self.key
        let (server, srec, port) = try await makeServer { _ in key }
        defer { server.stop() }
        let (client, crec) = makeClient()
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected && server.state.isConnected })
        let big = Data(repeating: 0x5A, count: GlasspadService.maxFrameLength * 3 / 4 + 1024)
        server.send(.mode(.clipboardContent(.imagePNG(big))))
        client.send(message: .mode(.clipboardPush(.imagePNG(big))))
        try await Task.sleep(nanoseconds: 1_500_000_000)
        server.send(.haptic(.snap))
        client.send(message: .mode(.presentNext))
        #expect(await waitUntil { crec.messages.contains(.haptic(.snap)) })
        #expect(await waitUntil { srec.messages.contains(.mode(.presentNext)) })
        // The session was never closed and reopened.
        #expect(!srec.states.drop { !$0.isConnected }.contains(.searching))
        #expect(crec.states.filter { $0 == .connecting }.count == 1)
    }

    /// The clipboard image budget leaves room for base64, the JSON around it and the seal.
    @Test func clipboardImageBudgetFitsOneFrame() throws {
        // Random bytes, like a real PNG: about one base64 character in 64 is a "/", which JSON escapes.
        var rng = SystemRandomNumberGenerator()
        let image = Data((0..<ClipboardContent.maxImageBytes).map { _ in UInt8.random(in: 0...255, using: &rng) })
        for m in [ControlMessage.mode(.clipboardContent(.imagePNG(image))), .mode(.clipboardPush(.imagePNG(image)))] {
            #expect(try m.jsonData().count + 8 + 16 <= GlasspadService.maxFrameLength)
        }
    }

    @Test func garbageDatagramsAreCounted() async throws {
        let key = self.key
        let (server, _, port) = try await makeServer { _ in key }
        defer { server.stop() }
        let (client, _) = makeClient()
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected && server.state.isConnected })
        let udpPort = try #require(server.ports).udp
        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        defer { close(sock) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = udpPort.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let junk = [UInt8](repeating: 0x42, count: 64)
        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(sock, junk, junk.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        #expect(await waitUntil { server.stats.authFailures >= 1 })
        #expect(server.state.isConnected)
    }
}
#endif
