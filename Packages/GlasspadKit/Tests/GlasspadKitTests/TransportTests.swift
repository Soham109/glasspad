#if os(macOS)
import Foundation
import CoreGraphics
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
        #expect(paired.phones.first == PairedPhone(phoneID: "new-phone", phoneName: "Test Phone", pairKey: key))
        #expect(server.pendingPairKey == nil)
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
