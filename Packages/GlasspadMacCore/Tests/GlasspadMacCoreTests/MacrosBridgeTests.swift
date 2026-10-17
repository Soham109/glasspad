import AppKit
import CoreGraphics
import Foundation
import GlasspadKit
import GlasspadMacros
import Testing
@testable import GlasspadMacCore

// MARK: - Fakes (nothing here posts, opens, runs or listens for real)

final class NoWindows: FrontmostWindowProviding, @unchecked Sendable {
    func frontmostBundleID() -> String? { "com.apple.Safari" }
    func frontmostWindowFrame() -> CGRect? { CGRect(x: 100, y: 50, width: 800, height: 600) }
}

final class FakeShortcutsRunner: ShortcutsRunning, @unchecked Sendable {
    func list() async throws -> [ShortcutInfo] { [] }
    func run(_ nameOrID: String, input: String?) async throws -> String? { "ran \(nameOrID)" }
}

final class FakeScriptRunner: ScriptRunning, @unchecked Sendable {
    func runAppleScript(_ source: String) async throws -> String? { nil }
    func runShell(_ command: String, timeoutMs: Int) async throws -> String { "shell" }
}

final class FakeClipboardWriter: ClipboardWriting, @unchecked Sendable {
    func setString(_ text: String) {}
}

final class FakeNotify: Notifying, @unchecked Sendable {
    func notify(title: String, body: String) async throws {}
}

/// Sleeps for real only when told to, so one test can hold a macro mid-run.
final class GateClock: MacroClock, @unchecked Sendable {
    private let lock = NSLock()
    private var _blockMs: Double = 0
    var blockMs: Double {
        get { lock.withLock { _blockMs } }
        set { lock.withLock { _blockMs = newValue } }
    }
    func nowMs() -> Double { ProcessInfo.processInfo.systemUptime * 1000 }
    func sleep(ms: Double) async throws {
        let b = blockMs
        if b > 0 { try await Task.sleep(for: .milliseconds(Int(b))) } else { try Task.checkCancellation() }
    }
}

final class FakeRecorderSource: RecordingEventSource, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (RecordedEvent) -> Void)?
    func start(_ handler: @escaping @Sendable (RecordedEvent) -> Void) throws { lock.withLock { self.handler = handler } }
    func stop() { lock.withLock { handler = nil } }
    func emit(_ e: RecordedEvent) { let h = lock.withLock { handler }; h?(e) }
}

final class FakeSecure: SecureInputChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var on = false
    func set(_ v: Bool) { lock.withLock { on = v } }
    func isSecureInputEnabled() -> Bool { lock.withLock { on } }
}

final class FakeObserver: FrontmostAppObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var current: String?
    private var handler: (@Sendable (String?) -> Void)?
    init(_ current: String?) { self.current = current }
    func currentBundleID() -> String? { lock.withLock { current } }
    func start(_ onChange: @escaping @Sendable (String?) -> Void) { lock.withLock { handler = onChange } }
    func stop() { lock.withLock { handler = nil } }
    func activate(_ id: String?) {
        let h = lock.withLock { () -> (@Sendable (String?) -> Void)? in current = id; return handler }
        h?(id)
    }
}

func macroTempDir() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("glasspad-maccore-macros-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

@MainActor
struct MacroHarness {
    let poster = CapturingEventPoster()
    let clock = GateClock()
    let source = FakeRecorderSource()
    let secure = FakeSecure()
    let observer: FakeObserver
    let coordinator: MacroCoordinator
    let dir: URL
    var sent: () -> [MacroMessage]

    init(frontmost: String? = "com.apple.finder", seed: Bool = false, macros: [Macro] = [],
         controls: (any MacControlRunning)? = nil) throws {
        dir = macroTempDir()
        observer = FakeObserver(frontmost)
        let store = MacroStore(directory: dir.appendingPathComponent("macros"))
        for m in macros { try store.save(m) }
        let output = PosterMacroOutput(poster: poster, source: nil, accessibilityGranted: { true },
                                       layout: { .ansi }, pause: { _ in })
        let apps = PosterAppLauncher(poster: poster) { id in
            id == "com.apple.Notes" ? URL(fileURLWithPath: "/System/Applications/Notes.app") : nil
        }
        let env = MacroEnvironment(output: output, windows: NoWindows(), apps: apps, shortcuts: FakeShortcutsRunner(),
                                   scripts: FakeScriptRunner(), clipboard: FakeClipboardWriter(), notifier: FakeNotify(),
                                   clock: clock, inputMonitor: nil, controls: controls)
        let engine = MacroEngine(store: store, profileStore: ProfileStore(file: dir.appendingPathComponent("profiles.json")),
                                 player: MacroPlayer(environment: env),
                                 recorder: MacroRecorder(source: source, secureInput: secure, windows: NoWindows()),
                                 switcher: ProfileSwitcher(observer: observer, ignoredBundleIDs: ["com.soham109.glasspad"]),
                                 hotkeys: nil)
        coordinator = MacroCoordinator(engine: engine)
        let log = SentLog()
        coordinator.send = { log.items.append($0) }
        sent = { log.items }
        coordinator.start(seedStarters: seed)
    }

    final class SentLog { var items: [MacroMessage] = [] }
}

@MainActor
func eventually(_ timeout: TimeInterval = 15, _ cond: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if cond() { return true }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return cond()
}

// MARK: - Output through EventPoster

@Suite @MainActor struct PosterMacroOutputTests {
    func output(_ poster: CapturingEventPoster, granted: Bool = true) -> PosterMacroOutput {
        PosterMacroOutput(poster: poster, source: nil, accessibilityGranted: { granted }, layout: { .ansi }, pause: { _ in })
    }

    func marked(_ p: CapturingEventPoster) -> Bool {
        p.events.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == MacroEventMarker.userData }
    }

    @Test func keystrokeUsesTheLayoutAndModifiers() async throws {
        let p = CapturingEventPoster()
        try await output(p).press(KeyCombo("t", [.command, .shift]))
        #expect(p.events.map(\.type) == [.keyDown, .keyUp])
        #expect(p.events.allSatisfy { $0.getIntegerValueField(.keyboardEventKeycode) == 0x11 })
        #expect(p.events.allSatisfy { $0.flags.contains([.maskCommand, .maskShift]) && !$0.flags.contains(.maskControl) })
        #expect(p.posted.allSatisfy { $0.tap == .cghidEventTap && $0.delay == 0 })
        #expect(marked(p))

        // A layout where "t" sits elsewhere (a made-up map) moves the key code with it.
        let q = CapturingEventPoster()
        let other = PosterMacroOutput(poster: q, source: nil, accessibilityGranted: { true },
                                      layout: { KeyboardLayoutMap(codeToChar: [0x05: "t"]) }, pause: { _ in })
        try await other.press(KeyCombo("t", [.command]))
        #expect(q.events.first?.getIntegerValueField(.keyboardEventKeycode) == 0x05)
    }

    @Test func typingSendsUnicodeChunksAndRealReturnAndTab() async throws {
        let p = CapturingEventPoster()
        try await output(p).type("héllo\nworld\t👋")
        let strings = p.events.filter { $0.type == .keyDown }.map { e -> String in
            let code = e.getIntegerValueField(.keyboardEventKeycode)
            if code == 0x24 { return "<return>" }
            if code == 0x30 { return "<tab>" }
            return KeyboardSynth.unicodeString(of: e)
        }
        #expect(strings == ["héllo", "<return>", "world", "<tab>", "👋"])
        #expect(marked(p))
    }

    @Test func doubleClickCarriesClickStateAndModifiers() async throws {
        let p = CapturingEventPoster()
        try await output(p).click(.left, at: CGPoint(x: 10, y: 20), count: 2, modifiers: [.option])
        #expect(p.events.map(\.type) == [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDown, .leftMouseUp])
        #expect(p.events.dropFirst().map { $0.getIntegerValueField(.mouseEventClickState) } == [1, 1, 2, 2])
        #expect(p.events.dropFirst().allSatisfy { $0.flags.contains(.maskAlternate) })
        #expect(p.events.allSatisfy { $0.location == CGPoint(x: 10, y: 20) })
        #expect(marked(p))

        let r = CapturingEventPoster()
        try await output(r).click(.right, at: .zero, count: 1, modifiers: [])
        #expect(r.events.map(\.type) == [.mouseMoved, .rightMouseDown, .rightMouseUp])
    }

    @Test func dragMovesInStepsAndScrollUsesPixels() async throws {
        let p = CapturingEventPoster()
        try await output(p).drag(.left, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 50), durationMs: 64)
        let types = p.events.map(\.type)
        #expect(types.first == .mouseMoved)
        #expect(types[1] == .leftMouseDown)
        #expect(types.last == .leftMouseUp)
        #expect(types.filter { $0 == .leftMouseDragged }.count == 4)
        #expect(p.events.last?.location == CGPoint(x: 100, y: 50))

        let s = CapturingEventPoster()
        try await output(s).scroll(dx: -3, dy: 40)
        let e = try #require(s.events.first)
        #expect(e.type == .scrollWheel)
        #expect(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 40)
        #expect(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == -3)
        #expect(marked(s))
    }

    @Test func cancelledDragStillReleasesTheButton() async throws {
        let p = CapturingEventPoster()
        let out = PosterMacroOutput(poster: p, source: nil, accessibilityGranted: { true }, layout: { .ansi },
                                    pause: { _ in try await Task.sleep(for: .seconds(5)) })
        let task = Task { try await out.drag(.left, from: .zero, to: CGPoint(x: 50, y: 0), durationMs: 1000) }
        #expect(await eventually { p.events.contains { $0.type == .leftMouseDragged } })
        task.cancel()
        _ = await task.result
        #expect(p.events.last?.type == .leftMouseUp)
    }

    @Test func noAccessibilityMeansNoEvents() async {
        let p = CapturingEventPoster()
        await #expect(throws: MacroError.accessibilityNotGranted) { try await output(p, granted: false).press(KeyCombo("c", [.command])) }
        #expect(p.events.isEmpty)
    }

    @Test func launcherGoesThroughThePoster() async throws {
        let p = CapturingEventPoster()
        let notes = URL(fileURLWithPath: "/System/Applications/Notes.app")
        let apps = PosterAppLauncher(poster: p) { $0 == "com.apple.Notes" ? notes : nil }
        try await apps.openApp(bundleID: "com.apple.Notes")
        try await apps.open(url: URL(string: "https://example.com")!)
        await #expect(throws: MacroError.appNotFound(bundleID: "nope")) { try await apps.openApp(bundleID: "nope") }
        #expect(p.actions == [.openApplication(notes), .openURL(URL(string: "https://example.com")!)])
    }
}

// MARK: - Coordinator: phone messages <-> engine

@Suite(.serialized) @MainActor struct MacroCoordinatorTests {
    static let closeTab = Macro(name: "Close Tab", symbol: "xmark.square", color: "#FF453A",
                                steps: [.keystroke(KeyCombo("w", [.command]))], gestureTriggers: ["fourFingerTap"])
    static let openNotes = Macro(name: "Notes", symbol: "note.text", color: "#FFD60A",
                                 steps: [.openApp(bundleID: "com.apple.Notes"), .typeText("hi")])

    @Test func listMacrosRepliesWithProfileAndEveryMacro() throws {
        let h = try MacroHarness(macros: [Self.closeTab, Self.openNotes])
        h.coordinator.handle(.listMacros)
        guard case .macroList(let active, let all)? = h.sent().last else {
            Issue.record("no macroList: \(h.sent())")
            return
        }
        #expect(Set(all.map(\.name)) == ["Close Tab", "Notes"])
        let close = try #require(all.first { $0.name == "Close Tab" })
        #expect(close.symbol == "xmark.square")
        #expect(close.color == "#FF453A")
        #expect(close.stepCount == 1)
        #expect(active.profileID == nil)            // no profiles: every macro
        #expect(active.macros.count == 2)
        #expect(active.bundleID == "com.apple.finder")
    }

    @Test func runReportsProgressAndFinishAndPostsMarkedEvents() async throws {
        let h = try MacroHarness(macros: [Self.openNotes])
        h.coordinator.handle(.run(macroID: Self.openNotes.id))
        #expect(await eventually { h.sent().contains { if case .runFinished = $0 { true } else { false } } })
        let progress = h.sent().compactMap { m -> GlasspadKit.MacroProgress? in if case .progress(let p) = m { p } else { nil } }
        #expect(progress.map(\.completedSteps) == [0, 1, 2])
        #expect(progress.allSatisfy { $0.totalSteps == 2 && $0.macroID == Self.openNotes.id })
        #expect(h.sent().last == .runFinished(macroID: Self.openNotes.id, outcome: .completed, message: nil, outputs: []))
        #expect(h.poster.actions == [.openApplication(URL(fileURLWithPath: "/System/Applications/Notes.app"))])
        #expect(KeyboardSynth.unicodeString(of: try #require(h.poster.events.first)) == "hi")
        #expect(h.poster.events.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == MacroEventMarker.userData })
        #expect(h.coordinator.runningMacroID == nil)
    }

    @Test func unknownMacroAndBusyAreReported() async throws {
        let h = try MacroHarness(macros: [Self.closeTab])
        let ghost = UUID()
        h.coordinator.handle(.run(macroID: ghost))
        #expect(await eventually { h.sent().contains { if case .runFinished(ghost, .failed, _, _) = $0 { true } else { false } } })

        // Hold a macro mid-wait, then ask for another: refused, then cancel the first.
        let slow = Macro(name: "Slow", steps: [.wait(ms: 5000), .keystroke(KeyCombo("a"))])
        try h.coordinator.save(slow)
        h.clock.blockMs = 5000
        h.coordinator.handle(.run(macroID: slow.id))
        #expect(await eventually { h.coordinator.engine.runningMacroID == slow.id })
        h.coordinator.handle(.run(macroID: Self.closeTab.id))
        #expect(await eventually {
            h.sent().contains { if case .runFinished(Self.closeTab.id, .failed, let msg?, _) = $0 { msg.contains("Another macro") } else { false } }
        })
        h.coordinator.handle(.cancelRun)
        #expect(await eventually { h.sent().contains { if case .runFinished(slow.id, .cancelled, _, _) = $0 { true } else { false } } })
        #expect(!h.poster.events.contains { $0.type == .keyDown })
    }

    @Test func phoneGestureRunsTheBoundMacro() async throws {
        let h = try MacroHarness(macros: [Self.closeTab])
        h.coordinator.handle(.gesture(name: "twoFingerDoubleTap"))      // unbound: nothing happens
        h.coordinator.handle(.gesture(name: "fourFingerTap"))
        #expect(await eventually { h.sent().contains { if case .runFinished(Self.closeTab.id, .completed, _, _) = $0 { true } else { false } } })
        let keys = h.poster.events.filter { $0.type == .keyDown }
        #expect(keys.count == 1)
        #expect(keys.first?.getIntegerValueField(.keyboardEventKeycode) == 0x0D)   // W
        #expect(keys.first?.flags.contains(.maskCommand) == true)
    }

    @Test func frontmostAppChangePushesTheActiveProfile() async throws {
        let h = try MacroHarness(frontmost: "com.apple.finder", seed: true)
        h.observer.activate("com.apple.Safari")
        #expect(await eventually {
            if case .activeProfileChanged(let p)? = h.sent().last { p.name == "Safari" && !p.macros.isEmpty } else { false }
        })
        #expect(h.coordinator.activeProfile.bundleID == "com.apple.Safari")
        // Glasspad's own menu never swaps the buttons.
        let count = h.sent().count
        h.observer.activate("com.soham109.glasspad")
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(h.sent().count == count)
        // A new phone session gets the current profile at once.
        h.coordinator.sessionStarted()
        if case .activeProfileChanged(let p)? = h.sent().last { #expect(p.name == "Safari") } else { Issue.record("no profile on session start") }
    }

    @Test func recordingFromThePhoneSavesAMacro() async throws {
        let h = try MacroHarness(macros: [])
        h.coordinator.handle(.recordStart(windowRelative: false, keepTiming: false))
        #expect(h.sent().last == .recordingState(isRecording: true))
        #expect(h.coordinator.isRecording)
        h.source.emit(RecordedEvent(time: 1, kind: .keyDown(keyCode: 0x04, characters: "h", modifiers: [], isRepeat: false)))
        h.source.emit(RecordedEvent(time: 1.1, kind: .keyDown(keyCode: 0x22, characters: "i", modifiers: [], isRepeat: false)))
        h.source.emit(RecordedEvent(time: 1.5, kind: .keyDown(keyCode: 0x0D, characters: "w", modifiers: [.command], isRepeat: false)))
        h.coordinator.handle(.recordStop)
        guard case .recordingFinished(let summary, let dropped)? = h.sent().dropLast().last else {
            Issue.record("no recordingFinished: \(h.sent())")
            return
        }
        #expect(h.sent().last == .recordingState(isRecording: false))
        #expect(summary.name == "Recording 1")
        #expect(summary.stepCount == 2)
        #expect(dropped == 0)
        let saved = try #require(h.coordinator.macro(summary.id))
        // Characters come from the event; the shortcut's key from the active layout (US or not).
        #expect(saved.steps.first == .typeText("hi"))
        if case .keystroke(let combo)? = saved.steps.last { #expect(combo.modifiers == [.command]) } else { Issue.record("\(saved.steps)") }
        #expect(saved.origin == .recorded)
        #expect(h.coordinator.lastRecordedID == summary.id)
        #expect(h.coordinator.macros.count == 1)
        #expect(h.coordinator.nextRecordingName() == "Recording 2")
    }

    @Test func recordingRefusalsReachThePhone() throws {
        let h = try MacroHarness(macros: [])
        h.secure.set(true)
        h.coordinator.handle(.recordStart(windowRelative: true, keepTiming: true))
        guard case .recordingFailed(let msg)? = h.sent().dropLast().last else {
            Issue.record("no recordingFailed: \(h.sent())")
            return
        }
        #expect(msg.contains("password"))
        #expect(h.sent().last == .recordingState(isRecording: false))
        #expect(!h.coordinator.isRecording)

        h.secure.set(false)
        h.coordinator.handle(.recordStart(windowRelative: false, keepTiming: true))
        h.coordinator.handle(.recordStop)                   // nothing captured: not saved
        #expect(h.sent().contains(.recordingFailed(message: "Nothing was recorded.")))
        #expect(h.coordinator.macros.isEmpty)
        h.coordinator.handle(.recordStop)                   // not recording any more
        #expect(h.sent().contains(.recordingFailed(message: MacroError.notRecording.description)))
    }

    @Test func modeRouterRoutesMacroMessages() throws {
        let h = try MacroHarness(macros: [Self.closeTab])
        let router = ModeRouter(poster: CapturingEventPoster(), macDock: FakeDockHider.make().hider, observeWorkspace: false)
        router.macros = h.coordinator
        router.handle(.modeSelected(.macros))
        if case .macroList(_, let all)? = h.sent().last { #expect(all.map(\.id) == [Self.closeTab.id]) } else { Issue.record("no list") }
        let n = h.sent().count
        router.handle(.macro(.listMacros))
        #expect(h.sent().count == n + 1)
        router.handle(.macro(.recordingState(isRecording: true)))   // Mac -> phone echoes are ignored
        #expect(h.sent().count == n + 1)
    }

    @Test func editingFromSettingsUpdatesThePhone() throws {
        let h = try MacroHarness(macros: [Self.closeTab])
        var edited = Self.closeTab
        edited.name = "Close"
        edited.symbol = "xmark"
        edited.color = "#30D158"
        try h.coordinator.save(edited)
        #expect(h.coordinator.macros.map(\.name) == ["Close"])
        if case .activeProfileChanged(let p)? = h.sent().last {
            #expect(p.macros.first?.name == "Close")
            #expect(p.macros.first?.color == "#30D158")
        } else {
            Issue.record("no push after edit")
        }
        let profile = ContextProfile(name: "Finder", symbol: "folder", bundleIDs: ["com.apple.finder"], macroIDs: [edited.id])
        try h.coordinator.save(profiles: [profile])
        #expect(h.coordinator.activeProfile.profileID == profile.id)
        try h.coordinator.delete(edited.id)
        #expect(h.coordinator.macros.isEmpty)
        #expect(h.coordinator.profiles.first?.macroIDs.isEmpty == true)
    }
}
