import Foundation
import Testing
@testable import GlasspadMacros

@MainActor
@Suite("Engine and triggers")
struct EngineTests {
    @MainActor struct Rig {
        let h = Harness()
        let observer = FakeFrontmostObserver(current: "com.apple.finder")
        let hotkeys = FakeHotkeys()
        let source = FakeRecordingSource()
        let store: MacroStore
        let profiles: ProfileStore
        let engine: MacroEngine

        init() {
            let dir = tempDir()
            store = MacroStore(directory: dir.appendingPathComponent("macros"))
            profiles = ProfileStore(file: dir.appendingPathComponent("profiles.json"))
            engine = MacroEngine(store: store, profileStore: profiles, player: h.player,
                                 recorder: MacroRecorder(source: source, secureInput: FakeSecureInput(), windows: FakeWindows()),
                                 switcher: ProfileSwitcher(observer: observer, ignoredBundleIDs: []),
                                 hotkeys: hotkeys)
        }
    }

    @Test func startSeedsStartersAndPublishesTheActiveProfile() throws {
        let rig = Rig()
        let infos = LockedBox<[ActiveProfileInfo]>([])
        rig.engine.onActiveProfileChanged = { info in infos.update { $0.append(info) } }
        try rig.engine.start()
        #expect(rig.engine.macros.count == StarterLibrary.macros.count)
        #expect(infos.get().last?.name == "Finder")
        #expect(infos.get().last?.macros.first?.name == "Hidden Files")
        rig.observer.activate("com.apple.Safari")
        let safari = try #require(infos.get().last)
        #expect(safari.name == "Safari")
        #expect(safari.bundleID == "com.apple.Safari")
        #expect(safari.macros.map(\.name).prefix(3) == ["Reopen Closed Tab", "Show All Tabs", "Reader"])
    }

    @Test func deckRunReportsProgressAndFinish() async throws {
        let rig = Rig()
        try rig.engine.start(seedStarters: false)
        let m = Macro(name: "Two", steps: [.keystroke(KeyCombo("a")), .keystroke(KeyCombo("b"))])
        try rig.engine.save(m)
        let progress = LockedBox<[Int]>([])
        let finished = LockedBox<[MacroTrigger]>([])
        rig.engine.onProgress = { p, _ in progress.update { $0.append(p.completedSteps) } }
        rig.engine.onRunFinished = { _, trigger, _ in finished.update { $0.append(trigger) } }
        let result = await rig.engine.run(m.id, trigger: .deck)
        #expect(result.outcome == .completed)
        #expect(progress.get() == [0, 1, 2])
        #expect(finished.get() == [.deck])
        #expect(rig.engine.runningMacroID == nil)
        #expect(rig.h.log.all == ["press A", "press B"])
    }

    @Test func onlyOneMacroPlaysAtATimeAndCancelWorks() async throws {
        let rig = Rig()
        try rig.engine.start(seedStarters: false)
        let slow = Macro(name: "Slow", steps: [.keystroke(KeyCombo("a")), .wait(ms: 60_000)])
        try rig.engine.save(slow)
        // The fake clock never really sleeps, so block on a real one here.
        let engine = MacroEngine(store: rig.store, profileStore: rig.profiles,
                                 player: MacroPlayer(environment: MacroEnvironment(
                                    output: rig.h.output, windows: FakeWindows(), apps: FakeApps(log: rig.h.log),
                                    shortcuts: rig.h.shortcuts, scripts: FakeScripts(log: rig.h.log),
                                    clipboard: FakeClipboard(log: rig.h.log), notifier: FakeNotifier(log: rig.h.log),
                                    clock: ContinuousMacroClock(), inputMonitor: nil)),
                                 recorder: MacroRecorder(source: FakeRecordingSource(), secureInput: FakeSecureInput(),
                                                         windows: FakeWindows()),
                                 switcher: ProfileSwitcher(observer: rig.observer, ignoredBundleIDs: []),
                                 hotkeys: nil)
        try engine.start(seedStarters: false)
        let first = Task { await engine.run(slow.id, trigger: .deck) }
        while engine.runningMacroID == nil || rig.h.log.all.isEmpty { await Task.yield() }
        let second = await engine.run(slow.id, trigger: .gesture("x"))
        #expect(second.outcome == .failed(.busy))
        #expect(throws: MacroError.busy) { try engine.startRecording() }
        engine.cancelRun()
        #expect(await first.value.outcome == .cancelled)
        #expect(engine.runningMacroID == nil)
    }

    @Test func gesturesRouteByActiveProfile() async throws {
        let rig = Rig()
        try rig.engine.start(seedStarters: false)
        let inSafari = Macro(name: "Safari tap", steps: [.keystroke(KeyCombo("t", [.command]))], gestureTriggers: ["fourFingerTap"])
        let anywhere = Macro(name: "Global tap", steps: [.keystroke(KeyCombo("x"))], gestureTriggers: ["fourFingerTap"])
        try rig.engine.save(inSafari)
        try rig.engine.save(anywhere)
        try rig.engine.save(profiles: [
            ContextProfile(name: "Everywhere", bundleIDs: [], macroIDs: [anywhere.id], isFallback: true),
            ContextProfile(name: "Safari", bundleIDs: ["com.apple.Safari"], macroIDs: [inSafari.id]),
        ])
        await rig.engine.handleGesture("fourFingerTap")
        rig.observer.activate("com.apple.Safari")
        await rig.engine.handleGesture("fourFingerTap")
        #expect(await rig.engine.handleGesture("unboundGesture") == nil)
        #expect(rig.h.log.all == ["press X", "press ⌘T"])
    }

    @Test func hotkeysRegisterRunAndReportConflicts() async throws {
        let rig = Rig()
        rig.hotkeys.taken = [KeyCombo("q", [.command])]
        try rig.engine.start(seedStarters: false)
        let combo = KeyCombo("m", [.control, .option, .command])
        let a = Macro(name: "A", steps: [.typeText("from hotkey")], hotkey: combo)
        let b = Macro(name: "B", steps: [.typeText("never")], hotkey: combo)
        let c = Macro(name: "C", steps: [.typeText("taken")], hotkey: KeyCombo("q", [.command]))
        try rig.engine.save(a)
        try rig.engine.save(b)
        try rig.engine.save(c)
        #expect(rig.hotkeys.registered == [combo])
        #expect(rig.engine.unregisteredHotkeys == [KeyCombo("q", [.command])])
        #expect(rig.engine.triggerConflicts == [TriggerConflict(kind: .hotkey(combo), macroIDs: [a.id, b.id])])

        let done = LockedBox<MacroTrigger?>(nil)
        rig.engine.onRunFinished = { _, t, _ in done.set(t) }
        rig.hotkeys.press(combo)
        while done.get() == nil { await Task.yield() }
        #expect(done.get() == .hotkey)
        #expect(rig.h.log.all == ["type from hotkey"])
    }

    @Test func deletingAMacroRemovesItsButtons() throws {
        let rig = Rig()
        try rig.engine.start(seedStarters: false)
        let m = Macro(name: "Gone", steps: [.wait(ms: 1)])
        try rig.engine.save(m)
        try rig.engine.save(profiles: [ContextProfile(name: "P", bundleIDs: ["com.apple.finder"], macroIDs: [m.id])])
        #expect(rig.engine.activeProfileInfo.macros.map(\.name) == ["Gone"])
        try rig.engine.delete(id: m.id)
        #expect(rig.engine.profiles[0].macroIDs.isEmpty)
        #expect(rig.engine.activeProfileInfo.macros.isEmpty)
        #expect(try rig.profiles.load()?[0].macroIDs.isEmpty == true)
    }

    @Test func recordingFromThePhoneBecomesADraft() throws {
        let rig = Rig()
        try rig.engine.start(seedStarters: false)
        try rig.engine.startRecording(options: RecordingOptions(keepTiming: false))
        #expect(rig.engine.isRecording)
        rig.source.emit(RecordedEvent(time: 0, kind: .keyDown(keyCode: 0x11, characters: "t", modifiers: [.command], isRepeat: false)))
        rig.source.emit(RecordedEvent(time: 0.2, kind: .keyDown(keyCode: 0x04, characters: "h", modifiers: [], isRepeat: false)))
        let result = try rig.engine.stopRecording()
        let draft = MacroEngine.draft(from: result, name: "Recorded")
        #expect(draft.steps == [.keystroke(KeyCombo("t", [.command])), .typeText("h")])
        #expect(draft.origin == .recorded)
        #expect(!rig.engine.isRecording)
    }

    @Test func unknownMacroIsReported() async {
        let rig = Rig()
        let id = UUID()
        #expect(await rig.engine.run(id, trigger: .deck).outcome == .failed(.macroNotFound(id)))
    }
}
