import Foundation
import Testing
@testable import GlasspadMacCore

@Suite("Automation probe")
struct AutomationProbeTests {
    /// macOS's permission call can hang. It used to run on the main thread at launch and froze
    /// the whole app (no menu bar icon, no pointer). It must give up instead.
    @Test func hangingPermissionCallTimesOut() async {
        let start = Date()
        let state = await AutomationProbe.current(deniedApps: [], timeout: 0.2) {
            Thread.sleep(forTimeInterval: 30)   // a call that never answers
            return [.granted]
        }
        #expect(state == .notDetermined)
        #expect(Date().timeIntervalSince(start) < 2)
    }

    @Test func answerArrivingInTimeIsUsed() async {
        let state = await AutomationProbe.current(deniedApps: [], timeout: 2) { [.granted, .notInstalled] }
        #expect(state == .granted)
    }

    @Test func refusedAppsStillReportDeniedOnTimeout() async {
        let state = await AutomationProbe.current(deniedApps: ["Spotify"], timeout: 0.1) {
            Thread.sleep(forTimeInterval: 30)
            return []
        }
        #expect(state == .denied)
    }

    /// A stuck permission call used to keep one thread per check, and every phone session
    /// checks again: the live app had three threads parked in it. Checks made while one call
    /// is stuck now wait for that call instead of starting another.
    @Test func stuckProbeIsNotStartedAgain() async {
        let gate = ProbeGate()
        let release = DispatchSemaphore(value: 0)
        let calls = Counter()
        let probe: @Sendable () -> [AutomationProbe.Answer] = {
            calls.add()
            release.wait()
            return [.granted]
        }
        for _ in 0..<3 {
            let state = await AutomationProbe.current(deniedApps: [], timeout: 0.05, gate: gate, probe: probe)
            #expect(state == .notDetermined)
        }
        #expect(gate.runs == 1)
        // The stuck call answers; a check still waiting gets that answer.
        async let waiting = AutomationProbe.current(deniedApps: [], timeout: 5, gate: gate, probe: probe)
        while gate.joins < 4 { try? await Task.sleep(for: .milliseconds(5)) }
        release.signal()
        #expect(await waiting == .granted)
        #expect(gate.runs == 1)
        // Nothing in flight now, so the next check asks macOS again.
        release.signal()
        #expect(await AutomationProbe.current(deniedApps: [], timeout: 5, gate: gate, probe: probe) == .granted)
        #expect(gate.runs == 2)
        #expect(calls.value == 2)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func add() { lock.withLock { n += 1 } }
    var value: Int { lock.withLock { n } }
}
