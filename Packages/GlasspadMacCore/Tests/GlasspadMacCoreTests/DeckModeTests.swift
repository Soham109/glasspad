import AppKit
import Foundation
import GlasspadKit
import Testing
@testable import GlasspadMacCore

@Suite @MainActor struct DeckTests {
    private func deck(_ buttons: [DeckButton], shell: Bool = false, env: FakeDeckEnvironment = FakeDeckEnvironment()) throws
        -> (DeckMode, FakeDeckEnvironment) {
        let url = tempURL("deck.json")
        try DeckConfig(allowShellCommands: shell, buttons: buttons, pages: nil).save(to: url)
        return (DeckMode(env: env, url: url), env)
    }

    private func outcome(_ d: DeckMode, _ action: DeckAction) async -> DeckMode.Outcome { await d.perform(action) }

    @Test func configRoundTripAndVersionOneStillLoads() throws {
        let url = tempURL("deck.json")
        let cfg = DeckConfig(allowShellCommands: true, buttons: [
            DeckButton(title: "App", symbol: "app", action: .openApp(bundleID: "com.apple.Notes")),
            DeckButton(title: "Shell", symbol: "terminal", action: .shellScript("echo hi")),
        ], pages: [DeckPage(title: "P", buttons: [])], columns: 4)
        try cfg.save(to: url)
        #expect(DeckConfig.load(from: url) == cfg)

        let v1 = #"{"version":1,"allowShellCommands":false,"buttons":[{"id":"\#(UUID().uuidString)","title":"S","symbol":"safari","action":{"openApp":{"bundleID":"com.apple.Safari"}}}]}"#
        try Data(v1.utf8).write(to: url)
        let loaded = DeckConfig.load(from: url)
        // Migrated: nothing lost, the old buttons become "My Buttons" behind the new Mac page.
        #expect(loaded.version == DeckConfig.currentVersion)
        #expect(loaded.layout.pages.map(\.id) == [DeckConfig.macPageID, DeckConfig.myPageID])
        #expect(loaded.layout.pages[1].buttons.map(\.title) == ["S"])
        #expect(loaded.layout.pages[0].buttons.contains { $0.action == .system(.lockScreen) })
        #expect(loaded.buttons.contains { $0.title == "S" })
    }

    @Test func missingOrCorruptConfigGivesStarterSet() throws {
        let url = tempURL("deck.json")
        let fresh = DeckConfig.load(from: url)
        #expect(fresh.layout.pages.map(\.title) == ["Mac", "My Buttons"])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{nope".utf8).write(to: url)
        #expect(DeckConfig.load(from: url).allowShellCommands == false)
        // The starter set never contains a shell button.
        #expect(!DeckConfig().layout.allButtons.contains { if case .shellScript = $0.action { true } else { false } })
    }

    @Test func versionTwoPagesGetTheMacPageOnceAndKeepTheirOwn() throws {
        let mine = DeckPage(title: "Figma", appBundleIDs: ["com.figma.Desktop"], buttons: [DeckButton(title: "X", symbol: "x", action: .typeText("x"))])
        let v2 = DeckConfig(version: 2, buttons: [], pages: [mine])
        let m = v2.migrated()
        #expect(m.layout.pages.map(\.title) == ["Mac", "Figma"])
        #expect(m.layout.pages[1] == mine)
        // Already current: untouched, so a user who deleted the Mac page keeps it deleted.
        var current = m
        current.pages = [mine]
        #expect(current.migrated().layout.pages == [mine])
    }

    @Test func idsStayStableAcrossReloadsWhenNoFileExisted() throws {
        let url = tempURL("deck.json")
        let d = DeckMode(env: FakeDeckEnvironment(), url: url)
        let ids = d.config.layout.allButtons.map(\.id)
        d.reload()
        #expect(d.config.layout.allButtons.map(\.id) == ids)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func basicActionsRunThroughEnvironment() async throws {
        let key = Keystroke(key: .character("c"), modifiers: [.command])
        let macroID = UUID()
        let buttons = [
            DeckButton(title: "A", symbol: "a", action: .openApp(bundleID: "com.apple.Notes")),
            DeckButton(title: "U", symbol: "u", action: .openURL("https://example.com")),
            DeckButton(title: "S", symbol: "s", action: .runShortcut(name: "Focus")),
            DeckButton(title: "K", symbol: "k", action: .keystroke(key)),
            DeckButton(title: "T", symbol: "t", action: .typeText("hello")),
            DeckButton(title: "M", symbol: "m", action: .runMacro(id: macroID)),
        ]
        let (d, env) = try deck(buttons)
        for b in buttons { #expect(await d.run(id: b.id) == [.deckResult(id: b.id, ok: true, message: nil)]) }
        #expect(env.opened == ["com.apple.Notes"])
        #expect(env.urls == [URL(string: "https://example.com")!])
        #expect(env.runs.first?.0 == "/usr/bin/shortcuts")
        #expect(env.runs.first?.1 == ["run", "Focus"])
        #expect(env.pressed == [key])
        #expect(env.typed == ["hello"])
        #expect(env.macros == [macroID])
    }

    @Test func buttonsInsideFoldersAndOtherPagesRun() async throws {
        let inner = DeckButton(title: "In", symbol: "a", action: .typeText("x"))
        let url = tempURL("deck.json")
        let layout = DeckLayout(pages: [DeckPage(title: "1", buttons: []),
                                        DeckPage(title: "2", buttons: [DeckButton(title: "F", symbol: "folder", action: .folder, children: [inner])])])
        try DeckConfig(layout: layout, allowShellCommands: false).save(to: url)
        let env = FakeDeckEnvironment()
        let d = DeckMode(env: env, url: url)
        #expect(await d.run(id: inner.id) == [.deckResult(id: inner.id, ok: true, message: nil)])
        #expect(env.typed == ["x"])
    }

    @Test func openFileExpandsHomeAndChecksItExists() async throws {
        let (d, env) = try deck([])
        env.existing = ["/Users/test/Downloads"]
        #expect(await outcome(d, .openFile(path: "~/Downloads")).ok)
        #expect(env.urls.last?.path == "/Users/test/Downloads")
        #expect(await outcome(d, .openFile(path: "~/Nope")).ok == false)
        #expect(await outcome(d, .openFile(path: "relative/path")).message == "Use a full path, like ~/Documents")
        #expect(env.urls.count == 1)
    }

    @Test func shellNeedsExplicitOptIn() async throws {
        let shell = DeckButton(title: "Sh", symbol: "terminal", action: .shellScript("touch /tmp/x"))
        let (d, env) = try deck([shell])
        let first = await d.run(id: shell.id)
        if case .deckResult(_, let ok, let msg) = first[0] {
            #expect(!ok)
            #expect(msg?.contains("off") == true)
        }
        #expect(env.runs.isEmpty)
        var cfg = d.config
        cfg.allowShellCommands = true
        try d.update(cfg)
        #expect(await d.run(id: shell.id) == [.deckResult(id: shell.id, ok: true, message: nil)])
        #expect(env.runs.first?.0 == "/bin/zsh")
    }

    @Test func unknownButtonAndFileURLsAreRefused() async throws {
        let file = DeckButton(title: "F", symbol: "doc", action: .openURL("file:///Applications/Calculator.app"))
        let (d, env) = try deck([file])
        let unknown = UUID()
        #expect(await d.run(id: unknown) == [.deckResult(id: unknown, ok: false, message: "Button not found")])
        #expect(await d.run(id: file.id) == [.deckResult(id: file.id, ok: false, message: "Invalid URL")])
        #expect(env.urls.isEmpty)
    }

    // MARK: Screenshots

    @Test func screenshotCapturesDirectlyIntoTheScreenshotFolder() async throws {
        let (d, env) = try deck([])
        let r = await outcome(d, .screenshot(DeckScreenshot(area: .fullScreen)))
        #expect(r.ok && r.image == nil)
        let (tool, args) = try #require(env.runs.first)
        #expect(tool == "/usr/sbin/screencapture")
        #expect(args.count == 1)   // no -i, no -U: nothing interactive, no toolbar
        let expected = env.shots.appendingPathComponent(DeckMode.fileName("Screenshot", date: env.clock, ext: "png")).path
        #expect(args[0] == expected)
        #expect(args[0].hasPrefix("/Users/test/Pictures/Shots/Screenshot "))
    }

    @Test func screenshotFlagsPerArea() throws {
        let (d, env) = try deck([])
        let file = URL(fileURLWithPath: "/x/s.png")
        #expect(d.screencaptureArguments(.fullScreen, file: file) == ["/x/s.png"])
        #expect(d.screencaptureArguments(.frontWindow, file: file) == ["-l", "4242", "/x/s.png"])
        #expect(d.screencaptureArguments(.selection, file: file) == ["-i", "-s", "/x/s.png"])
        env.frontWindow = nil
        #expect(d.screencaptureArguments(.frontWindow, file: file) == nil)
    }

    @Test func screenshotCanGoToThePhoneAndMacClipboard() async throws {
        let id = UUID()
        let button = DeckButton(id: id, title: "Shot", symbol: "camera",
                                action: .screenshot(DeckScreenshot(area: .frontWindow, sendToPhone: .photos, copyToMacClipboard: true)))
        let (d, env) = try deck([button])
        let replies = await d.run(id: id)
        #expect(replies.count == 2)
        #expect(replies[0] == .deckResult(id: id, ok: true, message: nil))
        guard case .deckImage(let rid, let data, let dest) = replies[1] else { Issue.record("no image"); return }
        #expect(rid == id && dest == .photos)
        #expect(String(decoding: data, as: UTF8.self).hasPrefix("image:Screenshot "))
        #expect(env.copiedToClipboard.count == 1)
    }

    @Test func cancelledSelectionAndMissingPermissionAreExplained() async throws {
        let (d, env) = try deck([])
        env.captureCreatesFile = false
        #expect(await outcome(d, .screenshot(DeckScreenshot(area: .selection))).message == "Screenshot cancelled")
        env.runResult = (false, "")
        #expect(await outcome(d, .screenshot(DeckScreenshot(area: .fullScreen))).message?.contains("Screen") == true)
        env.frontWindow = nil
        #expect(await outcome(d, .screenshot(DeckScreenshot(area: .frontWindow))).message == "No window to capture")
    }

    @Test func screenRecordingStartsThenStops() async throws {
        let (d, env) = try deck([])
        #expect(await outcome(d, .screenRecording).ok)
        #expect(d.isRecording)
        let (tool, args) = try #require(env.started.first)
        #expect(tool == "/usr/sbin/screencapture")
        #expect(args.first == "-v")
        #expect(args.last?.hasSuffix(".mov") == true)
        #expect(await outcome(d, .screenRecording).ok)
        #expect(env.lastProcess?.interrupted == 1)
        #expect(!d.isRecording)
        #expect(env.started.count == 1)
    }

    // MARK: System controls

    @Test func systemControlsMapToTheRightCalls() async throws {
        let (d, env) = try deck([])
        #expect(await outcome(d, .system(.lockScreen)).ok)
        #expect(env.pressed.last == Keystroke(key: .character("q"), modifiers: [.command, .control]))
        _ = await outcome(d, .system(.sleepDisplay))
        #expect(env.runs.last?.0 == "/usr/bin/pmset" && env.runs.last?.1 == ["displaysleepnow"])
        _ = await outcome(d, .system(.sleepMac))
        #expect(env.runs.last?.1 == ["sleepnow"])
        _ = await outcome(d, .system(.showDesktop))
        #expect(env.runs.last?.0 == DeckMode.missionControlPath && env.runs.last?.1 == ["1"])
        _ = await outcome(d, .system(.missionControl))
        #expect(env.runs.last?.1 == [])
        _ = await outcome(d, .system(.appExpose))
        #expect(env.runs.last?.1 == ["2"])
        _ = await outcome(d, .system(.toggleDarkMode))
        #expect(env.runs.last?.0 == "/usr/bin/osascript")
        #expect(env.runs.last?.1.last?.contains("dark mode") == true)
        _ = await outcome(d, .system(.emptyTrash))
        #expect(env.runs.last?.1.last?.contains("empty trash") == true)
        _ = await outcome(d, .system(.launchpad))
        #expect(env.opened.last == "com.apple.apps.launcher")
        for (a, c) in [(DeckSystemAction.playPause, MediaCommand.playPause), (.nextTrack, .nextTrack), (.previousTrack, .previousTrack)] {
            _ = await outcome(d, .system(a))
            #expect(env.mediaCommands.last == c)
        }
    }

    @Test func volumeBrightnessAndMicrophone() async throws {
        let (d, env) = try deck([])
        _ = await outcome(d, .system(.volumeUp))
        #expect(abs((env.outputVolume ?? 0) - (0.5 + DeckMode.step)) < 1e-9)
        env.outputVolume = 0.01
        _ = await outcome(d, .system(.volumeDown))
        #expect(env.outputVolume == 0)
        _ = await outcome(d, .system(.mute))
        #expect(env.mutedToggles == 1)
        _ = await outcome(d, .system(.micMute))
        #expect(env.inputMuted == true)
        _ = await outcome(d, .system(.micMute))
        #expect(env.inputMuted == false)
        env.brightness = 0.99
        _ = await outcome(d, .system(.brightnessUp))
        #expect(env.brightness == 1)
        env.brightness = nil
        #expect(await outcome(d, .system(.brightnessDown)).ok == false)
        env.outputVolume = nil
        #expect(await outcome(d, .system(.volumeUp)).ok == false)
    }

    @Test func ejectAndAudioOutput() async throws {
        let (d, env) = try deck([])
        #expect(await outcome(d, .system(.ejectAll)).ok)
        env.ejectResult = (1, 1)
        #expect(await outcome(d, .system(.ejectAll)).message == "1 disk could not be ejected (in use)")
        #expect(await outcome(d, .setAudioOutput(name: "AirPods Pro")).ok)
        #expect(env.selectedOutput == "AirPods Pro")
        #expect(await outcome(d, .setAudioOutput(name: "Nope")).ok == false)
        #expect(await outcome(d, .folder).ok == false)
    }

    @Test func destructiveButtonsNeedConfirmation() async throws {
        let trash = DeckButton(title: "Trash", symbol: "trash", action: .system(.emptyTrash))
        let (d, env) = try deck([trash])
        #expect(await d.run(id: trash.id) == [.deckResult(id: trash.id, ok: false, message: "Confirm on the phone first.")])
        #expect(env.runs.isEmpty)
        #expect(await d.run(id: trash.id, confirmed: true) == [.deckResult(id: trash.id, ok: true, message: nil)])
        #expect(env.runs.count == 1)
    }

    // MARK: Phone edits

    @Test func phoneEditsSaveButNeverAddShell() throws {
        let shell = DeckButton(title: "Sh", symbol: "terminal", action: .shellScript("echo safe"))
        let (d, _) = try deck([shell], shell: true)
        // Reordering and adding normal buttons is fine, an existing shell button may stay.
        let added = DeckButton(title: "Notes", symbol: "note", action: .openApp(bundleID: "com.apple.Notes"))
        let ok = DeckLayout(pages: [DeckPage(title: "Main", buttons: [added, shell])], columns: 9, allowsShellCommands: true)
        #expect(d.savePhoneEdit(ok) == .deckSaveResult(ok: true, message: nil))
        #expect(d.config.layout.pages[0].buttons.map(\.title) == ["Notes", "Sh"])
        #expect(d.config.columns == 6)              // clamped
        #expect(d.config.allowShellCommands)        // the phone's flag is ignored either way

        // A new shell button, or an edited script, is refused and nothing changes.
        var changed = shell
        changed.action = .shellScript("rm -rf ~")
        let bad = DeckLayout(pages: [DeckPage(title: "Main", buttons: [changed])])
        #expect(d.savePhoneEdit(bad) == .deckSaveResult(ok: false, message: DeckEditError.shellFromPhone.message))
        let fresh = DeckLayout(pages: [DeckPage(title: "Main", buttons: [DeckButton(title: "x", symbol: "x", action: .shellScript("id"))])])
        #expect(d.savePhoneEdit(fresh).isFailedSave)
        #expect(d.config.layout.pages[0].buttons.map(\.title) == ["Notes", "Sh"])
    }

    @Test func phoneCannotTurnShellOn() throws {
        let (d, _) = try deck([], shell: false)
        let layout = DeckLayout(pages: [DeckPage(title: "Main", buttons: [])], allowsShellCommands: true)
        #expect(d.savePhoneEdit(layout) == .deckSaveResult(ok: true, message: nil))
        #expect(!d.config.allowShellCommands)
    }

    @Test func flatListStaysForOlderPhones() throws {
        let inner = DeckButton(title: "In", symbol: "a", action: .typeText("x"))
        let folder = DeckButton(title: "F", symbol: "folder", action: .folder, children: [inner])
        let cfg = DeckConfig(layout: DeckLayout(pages: [DeckPage(title: "P", buttons: [folder])]), allowShellCommands: false)
        #expect(cfg.buttons == [inner])
    }

    @Test func catalogListsOutputsAndShortcuts() async throws {
        let (d, _) = try deck([])
        let c = await d.catalog()
        #expect(c.audioOutputs == ["MacBook Pro Speakers", "AirPods Pro"])
        #expect(c.shortcuts == ["Focus On", "Focus Off"])
    }
}

private extension ModeMessage {
    var isFailedSave: Bool { if case .deckSaveResult(false, _) = self { true } else { false } }
}

@Suite @MainActor struct ModeRouterTests {
    private func router() -> (ModeRouter, FakeWorkspace, MacDockHider, () -> [ModeMessage]) {
        let poster = CapturingEventPoster()
        let keys = KeysMode(poster: poster, source: nil)
        let ws = FakeWorkspace()
        let hider = FakeDockHider.make().hider
        let deckURL = tempURL("deck.json")
        let r = ModeRouter(keys: keys, dock: DockMode(workspace: ws, cacheDirectory: nil), media: MediaMode(poster: poster),
                           deck: DeckMode(env: FakeDeckEnvironment(), url: deckURL), clipboard: ClipboardMode(),
                           present: PresentMode(keys: keys), macDock: hider)
        r.disconnectGrace = 0
        var sent: [ModeMessage] = []
        r.send = { sent.append($0) }
        return (r, ws, hider, { sent })
    }

    @Test func dockSyncRepliesWithListAndDockState() {
        let (r, _, _, sent) = router()
        r.handle(.dockSync(iconKeys: []))
        #expect(sent().contains { if case .dockList = $0 { true } else { false } })
        #expect(sent().contains { if case .macDockState = $0 { true } else { false } })
    }

    @Test func openReportsTheOutcome() {
        let (r, _, _, sent) = router()
        r.handle(.dockOpen(bundleID: "com.example.none"))
        #expect(sent().contains(.dockOpenResult(bundleID: "com.example.none", ok: false, message: "This app is not installed on your Mac.")))
    }

    @Test func phoneSwitchesTheMacDockAndDisconnectRestoresIt() async throws {
        let (r, _, hider, _) = router()
        r.handle(.macDockSet(MacDockState(hidden: false, hideWhileConnected: true)))
        #expect(hider.isHidden)
        r.sessionEnded()
        try await Task.sleep(for: .milliseconds(50))
        #expect(!hider.isHidden)
        r.handle(.modeSelected(.dock))   // a phone is back
        #expect(hider.isHidden)
        r.appWillTerminate()
        #expect(!hider.isHidden)
    }

    @Test func deckRequestSendsFlatListAndLayout() {
        let (r, _, _, sent) = router()
        r.handle(.deckRequest)
        #expect(sent().contains { if case .deckButtons = $0 { true } else { false } })
        #expect(sent().contains { if case .deckLayout = $0 { true } else { false } })
    }

    @Test func frontmostChangesReachDeck() {
        let (r, _, _, sent) = router()
        r.handle(.modeSelected(.deck))
        r.workspaceChanged(activated: "com.apple.Safari", name: "Safari", url: nil)
        #expect(sent().last == .frontmostApp(bundleID: "com.apple.Safari"))
    }
}
