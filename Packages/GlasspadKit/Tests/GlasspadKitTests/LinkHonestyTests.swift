import Foundation
import Testing
@testable import GlasspadKit

/// Taps held through a reconnect, the Mac saying why it left, and the battery experiment.
@Suite struct LinkHonestyTests {
    // MARK: Which taps wait

    @Test func onlyOneShotTapsAreHeld() {
        let id = UUID()
        let held: [ModeMessage] = [
            .deckRun(id: id), .deckRunConfirmed(id: id), .macro(.run(macroID: id)), .mediaCommand(.nextTrack),
            .presentNext, .presentPrevious, .remoteSystem(id: id, action: .sleepDisplay), .dockOpen(bundleID: "com.apple.Safari"),
        ]
        for m in held { #expect(TapHold.holds(m), "\(m)") }
        let live: [ModeMessage] = [
            .keysText("a"), .presentLaser(on: true), .presentLaserPosition(x: 0.5, y: 0.5), .mediaSetVolume(0.4),
            .modeSelected(.media), .mediaRequest, .deckRequest, .macro(.listMacros), .macro(.cancelRun),
        ]
        for m in live { #expect(!TapHold.holds(m), "\(m)") }
    }

    @Test func tapsWaitOnlyForALinkThatIsComingBack() {
        #expect(TapHold.mayWait(macSelected: true, inFront: true, linkGivenUp: false, knownAbsent: false, downFor: 1))
        #expect(!TapHold.mayWait(macSelected: false, inFront: true, linkGivenUp: false, knownAbsent: false, downFor: 1))
        #expect(!TapHold.mayWait(macSelected: true, inFront: false, linkGivenUp: false, knownAbsent: false, downFor: 1))
        #expect(!TapHold.mayWait(macSelected: true, inFront: true, linkGivenUp: true, knownAbsent: false, downFor: 1))
        #expect(!TapHold.mayWait(macSelected: true, inFront: true, linkGivenUp: false, knownAbsent: true, downFor: 1))
        #expect(!TapHold.mayWait(macSelected: true, inFront: true, linkGivenUp: false, knownAbsent: false, downFor: 5))
    }

    // MARK: Outbox

    @Test func drainSendsInOrderAndEmpties() {
        var box = TapOutbox<Int>()
        box.hold(1, at: 10)
        box.hold(2, at: 10.5)
        box.hold(3, at: 11)
        let out = box.drain(at: 11.2)
        #expect(out.send == [1, 2, 3])
        #expect(out.expired.isEmpty)
        #expect(box.isEmpty)
        // Each tap goes out once: a second drain has nothing.
        let again = box.drain(at: 11.3)
        #expect(again.send.isEmpty && again.expired.isEmpty)
    }

    @Test func aTapOlderThanThreeSecondsExpiresAndIsNeverSent() {
        var box = TapOutbox<Int>()
        box.hold(1, at: 0)
        box.hold(2, at: 2)
        #expect(box.nextExpiry == 3)
        let out = box.drain(at: 3.5)
        #expect(out.send == [2])
        #expect(out.expired == [1])

        box.hold(3, at: 10)
        box.hold(4, at: 12)
        #expect(box.expire(at: 12.9).isEmpty)
        #expect(box.expire(at: 13) == [3])
        #expect(box.items == [4])
        #expect(box.nextExpiry == 15)
    }

    @Test func theNinthTapPushesTheFirstOut() {
        var box = TapOutbox<Int>()
        for i in 1...8 { #expect(box.hold(i, at: 0).isEmpty) }
        #expect(box.hold(9, at: 0.1) == [1])
        #expect(box.count == 8)
        #expect(box.drain(at: 0.2).send == Array(2...9))
    }

    @Test func removeAllEmpties() {
        var box = TapOutbox<Int>()
        box.hold(1, at: 0)
        box.hold(2, at: 0)
        #expect(box.removeAll() == [1, 2])
        #expect(box.isEmpty && box.nextExpiry == nil)
    }

    // MARK: MacStatus.screenLocked

    @Test func screenLockedRoundTripsAndIsOptional() throws {
        for locked in [true, false, nil] as [Bool?] {
            let s = MacStatus(accessibilityTrusted: true, macName: "MacBook Pro", followsAllPanes: true, screenLocked: locked)
            let back = try JSONDecoder().decode(MacStatus.self, from: JSONEncoder().encode(s))
            #expect(back == s)
        }
        let unset = try JSONEncoder().encode(MacStatus(accessibilityTrusted: true))
        #expect(!String(decoding: unset, as: UTF8.self).contains("screenLocked"))
        // A Mac from before the field: still reads, nothing said about the lock.
        let old = try JSONDecoder().decode(MacStatus.self, from: Data(#"{"accessibilityTrusted":true,"macName":"Mac","followsAllPanes":true}"#.utf8))
        #expect(old.screenLocked == nil && old.macName == "Mac")
        // A value of the wrong type does not drop the message.
        let odd = try JSONDecoder().decode(MacStatus.self, from: Data(#"{"accessibilityTrusted":false,"screenLocked":"yes"}"#.utf8))
        #expect(odd.screenLocked == nil && !odd.accessibilityTrusted)
    }

    @Test func byeReasonsKeepTheirWireStrings() {
        // Older Macs already send "server stopped"; a phone of any age must keep reading it.
        #expect(GlasspadService.stoppedReason == "server stopped")
        #expect(GlasspadService.sleepingReason == "mac going to sleep")
        #expect(GlasspadService.sleepingReason != GlasspadService.replacedReason)
    }

    // MARK: Battery experiment

    @Test func heartbeatRestOnlyShortensTheIdleTimeout() {
        let normal = PowerPolicy()
        #expect(normal.heartbeatIdleTimeout == GlasspadService.heartbeatIdleTimeout)
        #expect(normal.heartbeatIdleTimeout(rest: .standard) == 120)
        #expect(normal.heartbeatIdleTimeout(rest: .thirtySeconds) == 30)
        #expect(normal.heartbeatIdleTimeout(rest: .whenDimmed) == 120)
        let low = PowerPolicy(lowPower: true)
        #expect(low.heartbeatIdleTimeout(rest: .thirtySeconds) == PowerPolicy.lowPowerHeartbeatIdle)
        #expect(low.heartbeatIdleTimeout(rest: .twoMinutes) == PowerPolicy.lowPowerHeartbeatIdle)
        #expect(HeartbeatRest.standard == .twoMinutes)
        #expect(HeartbeatRest.twoMinutes.runsWhileDimmed && HeartbeatRest.thirtySeconds.runsWhileDimmed)
        #expect(!HeartbeatRest.whenDimmed.runsWhileDimmed)
        #expect(HeartbeatRest(rawValue: "dim") == .whenDimmed && HeartbeatRest(rawValue: "30") == .thirtySeconds)
    }

    /// The default changes nothing: the idle timeout the phone gives the client is exactly the
    /// one it gave before the experiment existed, in every power state, and heartbeats keep
    /// running while dimmed.
    @Test func theDefaultRestIsTodaysBehaviour() {
        for heat in [PowerPolicy.Heat.nominal, .fair, .serious, .critical] {
            for low in [false, true] {
                let policy = PowerPolicy(heat: heat, lowPower: low)
                let before: TimeInterval = low ? 10 : 120
                #expect(policy.heartbeatIdleTimeout(rest: .standard) == before)
                #expect(policy.heartbeatIdleTimeout == before)
            }
        }
        #expect(HeartbeatRest.standard.runsWhileDimmed)
    }

    // MARK: First touch after a rest (Mac log)

    @Test func firstTouchAfterARestIsMeasuredAgainstTheFastestFrameAfterIt() throws {
        var probe = RestWakeProbe()
        probe.sessionStarted(at: 100)
        // Heartbeats every 20 ms: no rest.
        for i in 0..<10 { #expect(probe.heartbeat(at: 100 + Double(i) * 0.02) == nil) }
        #expect(probe.touch(at: 100.3, timestamp: 50.3) == nil)
        // 30 s quiet, then a touch at phone time 80.0 that arrives 150 ms late (offset 50.15);
        // the frames after it travel with offset 50.0.
        #expect(probe.touch(at: 130.15, timestamp: 80.0) == nil)
        for i in 1...20 { #expect(probe.touch(at: 130.15 + Double(i) * 0.008, timestamp: 80.15 + Double(i) * 0.008) == nil) }
        // A heartbeat past the 1 s window closes it.
        let closed = probe.heartbeat(at: 131.2)
        let result = try #require(closed)
        #expect(abs(result.quiet - 29.85) < 0.001)
        #expect(abs(result.lateMs - 150) < 0.5)
        #expect(result.frames == 21)
        #expect(result.line.hasPrefix("rest: first touch after 29.9 s quiet came 150 ms late"))
        // Once only.
        #expect(probe.heartbeat(at: 131.3) == nil)
    }

    @Test func aShortPauseIsNotARest() {
        var probe = RestWakeProbe()
        probe.sessionStarted(at: 0)
        #expect(probe.touch(at: 1.5, timestamp: 1) == nil)
        #expect(probe.heartbeat(at: 3) == nil)
        #expect(probe.heartbeat(at: 4.6) == nil)
    }
}

#if os(macOS)
/// The Mac's bye reasons reach the phone as a reason it can show, over the real transport.
@Suite("Link honesty loopback", .serialized)
struct LinkHonestyLoopbackTests {
    let macID = UUID()
    let key = PairingPayload.generateKey()
    let q = DispatchQueue(label: "test.honesty")

    final class Issues: @unchecked Sendable {
        private let lock = NSLock()
        private var _seen: [LinkIssue?] = []
        var seen: [LinkIssue?] { lock.withLock { _seen } }
        func add(_ i: LinkIssue?) { lock.withLock { _seen.append(i) } }
    }

    func rig() async throws -> (GlasspadServer, GlasspadClient, Recorder, Issues, UInt16) {
        let key = self.key
        let server = GlasspadServer(macID: macID, macName: "Test Mac", advertise: false, delegateQueue: q) { _ in key }
        try server.start()
        #expect(await waitUntil { server.ports != nil })
        let port = try #require(server.ports).tcp
        let rec = Recorder()
        let client = GlasspadClient(phoneID: "phone-1", phoneName: "Test Phone",
                                    pairing: PairingPayload(macID: macID, macName: "Test Mac", pairKey: key), delegateQueue: q)
        client.delegate = rec
        let issues = Issues()
        client.onIssueChange = { issues.add($0) }
        client.connect(host: "127.0.0.1", port: port)
        #expect(await waitUntil { client.state.isConnected && server.state.isConnected })
        return (server, client, rec, issues, port)
    }

    @Test func sleepingByeSaysAsleepUntilTheNextConnect() async throws {
        let (server, client, rec, issues, _) = try await rig()
        defer { client.disconnect(); server.stop() }
        server.disconnect(reason: GlasspadService.sleepingReason)
        #expect(await waitUntil { issues.seen.contains(.macAsleep) })
        #expect(rec.messages.contains(.bye(reason: GlasspadService.sleepingReason)))
        // It keeps trying (not a refusal), and connecting again clears the reason.
        #expect(await waitUntil(8) { client.state.isConnected && client.issue == nil })
        #expect(issues.seen.last == .some(nil))
    }

    @Test func stoppedServerSaysGlasspadIsOffAndKeepsLooking() async throws {
        let (server, client, _, issues, _) = try await rig()
        defer { client.disconnect() }
        server.stop()
        #expect(await waitUntil { client.issue == .macTurnedOff })
        #expect(issues.seen.contains(.macTurnedOff))
        #expect(client.state.failure == nil)
        try await Task.sleep(for: .milliseconds(600))
        #expect(client.issue == .macTurnedOff)
        #expect(client.state.failure == nil)
    }

    @Test func replacedStillStopsRetrying() async throws {
        let (server, client, _, _, _) = try await rig()
        defer { client.disconnect(); server.stop() }
        server.disconnect(reason: GlasspadService.replacedReason)
        #expect(await waitUntil { client.state.failure == GlasspadService.replacedFailure })
        #expect(client.issue == nil)
    }
}
#endif
