import Foundation
import Network
import Testing
@testable import GlasspadKit

#if os(macOS)
/// What the link costs the radio, counted on a real loopback session: the numbers behind the
/// phone's energy model . Each state is measured over a second.
@Suite("Radio budget", .serialized)
struct RadioBudgetTests {
    @Test func packetsPerSecondInEachState() async throws {
        let macID = UUID(), key = PairingPayload.generateKey()
        let q = DispatchQueue(label: "test.radio")
        let server = GlasspadServer(macID: macID, macName: "Test Mac", advertise: false, delegateQueue: q) { _ in key }
        try server.start()
        defer { server.stop() }
        #expect(await waitUntil { server.ports != nil })
        let port = try #require(server.ports).tcp
        let client = GlasspadClient(phoneID: "phone-radio", phoneName: "Phone",
                                    pairing: PairingPayload(macID: macID, macName: "Test Mac", pairKey: key), delegateQueue: q)
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected })

        func rate(_ seconds: Double = 1) async throws -> Double {
            let start = client.datagramsSent
            try await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
            return Double(client.datagramsSent - start) / seconds
        }

        // Off the trackpad, connected: no datagrams (only the Mac's 1 s ping and the answer).
        let off = try await rate()
        #expect(off == 0)

        // Trackpad showing, recently touched: heartbeats at 50 Hz.
        client.heartbeatIdleTimeout = 2
        client.heartbeatsEnabled = true
        let on = try await rate()
        // The ceiling is the promise (never more than 50 Hz); the floor is loose because a busy
        // machine (CI) delays timers, which only ever lowers the rate.
        #expect(on >= 20 && on <= 52)

        // A finger resting: snapshot resends at the same 50 Hz (never more).
        let t = Touch(id: 1, phase: .began, x: 150, y: 300)
        client.send(frame: TouchFrame(seq: 0, timestamp: ProcessInfo.processInfo.systemUptime, touches: [t], surface: CGSize(width: 300, height: 600)))
        let resting = try await rate()
        #expect(resting >= 20 && resting <= 53)
        var lifted = t
        lifted.phase = .ended
        client.send(frame: TouchFrame(seq: 0, timestamp: ProcessInfo.processInfo.systemUptime, touches: [lifted], surface: CGSize(width: 300, height: 600)))

        // Past the idle timeout: silent again, though the trackpad still shows.
        try await Task.sleep(nanoseconds: 2_200_000_000)
        let idle = try await rate()
        #expect(idle == 0)
        #expect(client.state.isConnected)
        print("radio budget: off trackpad \(off)/s, heartbeats \(on)/s, resting finger \(resting)/s, idle \(idle)/s")
    }
}
#endif
