import Foundation
import Network
import Testing
@testable import GlasspadKit

@Suite struct ReconnectPolicyTests {
    @Test func firstRetriesStayFastThenGrowTo30Seconds() {
        let middle = (0..<9).map { ReconnectBackoff.delay(attempt: $0, random: 0.5) }
        #expect(middle == [0.2, 0.5, 1, 2, 5, 10, 30, 30, 30])
        // Under four seconds of waiting in all before the first long wait.
        #expect(middle.prefix(4).reduce(0, +) < 4)
    }

    @Test func fastRetriesAreExact() {
        for attempt in 0..<4 {
            #expect(ReconnectBackoff.delay(attempt: attempt, random: 0) == ReconnectBackoff.steps[attempt])
            #expect(ReconnectBackoff.delay(attempt: attempt, random: 0.99) == ReconnectBackoff.steps[attempt])
        }
    }

    @Test func jitterStaysWithinAFifthEitherWay() {
        for attempt in 4..<8 {
            let base = ReconnectBackoff.delay(attempt: attempt, random: 0.5)
            let low = ReconnectBackoff.delay(attempt: attempt, random: 0)
            let high = ReconnectBackoff.delay(attempt: attempt, random: 0.999_999)
            #expect(abs(low - base * 0.8) < 1e-9)
            #expect(high <= base * 1.2 && high > base * 1.19)
            for _ in 0..<50 {
                let d = ReconnectBackoff.delay(attempt: attempt)
                #expect(d >= base * 0.8 && d <= base * 1.2)
            }
        }
        // Out of range inputs are clamped, never negative or past the last step.
        #expect(ReconnectBackoff.delay(attempt: -3, random: 0.9) == 0.2)
        #expect(ReconnectBackoff.delay(attempt: 1_000, random: 7) == 36)
    }

    @Test func twoPhonesFailingTogetherDrift() {
        // The same failures with different draws land at different times.
        let a = ReconnectBackoff.delay(attempt: 6, random: 0.1)
        let b = ReconnectBackoff.delay(attempt: 6, random: 0.9)
        #expect(abs(a - b) > 9)
    }

    @Test func aMacThatAnswersIsRetriedQuickly() {
        // It accepted the connection and closed it (restarting a listener): never past 2 s.
        #expect(ReconnectBackoff.delay(attempt: 9, reachedMac: true, random: 0.5) == 2)
        #expect(ReconnectBackoff.delay(attempt: 1, reachedMac: true, random: 0.5) == 0.5)
        #expect(ReconnectBackoff.delay(attempt: 9, reachedMac: false, random: 0.5) == 30)
    }

    @Test func longWaitsWatchForTheMac() {
        #expect(ReconnectBackoff.delay(attempt: 3, random: 0.999) < ReconnectBackoff.watchFrom)
        #expect(ReconnectBackoff.delay(attempt: 4, random: 0) >= ReconnectBackoff.watchFrom)
    }

    @Test func peerToPeerOpensOnceForAMinute() {
        var w = PeerToPeerWindow()
        #expect(!w.isOpen(now: 100) && !w.isSpent(now: 100))
        #expect(w.remaining(now: 100) == nil)
        w.open(now: 100)
        #expect(w.isOpen(now: 100) && w.isOpen(now: 159.9))
        #expect(w.remaining(now: 130) == 30)
        // A second request (a retry inside the window) does not stretch it.
        w.open(now: 150)
        #expect(w.closesAt == 160)
        #expect(!w.isOpen(now: 160) && w.isSpent(now: 160))
        #expect(w.remaining(now: 200) == 0)
        // Closed for good: opening again keeps it closed.
        w.open(now: 300)
        #expect(!w.isOpen(now: 300))
        // Only a fresh start (network change, back in front) opens it again.
        var fresh = PeerToPeerWindow()
        fresh.open(now: 300)
        #expect(fresh.isOpen(now: 300))
    }
}

#if os(macOS)
/// Coming back after the phone was locked: the client knocks on the address the Mac last
/// answered on while Bonjour looks it up, and whatever reaches the Mac first wins, but only on
/// the network the address was learned on. Needs mDNS and a router (skipped with the reason
/// where the sandbox or the machine has neither).
@Suite("Last address", .serialized)
struct LastAddressTests {
    let macID = UUID()
    let key = PairingPayload.generateKey()
    let q = DispatchQueue(label: "test.lastaddress")

    func advertisedServer() async throws -> GlasspadServer {
        let key = self.key
        let server = GlasspadServer(macID: macID, macName: "Glasspad Test \(macID.uuidString.prefix(6))", advertise: true,
                                    delegateQueue: q) { _ in key }
        try server.start()
        #expect(await waitUntil { server.ports != nil })
        if !(await waitUntil(8) { server.isAdvertising }) {
            server.stop()
            try Test.cancel("mDNS unavailable here: the service never registered, so Bonjour was not tested.")
        }
        return server
    }

    func client() -> GlasspadClient {
        GlasspadClient(phoneID: "phone-1", phoneName: "Phone", pairing: PairingPayload(macID: macID, macName: "Test Mac", pairKey: key),
                       delegateQueue: q)
    }

    /// Connects once through Bonjour so the client learns the address and this machine's
    /// network; returns that network.
    func learn(_ server: GlasspadServer) async throws -> String {
        let id = macID
        GlasspadClient.lastAddresses.mutate { $0.forget(id) }
        let first = client()
        first.connect()
        #expect(await waitUntil(10) { first.state.isConnected })
        #expect(!first.connectedViaLastAddress)
        first.disconnect()
        #expect(await waitUntil { !server.state.isConnected })
        guard let network = GlasspadClient.lastAddresses.get().network(of: id) else {
            try Test.cancel("This machine has no router on its network, so no address was learned.")
        }
        return network
    }

    func remember(port: UInt16, network: String) {
        let id = macID
        GlasspadClient.lastAddresses.mutate {
            $0.learn(.hostPort(host: "127.0.0.1", port: .init(rawValue: port)!), network: network, for: id)
        }
    }

    @Test func secondStartUsesTheLastAddress() async throws {
        let server = try await advertisedServer()
        defer { server.stop() }
        _ = try await learn(server)
        let second = client()
        defer { second.disconnect() }
        second.slowBonjourForTesting = 0.5
        let started = ProcessInfo.processInfo.systemUptime
        second.connect()
        #expect(await waitUntil(10) { second.state.isConnected })
        #expect(second.connectedViaLastAddress)
        // Well before the (held back) lookup would even have started.
        #expect(ProcessInfo.processInfo.systemUptime - started < 0.5)
    }

    @Test func deadLastAddressFallsBackToBonjour() async throws {
        let server = try await advertisedServer()
        defer { server.stop() }
        let network = try await learn(server)
        // A port nobody listens on.
        let probe = try NWListener(using: .tcp, on: .any)
        let portBox = Box<UInt16>(0)
        probe.stateUpdateHandler = { if case .ready = $0 { portBox.value = probe.port?.rawValue ?? 0 } }
        probe.newConnectionHandler = { $0.cancel() }
        probe.start(queue: q)
        #expect(await waitUntil { portBox.value != 0 })
        probe.cancel()
        remember(port: portBox.value, network: network)

        let c = client()
        defer { c.disconnect() }
        c.slowBonjourForTesting = 0.3
        c.connect()
        #expect(await waitUntil(10) { c.state.isConnected })
        #expect(!c.connectedViaLastAddress)
        #expect(GlasspadClient.lastAddresses.get().knows(macID))   // learned the right one again
    }

    @Test func anotherMacAtTheLastAddressIsNotARefusal() async throws {
        let server = try await advertisedServer()
        defer { server.stop() }
        let network = try await learn(server)
        // A different Mac (another ID) now answers at the address this phone remembers.
        let other = GlasspadServer(macID: UUID(), macName: "Other Mac", advertise: false, delegateQueue: q) { _ in nil }
        try other.start()
        defer { other.stop() }
        #expect(await waitUntil { other.ports != nil })
        remember(port: try #require(other.ports).tcp, network: network)

        let c = client()
        defer { c.disconnect() }
        c.slowBonjourForTesting = 0.3
        c.connect()
        #expect(await waitUntil(10) { c.state.isConnected })
        #expect(!c.connectedViaLastAddress)
        #expect(server.state.isConnected)
        #expect(c.state.failure == nil)
    }

    /// On another network the address may belong to a stranger's device: the phone must not
    /// send it a hello (which names the phone and the Mac). It looks the Mac up instead.
    @Test func anAddressFromAnotherNetworkIsNeverTried() async throws {
        let server = try await advertisedServer()
        defer { server.stop() }
        _ = try await learn(server)
        // A listener standing in for a device on another network at the remembered address.
        let stranger = try NWListener(using: .tcp, on: .any)
        let knocked = Box<Bool>(false)
        let portBox = Box<UInt16>(0)
        stranger.stateUpdateHandler = { if case .ready = $0 { portBox.value = stranger.port?.rawValue ?? 0 } }
        stranger.newConnectionHandler = { conn in
            knocked.value = true
            conn.cancel()
        }
        stranger.start(queue: q)
        defer { stranger.cancel() }
        #expect(await waitUntil { portBox.value != 0 })
        remember(port: portBox.value, network: "another router")

        let c = client()
        defer { c.disconnect() }
        c.slowBonjourForTesting = 0.3
        c.connect()
        #expect(await waitUntil(10) { c.state.isConnected })
        #expect(!c.connectedViaLastAddress)
        #expect(!knocked.value)
    }
}

/// The address book's rules on their own.
@Suite struct LastAddressBookTests {
    let mac = UUID()
    let home = NWEndpoint.hostPort(host: "192.168.1.20", port: 51000)

    @Test func onlyTheSameNetworkGetsTheAddress() {
        var book = LastAddressBook()
        book.learn(home, network: "192.168.1.1", for: mac)
        #expect(book.address(for: mac, network: "192.168.1.1") == home)
        #expect(book.address(for: mac, network: "10.0.0.1") == nil)
        #expect(book.address(for: mac, network: "") == nil)
    }

    @Test func nothingIsLearnedWithoutANetwork() {
        var book = LastAddressBook()
        book.learn(home, network: "", for: mac)
        #expect(!book.knows(mac))
    }

    @Test func switchingNetworksForgetsAddressesFromElsewhere() {
        var book = LastAddressBook()
        let other = UUID()
        book.learn(home, network: "192.168.1.1", for: mac)
        book.learn(.hostPort(host: "10.0.0.5", port: 50000), network: "10.0.0.1", for: other)
        book.networkSwitched(to: "10.0.0.1")
        #expect(!book.knows(mac))
        #expect(book.knows(other))
        book.networkSwitched(to: "")
        #expect(!book.knows(other))
    }
}
#endif
