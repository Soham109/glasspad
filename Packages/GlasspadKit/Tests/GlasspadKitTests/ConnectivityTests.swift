#if os(macOS)
import Foundation
import CoreGraphics
import Network
import Testing
@testable import GlasspadKit

final class StringsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _items: [String] = []
    var items: [String] { lock.withLock { _items } }
    func add(_ s: String) { lock.withLock { _items.append(s) } }
}

final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ v: T) { _value = v }
    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

/// Frame arrival times for the latency test.
final class LatencyRecorder: GlasspadLinkDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _samples: [Double] = []
    var samples: [Double] { lock.withLock { _samples } }
    func link(didChangeState state: LinkState) {}
    func link(didReceive message: ControlMessage) {}
    func link(didReceive frame: TouchFrame) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.withLock { _samples.append((now - frame.timestamp) * 1000) }
    }
}

/// A loopback TCP proxy that slows one direction to about 400 KB/s, standing in for slow Wi-Fi.
final class SlowProxy: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "test.slowproxy")
    private let target: UInt16
    private let slowToPhone: Bool
    private let chunk = 16 << 10
    private let pause: TimeInterval = 0.04
    private let open = Box<[NWConnection]>([])
    var port: UInt16 { listener.port?.rawValue ?? 0 }

    init(target: UInt16, slowToPhone: Bool) throws {
        self.target = target
        self.slowToPhone = slowToPhone
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] inbound in self?.accept(inbound) }
        listener.start(queue: queue)
    }

    private func accept(_ phoneSide: NWConnection) {
        guard let port = NWEndpoint.Port(rawValue: target) else { return phoneSide.cancel() }
        let macSide = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        open.value += [phoneSide, macSide]
        phoneSide.start(queue: queue)
        macSide.start(queue: queue)
        pump(from: phoneSide, to: macSide, slow: !slowToPhone)
        pump(from: macSide, to: phoneSide, slow: slowToPhone)
    }

    private func pump(from: NWConnection, to: NWConnection, slow: Bool) {
        from.receive(minimumIncompleteLength: 1, maximumLength: slow ? chunk : 1 << 16) { [weak self] data, _, done, error in
            guard let self else { return }
            guard let data, !data.isEmpty else {
                if done || error != nil { to.cancel(); from.cancel() } else { self.pump(from: from, to: to, slow: slow) }
                return
            }
            to.send(content: data, completion: .contentProcessed { _ in
                if slow {
                    self.queue.asyncAfter(deadline: .now() + self.pause) { self.pump(from: from, to: to, slow: slow) }
                } else {
                    self.pump(from: from, to: to, slow: slow)
                }
            })
        }
    }

    func stop() {
        listener.cancel()
        for c in open.value { c.cancel() }
    }
}

@Suite("Connectivity", .serialized)
struct ConnectivityTests {
    let macID = UUID()
    let key = PairingPayload.generateKey()
    let q = DispatchQueue(label: "test.connectivity")

    func makeServer(macID: UUID? = nil, port: UInt16 = 0, advertise: Bool = false, name: String = "Test Mac",
                    lookup: @escaping @Sendable (String) -> Data?) async throws -> (GlasspadServer, Recorder, UInt16) {
        let rec = Recorder()
        let server = GlasspadServer(macID: macID ?? self.macID, macName: name, tcpPort: port, advertise: advertise,
                                    delegateQueue: q, pairKeyLookup: lookup)
        server.delegate = rec
        try server.start()
        #expect(await waitUntil { server.ports != nil })
        let p = try #require(server.ports).tcp
        return (server, rec, p)
    }

    func makeClient(phoneID: String = "phone-1", macID: UUID? = nil, key: Data? = nil) -> (GlasspadClient, Recorder) {
        let rec = Recorder()
        let pairing = PairingPayload(macID: macID ?? self.macID, macName: "Test Mac", pairKey: key ?? self.key)
        let c = GlasspadClient(phoneID: phoneID, phoneName: "Phone \(phoneID)", pairing: pairing, delegateQueue: q)
        c.delegate = rec
        return (c, rec)
    }

    // MARK: Bonjour

    /// Advertises a real `_glasspad._tcp` service and finds it again with both `GlasspadDiscovery`
    /// and the client's own Bonjour connect. Skips (with the reason) only when mDNS itself is
    /// unavailable: the service never registers, or the browser reports a DNS-SD error.
    @Test func bonjourAdvertiseBrowseAndConnect() async throws {
        let key = self.key
        let name = "Glasspad Test \(macID.uuidString.prefix(6))"
        let (server, _, _) = try await makeServer(advertise: true, name: name) { $0 == "phone-1" ? key : nil }
        defer { server.stop() }

        let registered = await waitUntil(8) { server.isAdvertising }
        if !registered {
            try Test.cancel("mDNS unavailable here: mDNSResponder never confirmed the service registration (sandbox or Local Network policy blocks Bonjour). Bonjour discovery was not tested.")
        }

        let discovery = GlasspadDiscovery(delegateQueue: q)
        let failures = StringsBox()
        discovery.onFailure = { failures.add($0) }
        discovery.start()
        defer { discovery.stop() }
        let wanted = macID
        let found = await waitUntil(10) { discovery.macs.contains { $0.macID == wanted } || !failures.items.isEmpty }
        if !found || discovery.macs.first(where: { $0.macID == wanted }) == nil {
            if let failure = failures.items.first {
                try Test.cancel("mDNS browse blocked here (\(failure)). Registration worked; browsing was not tested.")
            }
            Issue.record("the service registered but browsing never found it")
            return
        }
        let mac = try #require(discovery.macs.first { $0.macID == wanted })
        #expect(mac.name == name)
        #expect(mac.protocolVersion == GlasspadService.protocolVersion)

        // The client's Bonjour path: browse, match TXT id, resolve, connect.
        let (client, _) = makeClient()
        defer { client.disconnect() }
        client.connect()
        #expect(await waitUntil(10) { client.state.isConnected && server.state.isConnected })
        #expect(server.connectedPhone?.phoneID == "phone-1")
    }

    // MARK: Session replacement

    @Test func newPhoneReplacesOldSessionCleanly() async throws {
        let key = self.key
        let (server, srec, port) = try await makeServer { ["phone-1", "phone-2"].contains($0) ? key : nil }
        defer { server.stop() }
        let started = StringsBox()
        server.onSessionStarted = { started.add($0.phoneID) }

        let (first, firstRec) = makeClient(phoneID: "phone-1")
        defer { first.disconnect() }
        first.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { first.state.isConnected && server.connectedPhone?.phoneID == "phone-1" })

        let (second, _) = makeClient(phoneID: "phone-2")
        defer { second.disconnect() }
        second.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { second.state.isConnected && server.connectedPhone?.phoneID == "phone-2" })

        // The old phone was told why, and stops instead of stealing the Mac back.
        #expect(await waitUntil { first.state.failure == GlasspadService.replacedFailure })
        #expect(firstRec.messages.contains(.bye(reason: GlasspadService.replacedReason)))
        try await Task.sleep(nanoseconds: 800_000_000)
        #expect(server.connectedPhone?.phoneID == "phone-2")
        #expect(started.items == ["phone-1", "phone-2"])
        #expect(server.state.isConnected)

        // Only the new phone's input is delivered.
        second.send(message: .mode(.presentNext))
        #expect(await waitUntil { srec.messages.contains(.mode(.presentNext)) })
        #expect(server.stats.authFailures == 0)
    }

    // MARK: Why the phone cannot connect (reliability H2, H3)

    /// A Mac that is found but never accepts a connection (guest Wi-Fi, VPN, firewall) used to
    /// leave the phone on "Connecting" forever with no reason. Now the client says why, and
    /// keeps retrying in the background.
    @Test func unreachableMacGivesAReasonAndKeepsRetrying() async throws {
        // A port nobody listens on: every connect fails before TCP opens.
        let probe = try NWListener(using: .tcp, on: .any)
        let portBox = Box<UInt16>(0)
        probe.stateUpdateHandler = { if case .ready = $0 { portBox.value = probe.port?.rawValue ?? 0 } }
        probe.newConnectionHandler = { $0.cancel() }
        probe.start(queue: q)
        #expect(await waitUntil { portBox.value != 0 })
        let port = portBox.value
        probe.cancel()
        try await Task.sleep(nanoseconds: 100_000_000)

        let (client, _) = makeClient()
        defer { client.disconnect() }
        let seen = Box<[LinkIssue?]>([])
        client.onIssueChange = { seen.value.append($0) }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil(8) { client.issue == .networkBlocksDevices })
        #expect(await waitUntil { seen.value.contains(.networkBlocksDevices) })
        #expect(!client.state.isConnected)
        #expect(client.state.failure == nil)       // not given up: still retrying
        #expect(LinkIssue.networkBlocksDevices.message.contains("network"))
    }

    @Test func issueClearsOnceConnected() async throws {
        let key = self.key
        let (server, _, port) = try await makeServer { _ in key }
        defer { server.stop() }
        let (client, _) = makeClient()
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected })
        #expect(client.issue == nil)
    }

    @Test func failureTrackerTriesPeerToPeerThenReports() {
        var t = ConnectFailureTracker()
        #expect(t.record() == (false, false))
        #expect(t.record() == (true, false))      // second failure: allow peer-to-peer Wi-Fi
        #expect(t.record() == (true, false))
        #expect(t.record() == (true, true))       // fourth: tell the user why
    }

    /// A denied Local Network permission parks NWBrowser in `.waiting(PolicyDenied)`; it used to
    /// be ignored, so the phone said "Looking for your Mac" forever.
    @Test func policyDeniedIsRecognisedAsLocalNetworkDenied() {
        #expect(LinkIssue.isLocalNetworkDenied(NWError.dns(DNSServiceErrorType(-65570))))
        #expect(!LinkIssue.isLocalNetworkDenied(NWError.dns(DNSServiceErrorType(-65563))))   // service not running
        #expect(!LinkIssue.isLocalNetworkDenied(NWError.posix(.ECONNREFUSED)))
        #expect(LinkIssue.isLocalNetworkDenied(reason: "unreachable: \(NWError.dns(DNSServiceErrorType(-65570)))"))
        #expect(!LinkIssue.isLocalNetworkDenied(reason: "unreachable: \(NWError.posix(.ECONNREFUSED))"))
        #expect(LinkIssue.localNetworkDenied.message.contains("Local Network"))
    }

    // MARK: Mac status

    /// The Mac's status reaches the phone as a message, and a message type from a newer build
    /// (either way) is ignored without ending the session.
    @Test func macStatusArrivesAndUnknownTypesKeepTheSession() async throws {
        let key = self.key
        let (server, srec, port) = try await makeServer { _ in key }
        defer { server.stop() }
        let (client, crec) = makeClient()
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected && server.state.isConnected })

        server.send(.unknown(type: "fromTheFuture"))
        client.send(message: .unknown(type: "fromTheFuture"))
        let status = MacStatus(accessibilityTrusted: false, automationMedia: .notDetermined, macName: "Test Mac")
        server.send(.macStatus(status))
        client.send(message: .haptic(.snap))
        #expect(await waitUntil { crec.messages.contains(.macStatus(status)) })
        #expect(await waitUntil { srec.messages.contains(.haptic(.snap)) })
        #expect(!crec.messages.contains { if case .unknown = $0 { true } else { false } })
        #expect(!srec.messages.contains { if case .unknown = $0 { true } else { false } })
        #expect(client.state.isConnected && server.state.isConnected)
        #expect(server.stats.malformed == 0)
    }

    // MARK: Wake-on-LAN

    @Test func macSendsWakeTargetAfterHandshake() async throws {
        let key = self.key
        let (server, _, port) = try await makeServer { _ in key }
        defer { server.stop() }
        let target = WakeTarget(macAddress: "a4:83:e7:01:02:03", broadcastAddress: "192.168.1.255", lastIPv4: "192.168.1.20")
        server.wakeTargetOverride = target
        let (client, crec) = makeClient()
        defer { client.disconnect() }
        let received = Box<WakeTarget?>(nil)
        client.onWakeTarget = { received.value = $0 }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { received.value == target })
        #expect(client.wakeTarget == target)
        // It is transport-internal: never surfaces as a ControlMessage.
        #expect(crec.messages.isEmpty)
    }

    @Test func loopbackHasNoWakeTarget() async throws {
        let key = self.key
        let (server, _, port) = try await makeServer { _ in key }
        defer { server.stop() }
        let (client, _) = makeClient()
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected })
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(client.wakeTarget == nil)       // lo0 has no hardware address
    }

    @Test func magicPacketLayoutAndParsing() throws {
        let p = try #require(WakeOnLAN.magicPacket(macAddress: "A4-83-E7-01-02-0F"))
        #expect(p.count == WakeOnLAN.packetLength)
        #expect(Array(p.prefix(6)) == [UInt8](repeating: 0xFF, count: 6))
        for i in 0..<16 {
            #expect(Array(p[(6 + i * 6)..<(12 + i * 6)]) == [0xA4, 0x83, 0xE7, 0x01, 0x02, 0x0F])
        }
        for bad in ["", "a4:83:e7:01:02", "a4:83:e7:01:02:03:04", "zz:83:e7:01:02:03", "a4:83:e7:01:02:3", "00:00:00:00:00:00"] {
            #expect(WakeOnLAN.magicPacket(macAddress: bad) == nil, "\(bad)")
        }
        #expect(WakeOnLAN.formatMAC([0xA4, 0x83, 0xE7, 1, 2, 0x0F]) == "a4:83:e7:01:02:0f")
        #expect(throws: WakeOnLANError.badMACAddress("nope")) {
            try WakeOnLAN.send(to: WakeTarget(macAddress: "nope", broadcastAddress: "127.255.255.255"))
        }
    }

    /// Sends a real magic packet over UDP to a socket listening on loopback.
    @Test func magicPacketGoesOutOverUDP() throws {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        #expect(fd >= 0)
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        #expect(bound == 0)
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        let port = UInt16(bigEndian: addr.sin_port)
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Broadcast to the loopback net may or may not be allowed; the unicast copy must arrive.
        let sent = try WakeOnLAN.send(to: WakeTarget(macAddress: "a4:83:e7:01:02:03", broadcastAddress: "127.255.255.255",
                                                     lastIPv4: "127.0.0.1", port: port))
        #expect(sent.contains("127.0.0.1"))
        var buf = [UInt8](repeating: 0, count: 256)
        let n = recv(fd, &buf, buf.count, 0)
        #expect(n == WakeOnLAN.packetLength)
        #expect(Data(buf.prefix(max(n, 0))) == WakeOnLAN.magicPacket(macAddress: "a4:83:e7:01:02:03"))
    }

    /// Finds the wake target for a real interface on this Mac (Wi-Fi or Ethernet).
    @Test func wakeTargetForARealInterface() throws {
        let list = WakeOnLAN.interfaces()
        #expect(list.contains { $0.name == "lo0" && $0.macAddress == nil })
        #expect(WakeOnLAN.target(forLocalAddress: "127.0.0.1", in: list) == nil)
        guard let iface = list.first(where: { $0.macAddress != nil && $0.broadcast != nil && !$0.ipv4.isEmpty }) else {
            try Test.cancel("no interface with an IPv4 broadcast address here (offline?)")
        }
        let target = try #require(WakeOnLAN.target(forLocalAddress: iface.ipv4[0], in: list))
        #expect(target.macAddress == iface.macAddress)
        #expect(target.broadcastAddress == iface.broadcast)
        #expect(target.lastIPv4 == iface.ipv4[0])
        #expect(WakeOnLAN.parseMAC(target.macAddress) != nil)
        if let v6 = iface.ipv6.first {      // the phone may reach the Mac over IPv6 link-local
            #expect(WakeOnLAN.target(forLocalAddress: v6, in: list) == target)
        }
        // A synthetic list pins the matching rules down.
        let fake = [WakeOnLAN.Interface(name: "en9", macAddress: "02:00:00:00:00:01", ipv4: ["10.0.0.7"],
                                        ipv6: ["fe80::1%en9"], broadcast: "10.0.0.255")]
        #expect(WakeOnLAN.target(forLocalAddress: "fe80::1", in: fake)?.broadcastAddress == "10.0.0.255")
        #expect(WakeOnLAN.target(forLocalAddress: "10.0.0.8", in: fake) == nil)
    }

    // MARK: Staying connected

    /// The Mac stops pinging (it went to sleep): the phone notices within its silence timeout and
    /// reconnects by itself, without waiting for TCP.
    @Test func silentMacTriggersFastReconnect() async throws {
        let key = self.key
        let (server, srec, port) = try await makeServer { _ in key }
        defer { server.stop() }
        server.pingInterval = 30           // never pings during the test
        server.silenceTimeout = 60
        let (client, crec) = makeClient()
        defer { client.disconnect() }
        client.silenceTimeout = 0.4
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected })
        #expect(await waitUntil(4) { srec.states.filter(\.isConnected).count >= 3 })
        #expect(crec.states.filter(\.isConnected).count >= 2)
        #expect(crec.states.contains(.connecting))
    }

    /// A phone that went quiet (suspended, out of range) is dropped by the Mac.
    @Test func silentPhoneIsDroppedByTheMac() async throws {
        let key = self.key
        let (server, _, port) = try await makeServer { _ in key }
        defer { server.stop() }
        server.pingInterval = 0.1
        server.silenceTimeout = 0.5
        let (client, _) = makeClient()
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected && server.state.isConnected })
        // Pongs keep it alive well past the timeout.
        try await Task.sleep(nanoseconds: 900_000_000)
        #expect(server.state.isConnected)
        // Freeze the phone: no pongs any more (the delegate queue is irrelevant; the client queue is blocked).
        client.blockQueueForTesting(seconds: 1.2)
        #expect(await waitUntil(3) { !server.state.isConnected })
        client.disconnect()
    }

    /// Wi-Fi came back (or the phone woke) while the client was waiting out a 2 s backoff: it
    /// retries at once instead.
    @Test func networkChangeSkipsTheBackoff() async throws {
        let key = self.key
        // Learn a free port, then close it so the first attempts fail.
        let (probe, _, port) = try await makeServer { _ in key }
        probe.stop()
        let (client, crec) = makeClient()
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)
        // 0.2 + 0.5 + 1 s of failures: the next wait is 2 s.
        try await Task.sleep(nanoseconds: 1_900_000_000)
        #expect(!client.state.isConnected)
        let (server, _, _) = try await makeServer(port: port) { _ in key }
        defer { server.stop() }
        let before = Date()
        // A change that still has loopback: if a slow machine let the scheduled retry connect
        // first, that session stays, so exactly one connect either way.
        client.networkChanged(satisfied: true, interfaceNames: ["lo0", "en0"])
        #expect(await waitUntil(1.5) { client.state.isConnected })
        #expect(Date().timeIntervalSince(before) < 1.0)
        #expect(crec.states.filter(\.isConnected).count == 1)

        // Connected over loopback, an unrelated change that keeps lo0 does not drop the session.
        client.networkChanged(satisfied: true, interfaceNames: ["lo0", "en0"])
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(crec.states.filter(\.isConnected).count == 1)
        // The interface carrying the session went away: start over right now.
        client.networkChanged(satisfied: true, interfaceNames: ["en0"])
        #expect(await waitUntil(1.5) { crec.states.filter(\.isConnected).count == 2 && client.state.isConnected })
        // Another Wi-Fi network on the same interface (new router): the old socket is dead.
        client.networkChanged(satisfied: true, interfaceNames: ["lo0"], networkSwitched: true)
        #expect(await waitUntil(1.5) { crec.states.filter(\.isConnected).count == 3 && client.state.isConnected })
        // No network at all: nothing to do until it returns.
        client.networkChanged(satisfied: false, interfaceNames: [])
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(client.state.isConnected)
    }

    @Test func reconnectNowKeepsALiveSession() async throws {
        let key = self.key
        let (server, srec, port) = try await makeServer { _ in key }
        defer { server.stop() }
        let (client, crec) = makeClient()
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected && server.state.isConnected })
        client.reconnectNow()               // heard from the Mac within the last second
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(crec.states.filter(\.isConnected).count == 1)
        #expect(stayedConnected(srec.states))
    }

    // MARK: Large messages on slow Wi-Fi

    /// Reliability M1: a big clipboard message from the Mac takes longer than the phone's
    /// silence timeout on slow Wi-Fi, and the pings queue behind it. The partial message now
    /// counts as hearing the Mac, so the link stays up and the message arrives.
    @Test func slowLargeMessageToThePhoneKeepsTheLink() async throws {
        let key = self.key
        let (server, srec, port) = try await makeServer { _ in key }
        defer { server.stop() }
        server.pingInterval = 0.2
        let proxy = try SlowProxy(target: port, slowToPhone: true)
        defer { proxy.stop() }
        #expect(await waitUntil { proxy.port != 0 })
        let (client, crec) = makeClient()
        defer { client.disconnect() }
        client.silenceTimeout = 0.6
        client.connect(host: "127.0.0.1", port: proxy.port)
        #expect(await waitUntil { client.state.isConnected && server.state.isConnected })
        // About 1.5 s through the proxy, well over the 0.6 s silence timeout.
        let text = String(repeating: "x", count: 600_000)
        let start = Date()
        server.send(.mode(.clipboardContent(.text(text))))
        #expect(await waitUntil(8) { crec.messages.contains(.mode(.clipboardContent(.text(text)))) })
        #expect(Date().timeIntervalSince(start) > 1.0, "the proxy did not slow the message down")
        #expect(crec.states.filter(\.isConnected).count == 1)
        #expect(stayedConnected(srec.states))
    }

    /// The same the other way: a big push from the phone keeps the Mac from closing the session
    /// while the phone's pongs wait behind it.
    @Test func slowLargeMessageToTheMacKeepsTheSession() async throws {
        let key = self.key
        let (server, srec, port) = try await makeServer { _ in key }
        defer { server.stop() }
        server.pingInterval = 0.2
        server.silenceTimeout = 0.6
        let proxy = try SlowProxy(target: port, slowToPhone: false)
        defer { proxy.stop() }
        #expect(await waitUntil { proxy.port != 0 })
        let (client, crec) = makeClient()
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: proxy.port)
        #expect(await waitUntil { client.state.isConnected && server.state.isConnected })
        let text = String(repeating: "y", count: 600_000)
        let start = Date()
        client.send(message: .mode(.clipboardPush(.text(text))))
        #expect(await waitUntil(8) { srec.messages.contains(.mode(.clipboardPush(.text(text)))) })
        #expect(Date().timeIntervalSince(start) > 1.0, "the proxy did not slow the message down")
        #expect(stayedConnected(srec.states))
        #expect(crec.states.filter(\.isConnected).count == 1)
    }

    /// The Mac reports `connected` again whenever the round trip changes; any other state after
    /// the first `connected` means the session dropped.
    private func stayedConnected(_ states: [LinkState]) -> Bool {
        guard let first = states.firstIndex(where: \.isConnected) else { return false }
        return states[first...].allSatisfy(\.isConnected)
    }

    // MARK: Several Macs

    @Test func knownMacsTracksPairingsAndLastUsed() throws {
        let a = PairingPayload(macID: UUID(), macName: "Studio", pairKey: PairingPayload.generateKey())
        let b = PairingPayload(macID: UUID(), macName: "Laptop", pairKey: PairingPayload.generateKey())
        var macs = KnownMacs()
        #expect(macs.lastUsed == nil)
        macs.add(a, at: Date(timeIntervalSince1970: 100))
        macs.add(b, at: Date(timeIntervalSince1970: 200))
        #expect(macs.lastUsed?.id == b.macID)
        macs.markConnected(a.macID, at: Date(timeIntervalSince1970: 300))
        #expect(macs.lastUsed?.id == a.macID)
        #expect(macs.byRecency.map(\.id) == [a.macID, b.macID])
        macs.select(b.macID)
        #expect(macs.lastUsed?.id == b.macID)
        macs.select(UUID())                 // unknown: ignored
        #expect(macs.lastUsed?.id == b.macID)

        let wake = WakeTarget(macAddress: "02:00:00:00:00:01", broadcastAddress: "10.0.0.255")
        macs.setWakeTarget(wake, for: a.macID)
        // Re-pairing a Mac replaces its key but keeps its history.
        let a2 = PairingPayload(macID: a.macID, macName: "Studio 2", pairKey: PairingPayload.generateKey())
        macs.add(a2, at: Date(timeIntervalSince1970: 400))
        #expect(macs.macs.count == 2)
        #expect(macs[a.macID]?.pairing == a2)
        #expect(macs[a.macID]?.wakeTarget == wake)
        #expect(macs[a.macID]?.lastConnectedAt == Date(timeIntervalSince1970: 300))
        #expect(macs.lastUsed?.id == a.macID)

        macs.remove(a.macID)
        #expect(macs.lastUsed?.id == b.macID)
        macs.remove(b.macID)
        #expect(macs.lastUsed == nil)
        #expect(macs.macs.isEmpty)
    }

    @Test func knownMacsStorePersists() throws {
        let storage = InMemoryKnownMacsStorage()
        let a = PairingPayload(macID: UUID(), macName: "Studio", pairKey: PairingPayload.generateKey())
        let store = KnownMacsStore(storage: storage)
        store.update { $0.add(a) }
        let reopened = KnownMacsStore(storage: storage)
        #expect(reopened.current == store.current)
        #expect(reopened.current.lastUsed?.pairing == a)
        // Garbage in storage starts empty instead of crashing.
        #expect(KnownMacsStore(storage: InMemoryKnownMacsStorage(Data("nope".utf8))).current.macs.isEmpty)
    }

    /// Two updates from different threads: the stored bytes must be the later state. A slow save
    /// (the Keychain) that finished after a newer one used to leave the older state on disk.
    @Test func knownMacsStoreSavesInUpdateOrder() throws {
        final class SlowFirstSave: KnownMacsStorage, @unchecked Sendable {
            let lock = NSLock()
            var saved: Data?
            var calls = 0
            var store: KnownMacsStore?
            let second = DispatchGroup()
            let b = PairingPayload(macID: UUID(), macName: "Laptop", pairKey: PairingPayload.generateKey())
            func load() -> Data? { nil }
            func save(_ d: Data) throws {
                let first = lock.withLock { calls += 1; return calls == 1 }
                if first, let store {
                    // Another thread changes the store while this write is still in progress.
                    second.enter()
                    let b = self.b
                    Thread.detachNewThread { store.update { $0.add(b) }; self.second.leave() }
                    Thread.sleep(forTimeInterval: 0.2)
                }
                lock.withLock { saved = d }
            }
        }
        let storage = SlowFirstSave()
        let store = KnownMacsStore(storage: storage)
        storage.store = store
        let a = PairingPayload(macID: UUID(), macName: "Studio", pairKey: PairingPayload.generateKey())
        store.update { $0.add(a) }
        storage.second.wait()
        let onDisk = try JSONDecoder().decode(KnownMacs.self, from: try #require(storage.lock.withLock { storage.saved }))
        #expect(onDisk == store.current)
        #expect(onDisk.macs.count == 2)
    }

    /// Two Macs on loopback: connect to a chosen one, switch, then auto-connect to the last used.
    @Test func connectorSwitchesBetweenMacsAndRemembersTheLastOne() async throws {
        let keyA = PairingPayload.generateKey(), keyB = PairingPayload.generateKey()
        let idA = UUID(), idB = UUID()
        let (macA, _, portA) = try await makeServer(macID: idA, name: "Mac A") { _ in keyA }
        defer { macA.stop() }
        let (macB, _, portB) = try await makeServer(macID: idB, name: "Mac B") { _ in keyB }
        defer { macB.stop() }
        let wakeB = WakeTarget(macAddress: "02:00:00:00:00:0b", broadcastAddress: "10.0.0.255")
        macB.wakeTargetOverride = wakeB

        let storage = InMemoryKnownMacsStorage()
        let store = KnownMacsStore(storage: storage)
        store.update {
            $0.add(PairingPayload(macID: idA, macName: "Mac A", pairKey: keyA))
            $0.add(PairingPayload(macID: idB, macName: "Mac B", pairKey: keyB))
        }
        let ports = [idA: portA, idB: portB]
        let rec = Recorder()
        let connector = MacConnector(store: store, phoneID: "phone-1", phoneName: "Phone", delegateQueue: q)
        connector.delegate = rec
        connector.manualAddress = { id in ports[id].map { ("127.0.0.1", $0) } }

        connector.connect(to: idA)
        #expect(await waitUntil { macA.state.isConnected && connector.state.isConnected })
        #expect(connector.activeMacID == idA)
        #expect(store.current.lastUsedID == idA)
        #expect(throws: MacConnectorError.noWakeTarget) { try connector.wake() }

        connector.connect(to: idB)
        #expect(await waitUntil { macB.state.isConnected && connector.state.isConnected })
        #expect(await waitUntil { !macA.state.isConnected })      // the old Mac was told bye
        #expect(await waitUntil { store.current[idB]?.wakeTarget == wakeB })
        #expect(store.current[idB]?.lastConnectedAt != nil)
        #expect(store.current.lastUsedID == idB)
        connector.disconnect()
        #expect(await waitUntil { !macB.state.isConnected })

        // A fresh launch: auto-connect picks Mac B again.
        let relaunched = MacConnector(store: KnownMacsStore(storage: storage), phoneID: "phone-1", phoneName: "Phone",
                                      delegateQueue: q)
        relaunched.manualAddress = { id in ports[id].map { ("127.0.0.1", $0) } }
        #expect(relaunched.connectToLastUsed())
        #expect(await waitUntil { macB.state.isConnected && relaunched.state.isConnected })
        #expect(relaunched.activeMacID == idB)
        relaunched.disconnect()

        let empty = MacConnector(store: KnownMacsStore(storage: InMemoryKnownMacsStorage()), phoneID: "p", phoneName: "P")
        #expect(!empty.connectToLastUsed())
        #expect(throws: MacConnectorError.notPaired) { try empty.wake() }
    }

    // MARK: Latency

    /// Touch-path latency on loopback: encode + seal + UDP send + receive + open + decode +
    /// delegate hop, measured with one clock (the frame timestamp is `systemUptime` at send).
    @Test func loopbackTouchLatency() async throws {
        let key = self.key
        let rec = LatencyRecorder()
        let server = GlasspadServer(macID: macID, macName: "Test Mac", advertise: false,
                                    delegateQueue: DispatchQueue(label: "test.latency", qos: .userInteractive)) { _ in key }
        server.delegate = rec
        try server.start()
        defer { server.stop() }
        #expect(await waitUntil { server.ports != nil })
        let port = try #require(server.ports).tcp
        let (client, _) = makeClient()
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected && server.state.isConnected })
        try await Task.sleep(nanoseconds: 100_000_000)

        let surface = CGSize(width: 390, height: 844)
        let count = 400
        for i in 0..<count {
            let t = ProcessInfo.processInfo.systemUptime
            client.send(frame: TouchFrame(seq: 0, timestamp: t, touches: [
                Touch(id: 1, phase: i == 0 ? .began : .moved, x: Double(i % 300), y: 300),
                Touch(id: 2, phase: i == 0 ? .began : .moved, x: Double(i % 300) + 40, y: 300),
            ], surface: surface))
            try await Task.sleep(nanoseconds: 4_000_000)
        }
        #expect(await waitUntil { rec.samples.count >= count * 9 / 10 })
        // Resends of a resting finger carry a fresh timestamp too, so every sample is valid.
        let sorted = rec.samples.sorted()
        let p50 = try #require(percentile(sorted, 0.5)), p95 = try #require(percentile(sorted, 0.95))
        let line = String(format: "loopback touch latency over %d frames: p50 %.3f ms, p95 %.3f ms, max %.3f ms",
                          sorted.count, p50, p95, sorted.last ?? 0)
        print(line)
        // Loose bound so a busy CI machine does not flake; the printed numbers are the result.
        #expect(p95 < 25, "\(line)")
    }
}
#endif
