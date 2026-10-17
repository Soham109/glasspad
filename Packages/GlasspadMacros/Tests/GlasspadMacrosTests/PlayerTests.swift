import Foundation
import CoreGraphics
import Testing
@testable import GlasspadMacros

@Suite("Player")
struct PlayerTests {
    @Test func runsStepsInOrderAcrossEveryService() async throws {
        let h = Harness()
        let file = tempDir().appendingPathComponent("doc.txt")
        try Data("x".utf8).write(to: file)
        let macro = Macro(name: "All", steps: [
            .openApp(bundleID: "com.apple.Safari"),
            .keystroke(KeyCombo("l", [.command])),
            .typeText("example.com"),
            .keystroke(KeyCombo(.special(.returnKey))),
            .click(button: .left, at: .screen(10, 20), count: 2, modifiers: [.command]),
            .moveMouse(to: .screen(5, 6)),
            .drag(button: .left, from: .screen(1, 1), to: .screen(9, 9), durationMs: 200),
            .scroll(dx: 0, dy: -40),
            .openURL("https://glasspad.app"),
            .openFile(path: file.path),
            .runShortcut(nameOrID: "Make GIF", input: "in"),
            .setClipboard("clip"),
            .notify(title: "Hi", body: "there"),
            .runAppleScript(source: "beep"),
            .runShell(command: "true", timeoutMs: 1000),
        ], allowScripts: true)
        let result = await h.player.run(macro)
        #expect(result.outcome == .completed)
        #expect(result.stepsCompleted == 15)
        #expect(h.log.all == [
            "openApp com.apple.Safari", "press ⌘L", "type example.com", "press ↩",
            "click left 10,20 x2⌘", "move 5,6", "drag 1,1->9,9 200ms", "scroll 0,-40",
            "open https://glasspad.app", "open \(URL(fileURLWithPath: file.path).absoluteString)",
            "shortcut Make GIF input=in", "clipboard clip", "notify Hi: there", "applescript beep", "shell true",
        ])
        #expect(result.outputs == [StepOutput(path: [10], text: "shortcut-output"),
                                   StepOutput(path: [13], text: "as-out"), StepOutput(path: [14], text: "sh-out")])
        #expect(result.userInputGuardActive)
        #expect(h.monitor.started == 1 && h.monitor.stopped == 1)
    }

    @Test func waitsScaleWithSpeed() async {
        let h = Harness()
        let macro = Macro(name: "W", steps: [.wait(ms: 1000), .keystroke(KeyCombo("a")), .wait(ms: 300),
                                             .drag(button: .left, from: .screen(0, 0), to: .screen(1, 1), durationMs: 400)])
        _ = await h.player.run(macro, options: PlaybackOptions(speed: 2))
        #expect(h.clock.recordedSleeps == [500, 150])
        #expect(h.log.all.last == "drag 0,0->1,1 200ms")

        let slow = Harness()
        _ = await slow.player.run(macro, options: PlaybackOptions(speed: 0.5))
        #expect(slow.clock.recordedSleeps == [2000, 600])
    }

    @Test func nestedRepeatsExpandInOrderWithProgress() async {
        let h = Harness()
        let macro = Macro(name: "R", steps: [
            .keystroke(KeyCombo("a")),
            .repeatBlock(count: 2, steps: [
                .keystroke(KeyCombo("b")),
                .repeatBlock(count: 3, steps: [.keystroke(KeyCombo("c"))]),
            ]),
            .keystroke(KeyCombo("d")),
        ])
        let progress = LockedBox<[MacroProgress]>([])
        let result = await h.player.run(macro) { p in progress.update { $0.append(p) } }
        #expect(h.log.all.map { String($0.last!) } == ["A", "B", "C", "C", "C", "B", "C", "C", "C", "D"])
        #expect(result.totalSteps == 10 && result.stepsCompleted == 10)
        let p = progress.get()
        #expect(p.count == 11)
        #expect(p.map(\.completedSteps) == Array(0...10))
        #expect(p.allSatisfy { $0.totalSteps == 10 && $0.macroID == macro.id })
        #expect(p[1].currentPath == [1, 0])
        #expect(p[2].currentPath == [1, 1, 0])
        #expect(p.last!.currentPath.isEmpty && p.last!.fraction == 1)
    }

    @Test func cancellingTheTaskStopsMidWait() async {
        let h = Harness(clock: ContinuousMacroClock())
        let macro = Macro(name: "C", steps: [.keystroke(KeyCombo("a")), .wait(ms: 30_000), .keystroke(KeyCombo("b"))])
        let started = ContinuousClock.now
        let task = Task { await h.player.run(macro) }
        while h.log.all.isEmpty { await Task.yield() }
        // Into the 30 s wait before cancelling: cancelling right after the key press could land
        // before the player moved on to step 1 (it failed that way when run alone).
        try? await Task.sleep(for: .milliseconds(200))
        task.cancel()
        let result = await task.value
        #expect(result.outcome == .cancelled)
        #expect(result.stepsCompleted == 1)
        #expect(result.stoppedAt == [1])
        #expect(h.log.all == ["press A"])
        #expect(ContinuousClock.now - started < .seconds(5))
        #expect(h.monitor.stopped == 1)
    }

    @Test func touchingTheRealMouseStopsPlayback() async {
        let h = Harness()
        h.output.onEvent = { [monitor = h.monitor] s in if s == "press B" { monitor.fire() } }
        let macro = Macro(name: "U", steps: (["a", "b", "c", "d"] as [Character]).map { .keystroke(KeyCombo($0)) })
        let result = await h.player.run(macro)
        #expect(result.outcome == .interruptedByUser)
        #expect(h.log.all == ["press A", "press B"])
        #expect(result.stoppedAt == [1])
    }

    @Test func userInputGuardCanBeTurnedOffOrBeUnavailable() async {
        let h = Harness()
        h.output.onEvent = { [monitor = h.monitor] _ in monitor.fire() }
        let macro = Macro(name: "U", steps: [.keystroke(KeyCombo("a")), .keystroke(KeyCombo("b"))])
        let off = await h.player.run(macro, options: PlaybackOptions(stopOnUserInput: false))
        #expect(off.outcome == .completed)
        #expect(!off.userInputGuardActive)
        #expect(h.monitor.started == 0)

        let h2 = Harness()
        h2.monitor.available = false
        let unguarded = await h2.player.run(macro)
        #expect(unguarded.outcome == .completed)
        #expect(!unguarded.userInputGuardActive)
    }

    @Test func scriptsNeedThePerMacroFlagAndNothingRunsWithoutIt() async {
        let h = Harness()
        let macro = Macro(name: "S", steps: [.keystroke(KeyCombo("a")),
                                             .repeatBlock(count: 2, steps: [.runShell(command: "rm -rf ~", timeoutMs: 10)])])
        let result = await h.player.run(macro)
        #expect(result.outcome == .failed(.scriptsNotAllowed))
        #expect(h.log.all.isEmpty)
        #expect(throws: MacroError.scriptsNotAllowed) { try h.player.dryRun(macro) }
    }

    @Test func invalidStepsFailBeforeAnythingRuns() async {
        let h = Harness()
        let cases: [(MacroStep, [Int])] = [
            (.repeatBlock(count: 0, steps: [.wait(ms: 1)]), [1]),
            (.repeatBlock(count: 2, steps: [.click(button: .left, at: .screen(0, 0), count: 4, modifiers: [])]), [1, 0]),
            (.wait(ms: -5), [1]),
            (.openApp(bundleID: ""), [1]),
            (.typeText(""), [1]),
        ]
        for (bad, path) in cases {
            let result = await h.player.run(Macro(name: "V", steps: [.keystroke(KeyCombo("a")), bad]))
            guard case .failed(.invalidStep(let p, _)) = result.outcome else {
                Issue.record("expected invalid step for \(bad), got \(result.outcome)")
                continue
            }
            #expect(p == path)
        }
        // Runaway nesting is refused too.
        let huge = Macro(name: "H", steps: [.repeatBlock(count: 1000, steps: [.repeatBlock(count: 1000, steps: [.wait(ms: 0)])])])
        guard case .failed(.invalidStep) = await h.player.run(huge).outcome else {
            Issue.record("expected expansion limit"); return
        }
        #expect(h.log.all.isEmpty)
    }

    @Test func dryRunResolvesEverythingAndPostsNothing() throws {
        let h = Harness(windows: FakeWindows(frame: CGRect(x: 100, y: 200, width: 1000, height: 800)))
        let macro = Macro(name: "D", steps: [
            .repeatBlock(count: 2, steps: [.click(button: .left, at: .window(10, 20), count: 1, modifiers: [])]),
            .wait(ms: 400),
            .waitForApp(bundleID: "com.apple.Notes", timeoutMs: 100),
            .openURL("https://a.b"),
            .runShell(command: "ls", timeoutMs: 50),
        ], allowScripts: true)
        let plan = try h.player.dryRun(macro, options: PlaybackOptions(speed: 4))
        #expect(plan == [
            PlannedAction(path: [0, 0], action: .click(.left, at: CGPoint(x: 110, y: 220), count: 1, modifiers: [])),
            PlannedAction(path: [0, 0], action: .click(.left, at: CGPoint(x: 110, y: 220), count: 1, modifiers: [])),
            PlannedAction(path: [1], action: .wait(ms: 100)),
            PlannedAction(path: [2], action: .waitForApp(bundleID: "com.apple.Notes", timeoutMs: 100)),
            PlannedAction(path: [3], action: .open(URL(string: "https://a.b")!)),
            PlannedAction(path: [4], action: .runShell(command: "ls", timeoutMs: 50)),
        ])
        #expect(h.log.all.isEmpty)
        #expect(h.clock.recordedSleeps.isEmpty)
        #expect(h.monitor.started == 0)
    }

    @Test func dryRunReportsBadURLsAndMissingFiles() {
        let h = Harness()
        #expect(throws: MacroError.invalidURL("not a url")) {
            try h.player.dryRun(Macro(name: "x", steps: [.openURL("not a url")]))
        }
        #expect(throws: MacroError.fileNotFound("/nope/missing.txt")) {
            try h.player.dryRun(Macro(name: "x", steps: [.openFile(path: "/nope/missing.txt")]))
        }
    }

    @Test func waitForAppPollsUntilFrontmost() async {
        let h = Harness()
        h.windows.setBundle("com.apple.finder")
        h.clock.onAdvance = { [windows = h.windows] t in if t >= 700 { windows.setBundle("com.apple.Safari") } }
        let macro = Macro(name: "W", steps: [.openApp(bundleID: "com.apple.Safari"),
                                             .waitForApp(bundleID: "com.apple.Safari", timeoutMs: 5000),
                                             .keystroke(KeyCombo("t", [.command]))])
        let result = await h.player.run(macro)
        #expect(result.outcome == .completed)
        #expect(h.clock.nowMs() == 700)
        #expect(h.log.all == ["openApp com.apple.Safari", "press ⌘T"])
    }

    @Test func waitForAppTimesOutAndStops() async {
        let h = Harness()
        let macro = Macro(name: "W", steps: [.waitForApp(bundleID: "com.never", timeoutMs: 1000),
                                             .keystroke(KeyCombo("a"))])
        let result = await h.player.run(macro)
        #expect(result.outcome == .failed(.timedOutWaitingForApp(bundleID: "com.never")))
        #expect(result.stoppedAt == [0])
        #expect(h.clock.nowMs() == 1000)
        #expect(h.log.all.isEmpty)
    }

    @Test func windowRelativePointsResolveAtRunTimeForEveryAnchor() async throws {
        let frame = CGRect(x: 300, y: 100, width: 800, height: 600)
        let windows = FakeWindows(frame: frame)
        let h = Harness(windows: windows)
        let expectations: [(WindowAnchor, CGPoint)] = [
            (.topLeft, CGPoint(x: 310, y: 120)), (.topRight, CGPoint(x: 1110, y: 120)),
            (.bottomLeft, CGPoint(x: 310, y: 720)), (.bottomRight, CGPoint(x: 1110, y: 720)),
            (.center, CGPoint(x: 710, y: 420)),
        ]
        for (anchor, expected) in expectations {
            #expect(try MacroPoint.window(10, 20, from: anchor).resolve(windowFrame: frame) == expected)
        }
        // The frame is read when the step runs, so a window moved by an
        // earlier step is honoured.
        h.output.onEvent = { s in if s == "press ⌘N" { windows.setFrame(CGRect(x: 0, y: 0, width: 500, height: 500)) } }
        let macro = Macro(name: "Rel", steps: [
            .click(button: .left, at: .window(-40, 15, from: .topRight), count: 1, modifiers: []),
            .keystroke(KeyCombo("n", [.command])),
            .click(button: .left, at: .window(-40, 15, from: .topRight), count: 1, modifiers: []),
            .click(button: .left, at: .screen(1, 2), count: 1, modifiers: []),
        ])
        let result = await h.player.run(macro)
        #expect(result.outcome == .completed)
        #expect(h.log.all == ["click left 1060,115 x1", "press ⌘N", "click left 460,15 x1", "click left 1,2 x1"])
        #expect(windows.frameQueries == 2) // screen points never touch the Accessibility API
    }

    @Test func windowRelativeStepFailsWithoutAFrontWindow() async {
        let h = Harness(windows: FakeWindows(frame: nil))
        let result = await h.player.run(Macro(name: "x", steps: [.moveMouse(to: .window(1, 1))]))
        #expect(result.outcome == .failed(.noFrontWindow))
    }
}

@Suite("User input guard filter")
struct UserInputFilterTests {
    @Test func ignoresPlaybackReleasesRepeatsAndJitter() {
        var f = UserInputFilter(movementThreshold: 4)
        let results = [
            f.isUserInput(.keyDown(isRepeat: false), fromPlayback: true),
            f.isUserInput(.keyUp, fromPlayback: false),
            f.isUserInput(.flagsChanged, fromPlayback: false),
            f.isUserInput(.mouseUp, fromPlayback: false),
            f.isUserInput(.keyDown(isRepeat: true), fromPlayback: false),
            f.isUserInput(.mouseMoved(CGPoint(x: 100, y: 100)), fromPlayback: false),
            f.isUserInput(.mouseMoved(CGPoint(x: 102, y: 101)), fromPlayback: false),
            f.isUserInput(.mouseMoved(CGPoint(x: 104, y: 102)), fromPlayback: false),
        ]
        #expect(results == [false, false, false, false, false, false, false, true])
    }

    @Test func realPressesAndScrollsStopAtOnce() {
        var f = UserInputFilter()
        let results = [
            f.isUserInput(.keyDown(isRepeat: false), fromPlayback: false),
            f.isUserInput(.mouseDown, fromPlayback: false),
            f.isUserInput(.scroll, fromPlayback: false),
        ]
        #expect(results == [true, true, true])
    }
}
