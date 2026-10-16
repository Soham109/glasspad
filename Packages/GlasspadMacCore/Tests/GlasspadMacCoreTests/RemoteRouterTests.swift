import Foundation
import Testing
@testable import GlasspadKit
@testable import GlasspadMacCore

/// The Remote screen on the phone: media states, the frontmost app, and one-tap Mac controls.
@Suite @MainActor struct RemoteRouterTests {
    private func router() -> (ModeRouter, FakeDeckEnvironment, () -> [ModeMessage]) {
        let poster = CapturingEventPoster()
        let keys = KeysMode(poster: poster, source: nil)
        let env = FakeDeckEnvironment()
        let r = ModeRouter(keys: keys, dock: DockMode(workspace: FakeWorkspace(), cacheDirectory: nil), media: MediaMode(poster: poster),
                           deck: DeckMode(env: env, url: tempURL("deck.json")), clipboard: ClipboardMode(),
                           present: PresentMode(keys: keys), macDock: FakeDockHider.make().hider)
        r.disconnectGrace = 0
        var sent: [ModeMessage] = []
        r.send = { sent.append($0) }
        return (r, env, { sent })
    }

    @Test func remoteGetsTheFrontmostAppAndItsChanges() {
        let (r, _, sent) = router()
        r.handle(.modeSelected(.remote))
        #expect(sent().contains { if case .frontmostApp = $0 { true } else { false } })
        r.workspaceChanged(activated: "com.apple.TV", name: "TV", url: nil)
        #expect(sent().last == .frontmostApp(bundleID: "com.apple.TV"))
        r.handle(.modeSelected(.trackpad))
        let count = sent().count
        r.workspaceChanged(activated: "com.apple.Safari", name: "Safari", url: nil)
        #expect(sent().count == count)
        r.appWillTerminate()
    }

    @Test func remoteRunsOneTapControlsAndRefusesTheRest() async throws {
        let (r, env, sent) = router()
        let id = UUID()
        r.handle(.remoteSystem(id: id, action: .sleepDisplay))
        for _ in 0..<50 where !sent().contains(where: { if case .deckResult = $0 { true } else { false } }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(env.runs.last?.0 == "/usr/bin/pmset" && env.runs.last?.1 == ["displaysleepnow"])
        #expect(sent().contains(.deckResult(id: id, ok: true, message: nil)))
        let risky = UUID()
        let runs = env.runs.count
        r.handle(.remoteSystem(id: risky, action: .sleepMac))
        #expect(sent().contains { if case .deckResult(risky, false, _) = $0 { true } else { false } })
        #expect(env.runs.count == runs)
        r.appWillTerminate()
    }
}
