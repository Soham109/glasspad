import Foundation
import GlasspadKit
import Testing
@testable import GlasspadMacCore

@Suite("Pairing flow and Mac status")
struct PairingFlowTests {
    let url = URL(string: "glasspad://pair?test=1")!
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func codeWaitsThenExpiresOnce() {
        var flow = PairingFlow()
        #expect(flow.phase == .idle)
        flow.begin(url: url, now: t0)
        #expect(flow.phase.url == url)
        #expect(flow.remaining(now: t0) == PairingFlow.codeLifetime)
        let r1 = flow.tick(now: t0.addingTimeInterval(PairingFlow.codeLifetime - 1))
        #expect(!r1)
        #expect(flow.phase.url == url)
        let r2 = flow.tick(now: t0.addingTimeInterval(PairingFlow.codeLifetime))
        #expect(r2)
        #expect(flow.phase == .expired)
        #expect(flow.phase.url == nil)
        #expect(flow.remaining(now: t0) == nil)
        // Only once, so the key is disarmed once.
        let r3 = flow.tick(now: t0.addingTimeInterval(PairingFlow.codeLifetime + 10))
        #expect(!r3)
    }

    @Test func newCodeAfterExpiryStartsTheClockAgain() {
        var flow = PairingFlow()
        flow.begin(url: url, now: t0)
        _ = flow.tick(now: t0.addingTimeInterval(PairingFlow.codeLifetime))
        let later = t0.addingTimeInterval(1000)
        flow.begin(url: url, now: later)
        let r4 = flow.tick(now: later.addingTimeInterval(10))
        #expect(!r4)
        #expect(flow.phase.url == url)
    }

    @Test func successAndFailureEndTheCode() {
        var flow = PairingFlow()
        flow.begin(url: url, now: t0)
        flow.completed(phoneName: "Soham's iPhone")
        #expect(flow.phase == .paired(phoneName: "Soham's iPhone"))
        #expect(flow.phase.url == nil)
        let r5 = flow.tick(now: t0.addingTimeInterval(PairingFlow.codeLifetime * 2))
        #expect(!r5)
        flow.reset()
        #expect(flow.phase == .idle)
        #expect(!flow.phase.isActive)

        flow.begin(url: url, now: t0)
        flow.failed("No Keychain")
        #expect(flow.phase == .failed(message: "No Keychain"))
        #expect(flow.phase.isActive)
    }

    @Test func statusIsSentOnEverySessionAndOnlyOnChange() {
        var r = MacStatusReporter()
        let off = MacStatus(accessibilityTrusted: false, automationMedia: .notDetermined, macName: "Mac")
        let on = MacStatus(accessibilityTrusted: true, automationMedia: .notDetermined, macName: "Mac")
        let r6 = r.update(off, newSession: true)
        #expect(r6 == off)
        let r7 = r.update(off)
        #expect(r7 == nil)
        let r8 = r.update(on)
        #expect(r8 == on)
        let r9 = r.update(on)
        #expect(r9 == nil)
        // A reconnecting phone gets it again even though nothing changed.
        let r10 = r.update(on, newSession: true)
        #expect(r10 == on)
        r.sessionEnded()
        #expect(r.lastSent == nil)
        let r11 = r.update(on)
        #expect(r11 == on)
    }

    @Test func automationAnswersCombine() {
        typealias A = AutomationProbe.Answer
        #expect(AutomationProbe.combine([A.granted, .notRunning]) == .granted)
        #expect(AutomationProbe.combine([A.granted, .denied]) == .denied)
        #expect(AutomationProbe.combine([A.granted], deniedApps: ["Spotify"]) == .denied)
        #expect(AutomationProbe.combine([A.notRunning, .notDetermined]) == .notDetermined)
        #expect(AutomationProbe.combine([A.notRunning, .notInstalled]) == .notDetermined)
        #expect(AutomationProbe.combine([A.notInstalled, .notInstalled]) == .notNeeded)
    }

    /// Accessibility turned off (or back on) while running is noticed on the next poll, and the
    /// phone gets a new status for it (docs/review/reliability.md item 5).
    @Test func accessibilityRevokedWhileRunningIsReported() {
        final class Flag: @unchecked Sendable { var on = true }
        let flag = Flag()
        var monitor = AccessibilityMonitor { flag.on }
        var reporter = MacStatusReporter()
        #expect(monitor.trusted)
        let first = reporter.update(MacStatus(accessibilityTrusted: monitor.trusted), newSession: true)
        #expect(first?.accessibilityTrusted == true)

        let unchanged = monitor.poll()
        #expect(unchanged == nil)
        let quiet = reporter.update(MacStatus(accessibilityTrusted: monitor.trusted))
        #expect(quiet == nil)

        flag.on = false
        let off = monitor.poll()
        #expect(off == false)
        #expect(!monitor.trusted)
        let sentOff = reporter.update(MacStatus(accessibilityTrusted: monitor.trusted))
        #expect(sentOff == MacStatus(accessibilityTrusted: false))

        flag.on = true
        let on = monitor.poll()
        #expect(on == true)
        let sentOn = reporter.update(MacStatus(accessibilityTrusted: monitor.trusted))
        #expect(sentOn == MacStatus(accessibilityTrusted: true))
    }

    /// The controller reads trust through the injected checker, not the real permission.
    @MainActor @Test func controllerUsesTheInjectedTrustCheck() {
        final class Flag: @unchecked Sendable { var on = false }
        let flag = Flag()
        let c = GlasspadController(pairing: PairingStore(store: InMemorySecretStore()), macName: "Test Mac",
                                   accessibilityCheck: { flag.on })
        #expect(!c.accessibilityTrusted)
        #expect(!c.macStatus.accessibilityTrusted)
        flag.on = true
        c.refreshAccessibility()
        #expect(c.accessibilityTrusted)
        flag.on = false
        c.refreshAccessibility()
        #expect(!c.accessibilityTrusted)
        #expect(c.macStatus == MacStatus(accessibilityTrusted: false, automationMedia: c.automation, macName: "Test Mac"))
    }
}
