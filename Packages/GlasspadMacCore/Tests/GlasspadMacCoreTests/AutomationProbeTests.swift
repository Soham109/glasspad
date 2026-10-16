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
}
