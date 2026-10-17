import Foundation
import Testing
@testable import GlasspadKit

/// The pieces the Siri and Shortcuts actions build on.
@Suite struct ShortcutsSupportTests {
    @Test func anAnswerAlreadyThereReturnsAtOnce() async {
        let start = ContinuousClock.now
        let value = await awaitAnswer(timeout: .seconds(2)) { 7 }
        #expect(value == 7)
        #expect(ContinuousClock.now - start < .milliseconds(40))
    }

    @MainActor @Test func waitsForALateAnswer() async {
        var reply: String?
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            reply = "Mission Control is open"
        }
        let start = ContinuousClock.now
        let value = await awaitAnswer(timeout: .seconds(20)) { reply }
        #expect(value == "Mission Control is open")
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test func noAnswerGivesUpAtTheDeadline() async {
        let start = ContinuousClock.now
        let value: Int? = await awaitAnswer(timeout: .milliseconds(150)) { nil }
        let waited = ContinuousClock.now - start
        #expect(value == nil)
        #expect(waited >= .milliseconds(150) && waited < .seconds(10))
    }

    @Test func cancellingStopsTheWait() async {
        let start = ContinuousClock.now
        let task = Task { await awaitAnswer(timeout: .seconds(30)) { Int?.none } }
        try? await Task.sleep(for: .milliseconds(60))
        task.cancel()
        let value = await task.value
        #expect(value == nil)
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test func layoutsMatchByNameIgnoringCaseAndAccents() {
        let library = LayoutLibrary(layouts: [
            ScreenLayout(name: "Couch Time", panes: ["remote"]),
            ScreenLayout(name: "Desk", panes: ["trackpad", "actions"]),
            ScreenLayout(name: "Café", panes: ["media"]),
            ScreenLayout(name: "Couch", panes: ["remote", "trackpad"]),
        ])
        #expect(library.layouts(matching: "couch").map(\.name) == ["Couch", "Couch Time"])
        #expect(library.layouts(matching: " DESK ").map(\.name) == ["Desk"])
        #expect(library.layouts(matching: "cafe").map(\.name) == ["Café"])
        #expect(library.layouts(matching: "Studio").isEmpty)
        #expect(library.layouts(matching: "").count == 4)
    }
}
