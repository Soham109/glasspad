import Foundation
import Testing
@testable import GlasspadKit

@Suite("Keyboard input")
struct KeyboardInputTests {
    @Test func oneTapAppliesToTheNextKeyOnly() {
        var m = StickyModifiers()
        m.tap(.command, at: 0)
        #expect(m.state(of: .command) == .latched)
        #expect(m.active == .command)
        #expect(m.consume() == .command)
        #expect(m.isEmpty)
        #expect(m.consume() == [])
    }

    @Test func doubleTapLocksUntilTappedAgain() {
        var m = StickyModifiers()
        m.tap(.shift, at: 10)
        m.tap(.shift, at: 10.25)
        #expect(m.state(of: .shift) == .locked)
        #expect(m.consume() == .shift)
        #expect(m.consume() == .shift)
        #expect(m.locked == .shift)
        m.tap(.shift, at: 20)
        #expect(m.state(of: .shift) == .off)
        #expect(m.isEmpty)
    }

    @Test func slowSecondTapReleases() {
        var m = StickyModifiers()
        m.tap(.option, at: 0)
        m.tap(.option, at: 0.41 + StickyModifiers.doubleTapWindow)
        #expect(m.state(of: .option) == .off)
    }

    @Test func lockedAndLatchedCombine() {
        var m = StickyModifiers()
        m.tap(.command, at: 0)
        m.tap(.command, at: 0.1)          // locked
        m.tap(.shift, at: 1)              // latched
        #expect(m.active == [.command, .shift])
        #expect(m.consume() == [.command, .shift])
        #expect(m.active == .command)
        m.clear()
        #expect(m.isEmpty)
    }

    @Test func repeatTiming() {
        let r = KeyRepeat.system
        #expect(r.presses(afterHolding: 0) == 1)
        #expect(r.presses(afterHolding: 0.49) == 1)
        #expect(r.presses(afterHolding: 0.5) == 2)
        #expect(r.presses(afterHolding: 0.59) == 3)
        #expect(r.presses(afterHolding: 1.4) == 12)
        #expect(r.delay(beforePress: 1) == 0)
        #expect(r.delay(beforePress: 2) == 0.5)
        #expect(r.delay(beforePress: 3) == 0.09)
        // The waits add up to the same count.
        var t = 0.0, n = 1
        while t + r.delay(beforePress: n + 1) <= 1.4 + 1e-9 { n += 1; t += r.delay(beforePress: n) }
        #expect(n == r.presses(afterHolding: 1.4))
    }

    @Test func roundTripStatsAndQualityWords() {
        var s = RoundTripStats()
        #expect(LinkQuality(s) == nil)
        for ms in [6.0, 8, 7, 9, 30] { s.add(ms) }
        #expect(s.medianMs == 8)
        #expect(LinkQuality(s) == .excellent)
        for _ in 0..<30 { s.add(120) }
        #expect(s.count == RoundTripStats.window)
        #expect(LinkQuality(s) == .poor)
        #expect(LinkQuality(medianMs: 25, p95Ms: 60) == .good)
        #expect(LinkQuality(medianMs: 12, p95Ms: 90) == .good)
        #expect(LinkQuality(medianMs: 50, p95Ms: 300) == .fair)
        #expect(LinkQuality.allCases.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
    }

    @Test func functionKeysRoundTripOnTheWire() throws {
        for k in [SpecialKey.f1, .f6, .f12] {
            let m = ModeMessage.keysKeystroke(Keystroke(key: .special(k), modifiers: [.shift]))
            let data = try JSONEncoder().encode(m)
            #expect(try JSONDecoder().decode(ModeMessage.self, from: data) == m)
        }
    }
}

#if os(macOS)
import Network
import CoreGraphics

@Suite("Round trip", .serialized)
struct RoundTripTests {
    /// The phone measures its own round trips with pings the Mac already answers, and knows
    /// which way the session goes (here, loopback).
    @Test func phoneMeasuresRoundTripAndPath() async throws {
        let macID = UUID(), key = PairingPayload.generateKey()
        let q = DispatchQueue(label: "test.roundtrip")
        let server = GlasspadServer(macID: macID, macName: "Test Mac", advertise: false, delegateQueue: q) { _ in key }
        try server.start()
        defer { server.stop() }
        #expect(await waitUntil { server.ports != nil })
        let port = try #require(server.ports).tcp
        let client = GlasspadClient(phoneID: "phone-rtt", phoneName: "Phone", pairing: PairingPayload(macID: macID, macName: "Test Mac", pairKey: key), delegateQueue: q)
        defer { client.disconnect() }
        #expect(client.path == nil)
        client.measuresRoundTrip = true
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected })
        #expect(client.path == .loopback)
        #expect(await waitUntil(6) { client.roundTrip.count >= 3 })
        let median = try #require(client.roundTrip.medianMs)
        #expect(median >= 0 && median < 200)
        #expect(LinkQuality(client.roundTrip) != nil)
        client.disconnect()
        #expect(await waitUntil { client.path == nil })
    }

    /// Nothing goes out 50 times a second unless something needs it: off the trackpad (no
    /// heartbeats, no finger) the client sends no datagrams; heartbeats bring the tick back, and
    /// a short idle window (Low Power Mode) stops them again.
    @Test func keepaliveRunsFastOnlyWhenNeeded() async throws {
        let macID = UUID(), key = PairingPayload.generateKey()
        let q = DispatchQueue(label: "test.keepalive")
        let server = GlasspadServer(macID: macID, macName: "Test Mac", advertise: false, delegateQueue: q) { _ in key }
        try server.start()
        defer { server.stop() }
        #expect(await waitUntil { server.ports != nil })
        let port = try #require(server.ports).tcp
        let client = GlasspadClient(phoneID: "phone-ka", phoneName: "Phone", pairing: PairingPayload(macID: macID, macName: "Test Mac", pairKey: key), delegateQueue: q)
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected })
        let idleStart = client.datagramsSent
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(client.datagramsSent - idleStart == 0)

        client.heartbeatIdleTimeout = 1
        client.heartbeatsEnabled = true
        client.send(frame: TouchFrame(seq: 0, timestamp: ProcessInfo.processInfo.systemUptime, touches: [], surface: CGSize(width: 300, height: 600)))
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(client.datagramsSent - idleStart >= 8)       // about 20 in 0.4 s at 50 Hz
        // Past the idle window the heartbeats stop.
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let after = client.datagramsSent
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(client.datagramsSent - after == 0)
        #expect(client.state.isConnected)
    }
}
#endif
