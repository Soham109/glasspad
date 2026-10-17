import Foundation
import Testing
@testable import GlasspadKit

@Suite struct RequestCoalescerTests {
    @Test func aRepeatWithinHalfASecondIsDropped() {
        let c = CoalescerProbe()
        #expect(c.ok(.mediaRequest, 10))
        #expect(!c.ok(.mediaRequest, 10.2))      // Remote's ask next to Media's
        #expect(c.ok(.mediaRequest, 10.6))       // a later ask is a new one
        // Different requests do not hide each other; the two Dock asks are one.
        #expect(c.ok(.deckRequest, 10.6))
        #expect(c.ok(.macro(.listMacros), 10.6))
        #expect(!c.ok(.macro(.listMacros), 10.7))
        // The Dock list and the icon sync are kept apart: a sync names the icons this phone
        // has, so it is never stood in for by a plain list request (or the other way round).
        #expect(c.ok(.dockSync(iconKeys: []), 11))
        #expect(c.ok(.dockRequest, 11.1))
        #expect(!c.ok(.dockSync(iconKeys: ["a"]), 11.2))
    }

    @Test func commandsAlwaysGoOut() {
        let c = CoalescerProbe()
        for _ in 0..<3 {
            #expect(c.ok(.mediaCommand(.playPause), 1))
            #expect(c.ok(.presentNext, 1))
        }
        #expect(c.ok(.dockOpen(bundleID: "com.apple.Safari"), 1))
        #expect(c.ok(.dockOpen(bundleID: "com.apple.Safari"), 1))
    }

    @Test func aNewScreenOrSessionStartsAfresh() {
        let c = CoalescerProbe()
        #expect(c.ok(.mediaRequest, 1))
        // Media, then Keyboard, then Media again quickly: the Mac stopped now playing for
        // Keyboard, so the second ask must reach it.
        #expect(c.ok(.modeSelected(.keys), 1.1))
        #expect(c.ok(.mediaRequest, 1.2))
        c.coalescer.reset()
        #expect(c.ok(.mediaRequest, 1.3))
    }

    @Test func macStatusSaysWhetherTheMacFollowsEveryPane() throws {
        let new = ControlMessage.macStatus(MacStatus(accessibilityTrusted: true, followsAllPanes: true))
        #expect(String(decoding: try new.jsonData(), as: UTF8.self).contains(#""followsAllPanes":true"#))
        #expect(try ControlMessage.from(jsonData: new.jsonData()) == new)
        // A Mac from before says nothing: the phone keeps asking for the Dock itself.
        let old = try ControlMessage.from(jsonData: Data(#"{"t":"macStatus","status":{"accessibilityTrusted":true}}"#.utf8))
        guard case .macStatus(let status) = old else { Issue.record("not a status"); return }
        #expect(status.followsAllPanes == nil)
    }
}

/// `#expect` cannot call a mutating method on a local; this holds the coalescer.
private final class CoalescerProbe {
    var coalescer = RequestCoalescer()
    func ok(_ message: ModeMessage, _ now: TimeInterval) -> Bool { coalescer.shouldSend(message, now: now) }
}
