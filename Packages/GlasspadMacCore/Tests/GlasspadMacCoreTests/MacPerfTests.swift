import AppKit
import Foundation
import GlasspadKit
import Testing
@testable import GlasspadMacCore

/// Memory, disk and main thread costs of the menu bar app staying small.
@Suite @MainActor struct MacPerfTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("glasspad-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Icons kept in memory stay bounded (a long session of searches used to keep every one),
    /// and go when the phone leaves; the disk copy serves them again without drawing.
    @Test func dockIconMemoryIsBoundedAndFreedAfterTheSession() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let ws = FakeWorkspace()
        let dock = DockMode(workspace: ws, cacheDirectory: dir)
        let url = URL(fileURLWithPath: "/Applications/Test.app")
        let count = DockMode.memoryIconLimit + 12
        for i in 0..<count { #expect(dock.iconPNG(key: "app\(i)@1-384", url: url) != nil) }
        #expect(dock.memoryIconCount == DockMode.memoryIconLimit)
        #expect(ws.iconRenders == count)
        dock.resetSession()
        #expect(dock.memoryIconCount == 0)
        // From disk, not drawn again.
        #expect(dock.iconPNG(key: "app0@1-384", url: url) != nil)
        #expect(ws.iconRenders == count)
    }

    /// An app update gives its icon a new key; the old version's file goes, other apps' stay.
    @Test func olderIconOfAnUpdatedAppIsRemoved() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let names = ["com.a@1-384.png", "com.a@2-384.png", "com.a.helper@1-384.png", "com.b@1-384.png"]
        for name in names { try Data([1]).write(to: dir.appendingPathComponent(name)) }
        DockMode.removeOlderIcons(of: "com.a@2-384", in: dir)
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(left == ["com.a.helper@1-384.png", "com.a@2-384.png", "com.b@1-384.png"])
    }

    /// Hiding or showing the Dock restarts it off the main thread (a process launch and wait);
    /// quitting is told once the restart is done, still without waiting on the main thread.
    @Test func dockRestartRunsOffTheMainThreadAndQuitHearsWhenItIsDone() async throws {
        let own = UserDefaults(suiteName: "glasspad-tests-\(UUID().uuidString)")!
        let dock = FakeDefaults()
        let runner = ThreadRecordingRunner()
        let queue = DispatchQueue(label: "test.dock-restart")
        let hider = MacDockHider(dock: dock, own: own, runner: runner, flushOwn: {},
                                 restartQueue: { queue.async(execute: $0) })
        hider.setManual(true)
        // The settings are written before the restart is queued.
        #expect(dock.values[MacDockHider.domain]?["autohide-delay"] as? Double == MacDockHider.hiddenDelay)
        queue.sync {}
        #expect(runner.calls == 1)
        #expect(runner.ranOnMain == false)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            hider.restoreBeforeQuit { c.resume() }
        }
        // Done by the time quitting hears back, and off the main thread too.
        #expect(runner.calls == 2)
        #expect(runner.ranOnMain == false)
        #expect(!hider.isHidden)
        // Nothing hidden: quitting goes ahead at once, with no restart.
        var answered = false
        hider.restoreBeforeQuit { answered = true }
        #expect(answered && runner.calls == 2)
    }
}

private final class ThreadRecordingRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    private var _ranOnMain = false
    var calls: Int { lock.withLock { _calls } }
    var ranOnMain: Bool { lock.withLock { _ranOnMain } }
    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        lock.withLock {
            _calls += 1
            if Thread.isMainThread { _ranOnMain = true }
        }
        return (0, "")
    }
}
