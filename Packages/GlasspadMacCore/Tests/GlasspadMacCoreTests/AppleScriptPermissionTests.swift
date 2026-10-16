import Foundation
import Testing
@testable import GlasspadMacCore

/// The permission check must never make its caller wait: macOS can leave
/// `AEDeterminePermissionToAutomateTarget` unanswered, and on the main thread that froze the
/// menu bar icon.
struct AppleScriptPermissionTests {
    @Test func aCheckThatNeverAnswersDoesNotBlock() {
        let gate = DispatchSemaphore(value: 0)
        let runner = LiveAppleScriptRunner(check: { _ in gate.wait(); return true })
        let start = Date()
        #expect(runner.permission(for: "com.spotify.client") == nil)
        #expect(runner.permission(for: "com.spotify.client") == nil)
        #expect(Date().timeIntervalSince(start) < 0.2)
        gate.signal()
    }

    @Test func theAnswerArrivesOnALaterCall() async throws {
        let runner = LiveAppleScriptRunner(check: { id in id == "com.apple.Music" })
        _ = runner.permission(for: "com.apple.Music")
        _ = runner.permission(for: "com.spotify.client")
        for _ in 0 ..< 50 where runner.permission(for: "com.apple.Music") != true || runner.permission(for: "com.spotify.client") != false {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(runner.permission(for: "com.apple.Music") == true)
        #expect(runner.permission(for: "com.spotify.client") == false)
    }
}
