import AppKit
import Foundation
import GlasspadKit
import Testing
@testable import GlasspadMacCore

/// Sleep and the screen lock, told to the phone. Every notification goes into centers made
/// for the test; the real workspace and distributed centers are never touched.
@Suite(.serialized) @MainActor struct MacPresenceTests {
    final class Bridge: GlasspadLinkDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var _messages: [ControlMessage] = []
        var messages: [ControlMessage] { lock.withLock { _messages } }
        func link(didChangeState state: LinkState) {}
        func link(didReceive message: ControlMessage) { lock.withLock { _messages.append(message) } }
    }

    func eventually(_ timeout: TimeInterval = 5, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if cond() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return cond()
    }

    @Test func willSleepSendsExactlyOneSleepingBye() async throws {
        let workspace = NotificationCenter()
        let presence = MacPresence(workspace: workspace, distributed: NotificationCenter(), initiallyLocked: false)
        let key = PairingPayload.generateKey()
        let macID = UUID()
        let server = GlasspadServer(macID: macID, macName: "Test Mac", advertise: false, delegateQueue: .main) { _ in key }
        try server.start()
        defer { server.stop() }
        #expect(await eventually { server.ports != nil })
        let port = try #require(server.ports).tcp
        let phone = Bridge()
        let client = GlasspadClient(phoneID: "phone-presence", phoneName: "Phone",
                                    pairing: PairingPayload(macID: macID, macName: "Test Mac", pairKey: key))
        client.delegate = phone
        defer { client.disconnect() }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await eventually { client.state == .connected(rttMs: nil) && server.connectedPhone != nil })

        // Wired the way GlasspadController wires it.
        presence.onSleep = { server.disconnect(reason: GlasspadService.sleepingReason) }
        presence.start()
        defer { presence.stop() }
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(await eventually { client.issue == .macAsleep })
        try await Task.sleep(for: .milliseconds(300))
        let byes = phone.messages.filter { $0 == .bye(reason: GlasspadService.sleepingReason) }
        #expect(byes.count == 1)
    }

    @Test func lockAndUnlockFlipScreenLocked() {
        let distributed = NotificationCenter()
        let presence = MacPresence(workspace: NotificationCenter(), distributed: distributed, initiallyLocked: false)
        var changes: [Bool] = []
        presence.onLockChange = { changes.append($0) }
        presence.start()
        distributed.post(name: MacPresence.screenLocked, object: nil)
        #expect(presence.screenLocked)
        // The same news twice is one change.
        distributed.post(name: MacPresence.screenLocked, object: nil)
        distributed.post(name: MacPresence.screenUnlocked, object: nil)
        #expect(!presence.screenLocked)
        #expect(changes == [true, false])
        presence.stop()
        distributed.post(name: MacPresence.screenLocked, object: nil)
        #expect(!presence.screenLocked)
    }

    @Test func controllerReportsTheLock() {
        let distributed = NotificationCenter()
        let presence = MacPresence(workspace: NotificationCenter(), distributed: distributed, initiallyLocked: true)
        let c = GlasspadController(pairing: PairingStore(store: InMemorySecretStore()), macName: "Test Mac",
                                   accessibilityCheck: { true }, presence: presence)
        #expect(c.macStatus.screenLocked == true)
        presence.start()
        defer { presence.stop() }
        distributed.post(name: MacPresence.screenUnlocked, object: nil)
        #expect(c.macStatus.screenLocked == false)
    }
}
