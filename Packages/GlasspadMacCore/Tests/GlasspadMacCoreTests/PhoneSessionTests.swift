import AppKit
import CoreGraphics
import Foundation
import GlasspadMacros
import Testing
@testable import GlasspadKit
@testable import GlasspadMacCore

// The whole phone to Mac conversation for every mode, end to end: a real GlasspadClient (the
// phone) talks to a real GlasspadServer (the Mac) over loopback, paired with a real key and
// sealed, and the Mac answers through the real ModeRouter. Everything that would touch this
// Mac (events, apps, AppleScript, pmset, volume, the pasteboard, the laser window) is a fake
// that records what it was asked to do.

/// Mac side: hands each mode message to the router, as GlasspadController does.
private final class RouterBridge: GlasspadLinkDelegate {
    let router: ModeRouter
    init(_ router: ModeRouter) { self.router = router }
    func link(didChangeState state: LinkState) {}
    func link(didReceive message: ControlMessage) {
        guard case .mode(let m) = message else { return }
        let r = router
        MainActor.assumeIsolated { r.handle(m) }
    }
}

/// Phone side: every mode message the Mac sent, in order.
final class PhoneInbox: GlasspadLinkDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _messages: [ModeMessage] = []
    private var _other: [ControlMessage] = []
    var messages: [ModeMessage] { lock.withLock { _messages } }
    var other: [ControlMessage] { lock.withLock { _other } }
    func link(didChangeState state: LinkState) {}
    func link(didReceive message: ControlMessage) {
        lock.withLock {
            if case .mode(let m) = message { _messages.append(m) } else { _other.append(message) }
        }
    }
}

/// Records the Mac's sound, brightness and now playing switches instead of using them.
@MainActor
final class MediaSwitches {
    var remoteCommands: [MediaCommand] = []
    var volumes: [Float] = []
    var brightness: [Float] = []
    var muted = false
    var muteChanges = 0
    var outputs: [String] = []
    /// What MediaRemote answers; false falls through to the media key (posted to the fake).
    var remoteWorks = true

    func install(on media: MediaMode) {
        media.system = MediaMode.SystemControls(
            sendRemote: { [unowned self] c in remoteCommands.append(c); return remoteWorks },
            setVolume: { [unowned self] v in volumes.append(v) },
            isMuted: { [unowned self] in muted },
            setMuted: { [unowned self] m in muted = m; muteChanges += 1 },
            setBrightness: { [unowned self] v in brightness.append(v) },
            selectOutput: { [unowned self] id in outputs.append(id) },
            remoteAnswersThisProcess: true)
    }
}

@MainActor
final class PhoneSession {
    let server: GlasspadServer
    let client: GlasspadClient
    let inbox = PhoneInbox()
    let router: ModeRouter
    let poster: CapturingEventPoster
    let env: FakeDeckEnvironment
    let workspace: FakeWorkspace
    let switches = MediaSwitches()
    let pasteboard: NSPasteboard
    let present: PresentMode
    let dockDefaults: FakeDefaults
    let macros: MacroHarness?
    private let bridge: RouterBridge

    init(seedMacros: Bool = false) async throws {
        let poster = CapturingEventPoster()
        self.poster = poster
        let keys = KeysMode(poster: poster, source: nil)
        workspace = FakeWorkspace()
        workspace.running = [DockMode.RunningApp(bundleID: "com.apple.Safari", name: "Safari",
                                                 url: URL(fileURLWithPath: "/Applications/Safari.app"), active: true, pid: 501)]
        workspace.front = "com.apple.Safari"
        workspace.installed = [("com.apple.Safari", "Safari", URL(fileURLWithPath: "/Applications/Safari.app")),
                               ("com.apple.Notes", "Notes", URL(fileURLWithPath: "/System/Applications/Notes.app"))]
        workspace.lsURLs = ["com.apple.Notes": [URL(fileURLWithPath: "/System/Applications/Notes.app")],
                            "com.apple.Safari": [URL(fileURLWithPath: "/Applications/Safari.app")]]
        workspace.existing = ["/System/Applications/Notes.app", "/Applications/Safari.app"]
        env = FakeDeckEnvironment()
        let media = MediaMode(poster: poster, adapter: NowPlayingAdapter(library: nil), runner: FakeAppleScriptRunner(),
                              runningPlayers: { [] })
        switches.install(on: media)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("glasspad-qa-\(UUID().uuidString)"))
        present = PresentMode(keys: keys)
        present.drawsOverlay = false
        let hider = FakeDockHider.make()
        dockDefaults = hider.dock
        router = ModeRouter(keys: keys, dock: DockMode(workspace: workspace, cacheDirectory: nil), media: media,
                            deck: DeckMode(env: env, url: tempURL("deck.json")), clipboard: ClipboardMode(pasteboard: pasteboard),
                            present: present, macDock: hider.hider)
        router.disconnectGrace = 0
        // Mac control steps in macros run through this Deck, as the app's router sets up.
        let relay = MacControlRelay()
        let deck = router.deck
        relay.perform = { await deck.perform(.system($0)) }
        macros = seedMacros ? try MacroHarness(seed: true, controls: relay) : nil
        router.macros = macros?.coordinator

        let key = PairingPayload.generateKey()
        let macID = UUID()
        server = GlasspadServer(macID: macID, macName: "QA Mac", advertise: false, delegateQueue: .main) { _ in key }
        bridge = RouterBridge(router)
        server.delegate = bridge
        client = GlasspadClient(phoneID: "qa-phone", phoneName: "QA Phone",
                                pairing: PairingPayload(macID: macID, macName: "QA Mac", pairKey: key))
        client.delegate = inbox
        let server = self.server
        router.send = { server.send(.mode($0)) }
        macros?.coordinator.send = { server.send(.mode(.macro($0))) }
        try server.start()
        #expect(await eventually { server.ports != nil })
        let port = try #require(server.ports).tcp
        client.connect(host: "127.0.0.1", port: port)
        #expect(await eventually { self.client.state == .connected(rttMs: nil) && server.connectedPhone != nil })
    }

    func close() {
        router.sessionEnded()
        router.appWillTerminate()
        client.disconnect()
        server.stop()
    }

    /// Sends as the phone does and waits for the first Mac answer (after this send) that matches.
    @discardableResult
    func send(_ message: ModeMessage, timeout: TimeInterval = 3,
              until match: ((ModeMessage) -> Bool)? = nil) async -> ModeMessage? {
        let start = inbox.messages.count
        client.send(message: .mode(message))
        guard let match else {
            // No answer expected: a request that is always answered, sent after it, comes back
            // once the Mac has handled it (one TCP stream, handled in order on the main queue).
            client.send(message: .mode(.dockCatalogRequest))
            _ = await eventually(timeout) {
                self.inbox.messages.dropFirst(start).contains { if case .dockCatalog = $0 { true } else { false } }
            }
            return nil
        }
        var found: ModeMessage?
        _ = await eventually(timeout) {
            found = self.inbox.messages.dropFirst(start).first(where: match)
            return found != nil
        }
        return found
    }

    /// Runs `message` and returns the deckResult for `id`.
    func result(_ message: ModeMessage, id: UUID, timeout: TimeInterval = 3) async -> (ok: Bool, message: String?)? {
        let reply = await send(message, timeout: timeout) {
            if case .deckResult(id, _, _) = $0 { true } else { false }
        }
        guard case .deckResult(_, let ok, let text)? = reply else { return nil }
        return (ok, text)
    }

    /// Key codes of the key-down events posted since `from`.
    func keyDowns(from: Int = 0) -> [Int64] {
        poster.events.dropFirst(from).filter { $0.type == .keyDown }.map { $0.getIntegerValueField(.keyboardEventKeycode) }
    }
}

func isCase(_ m: ModeMessage, _ tag: String) -> Bool { m.tag == tag }

@Suite(.serialized) @MainActor struct PhoneSessionTests {

    // MARK: General and Dock

    @Test func dockRequestsOpenActOnAppsAndSwitchTheMacDock() async throws {
        let s = try await PhoneSession()
        defer { s.close() }

        let front = await s.send(.modeSelected(.dock)) { isCase($0, "frontmostApp") }
        #expect(front == .frontmostApp(bundleID: "com.apple.Safari"))
        #expect(s.router.phoneMode == .dock)

        let list = await s.send(.dockRequest) { isCase($0, "dockList") }
        guard case .dockList(let apps)? = list else { Issue.record("no dock list"); return }
        #expect(apps.contains { $0.bundleID == "com.apple.Safari" && $0.running && $0.active })
        #expect(await eventually { s.inbox.messages.contains { isCase($0, "macDockState") } })

        let synced = await s.send(.dockSync(iconKeys: ["com.apple.Safari@1700000000"])) { isCase($0, "dockList") }
        guard case .dockList(let again)? = synced else { Issue.record("no dock list after sync"); return }
        #expect(again.first { $0.bundleID == "com.apple.Safari" }?.iconPNG == nil)   // the phone has it

        // Opening a running app activates it; one that is not installed says so in words.
        let opened = await s.send(.dockOpen(bundleID: "com.apple.Safari")) { isCase($0, "dockOpenResult") }
        guard case .dockOpenResult("com.apple.Safari", let ok, _)? = opened else { Issue.record("no open result"); return }
        #expect(ok)
        #expect(s.workspace.activated.contains(501))
        let missing = await s.send(.dockOpen(bundleID: "com.example.missing")) { isCase($0, "dockOpenResult") }
        guard case .dockOpenResult(_, false, let why?)? = missing else { Issue.record("missing app opened"); return }
        #expect(why.contains("not installed"))

        // Every long-press action.
        for action in DockAppAction.allCases {
            await s.send(.dockAppAction(bundleID: "com.apple.Safari", action: action))
        }
        #expect(s.workspace.terminated == [501])
        #expect(s.workspace.hidden == [501])
        #expect(s.workspace.unhidden == [501])
        #expect(s.workspace.revealed.map(\.path) == ["/Applications/Safari.app"])
        let notRunning = await s.send(.dockAppAction(bundleID: "com.apple.Notes", action: .quit)) { isCase($0, "dockOpenResult") }
        guard case .dockOpenResult("com.apple.Notes", false, _)? = notRunning else { Issue.record("quit of a closed app"); return }

        let catalog = await s.send(.dockCatalogRequest) { isCase($0, "dockCatalog") }
        guard case .dockCatalog(let all)? = catalog else { Issue.record("no catalog"); return }
        #expect(all.map(\.name) == ["Notes", "Safari"])
        #expect(all.allSatisfy { $0.iconPNG == nil && $0.iconKey != nil })

        let icons = await s.send(.dockIconRequest(bundleIDs: ["com.apple.Notes", "com.example.missing"])) { isCase($0, "dockIcons") }
        guard case .dockIcons(let withIcons)? = icons else { Issue.record("no icons"); return }
        #expect(withIcons.map(\.bundleID) == ["com.apple.Notes"])
        #expect(withIcons.first?.iconPNG.flatMap(NSBitmapImageRep.init(data:)) != nil)

        let set = MacDockState(hidden: true, hideWhileConnected: false)
        let state = await s.send(.macDockSet(set)) { if case .macDockState(let st) = $0 { st.hidden } else { false } }
        #expect(state != nil)
        #expect(s.dockDefaults.values["com.apple.dock"]?["autohide"] as? Bool == true)
        await s.send(.macDockSet(MacDockState(hidden: false, hideWhileConnected: false))) {
            if case .macDockState(let st) = $0 { !st.hidden } else { false }
        }
        #expect(s.server.stats.malformed == 0 && s.server.stats.authFailures == 0)
    }

    // MARK: Keys

    @Test func keysTypeTextAndPressEveryNamedKey() async throws {
        let s = try await PhoneSession()
        defer { s.close() }
        await s.send(.modeSelected(.keys))
        await s.send(.keysText("héllo\nwörld 👋"))
        #expect(await eventually { s.poster.events.count >= 6 })
        let typed = s.poster.events.filter { $0.type == .keyDown }.map { e -> String in
            e.getIntegerValueField(.keyboardEventKeycode) == 36 ? "<return>" : KeyboardSynth.unicodeString(of: e)
        }
        #expect(typed == ["héllo", "<return>", "wörld 👋"])

        // Every named key the phone has, with the modifiers it was sent with.
        for special in GlasspadKit.SpecialKey.allCases {
            let before = s.poster.events.count
            await s.send(.keysKeystroke(Keystroke(key: .special(special), modifiers: [.shift])))
            #expect(await eventually { s.poster.events.count == before + 2 }, "\(special)")
            let down = s.poster.events[before]
            #expect(down.getIntegerValueField(.keyboardEventKeycode) == Int64(KeysMode.specialCodes[special] ?? 999), "\(special)")
            #expect(down.flags.contains(.maskShift), "\(special)")
        }

        // A shortcut: cmd+shift+z presses z with both.
        let before = s.poster.events.count
        await s.send(.keysKeystroke(Keystroke(key: .character("z"), modifiers: [.command, .shift])))
        #expect(await eventually { s.poster.events.count == before + 2 })
        #expect(s.keyDowns(from: before) == [6])
        #expect(s.poster.events[before].flags.contains([.maskCommand, .maskShift]))
    }

    // MARK: Media

    @Test func mediaSendsStateAndEveryControlReachesTheMac() async throws {
        let s = try await PhoneSession()
        defer { s.close() }
        await s.send(.modeSelected(.media))
        let state = await s.send(.mediaRequest) { isCase($0, "mediaState") }
        #expect(state != nil)

        for command in MediaCommand.allCases where command != .mute {
            await s.send(.mediaCommand(command))
        }
        #expect(s.switches.remoteCommands == MediaCommand.allCases.filter { $0 != .mute })
        await s.send(.mediaCommand(.mute))
        #expect(s.switches.muted && s.switches.muteChanges == 1)
        await s.send(.mediaCommand(.mute))
        #expect(!s.switches.muted && s.switches.muteChanges == 2)

        // Without MediaRemote the media key goes out instead (to the capturing poster).
        s.switches.remoteWorks = false
        await s.send(.mediaCommand(.nextTrack))
        #expect(s.poster.events.contains { $0.type.rawValue == 14 })   // NSSystemDefined

        await s.send(.mediaSetVolume(0.25))
        await s.send(.mediaSetVolume(7))                   // out of range: clamped
        await s.send(.mediaSetBrightness(-1))
        #expect(s.switches.volumes == [0.25, 1])
        #expect(s.switches.brightness == [0])

        await s.send(.mediaControl(.selectOutput(id: "BuiltInSpeakerDevice")))
        #expect(s.switches.outputs == ["BuiltInSpeakerDevice"])
        // Seek, shuffle and repeat with no player: nothing to reach, and nothing breaks.
        await s.send(.mediaControl(.seek(42)))
        await s.send(.mediaControl(.setShuffle(true)))
        await s.send(.mediaControl(.setRepeat(.all)))
        let after = await s.send(.mediaRequest) { isCase($0, "mediaState") }
        #expect(after != nil)
        #expect(s.server.stats.malformed == 0)
    }

    // MARK: Deck

    /// One button of every kind the phone can save, with what the fake Mac must have done.
    static func everyKind(macro: UUID) -> [DeckButton] {
        func b(_ title: String, _ action: DeckAction) -> DeckButton { DeckButton(title: title, symbol: "star", action: action) }
        return [
            b("App", .openApp(bundleID: "com.apple.Notes")),
            b("Site", .openURL("https://www.apple.com")),
            b("Shortcut", .runShortcut(name: "Focus On")),
            b("Key", .keystroke(Keystroke(key: .character("t"), modifiers: [.command]))),
            b("File", .openFile(path: "~/Downloads")),
            b("Macro", .runMacro(id: macro)),
            b("Type", .typeText("Hello")),
            b("Shot", .screenshot(DeckScreenshot(area: .fullScreen, sendToPhone: .photos, copyToMacClipboard: true))),
            b("Window Shot", .screenshot(DeckScreenshot(area: .frontWindow))),
            b("Area Shot", .screenshot(DeckScreenshot(area: .selection, sendToPhone: .clipboard))),
            b("Output", .setAudioOutput(name: "AirPods Pro")),
        ]
    }

    @Test func deckSavesAndRunsEveryKindOfButton() async throws {
        let s = try await PhoneSession()
        defer { s.close() }
        s.env.existing.insert("/Users/test/Downloads")
        await s.send(.modeSelected(.deck)) { isCase($0, "frontmostApp") }
        let first = await s.send(.deckRequest) { isCase($0, "deckLayout") }
        guard case .deckLayout(let starter)? = first else { Issue.record("no layout"); return }
        #expect(s.inbox.messages.contains { isCase($0, "deckButtons") })
        #expect(!starter.allButtons.isEmpty)

        let macroID = UUID()
        let buttons = Self.everyKind(macro: macroID)
        let folder = DeckButton(title: "Folder", symbol: "folder.fill", action: .folder, children: [
            DeckButton(title: "Inner", symbol: "star", action: .typeText("inside")),
        ])
        var layout = starter
        layout.pages.append(DeckPage(title: "QA", symbol: "checkmark", appBundleIDs: ["com.apple.Safari"], buttons: buttons + [folder]))
        layout.columns = 9                                   // out of range: the Mac clamps it
        let saved = await s.send(.deckSave(layout)) { isCase($0, "deckSaveResult") }
        #expect(saved == .deckSaveResult(ok: true, message: nil))
        let echoed = await s.send(.deckRequest) { isCase($0, "deckLayout") }
        guard case .deckLayout(let back)? = echoed else { Issue.record("no layout after save"); return }
        #expect(back.columns == 6)
        #expect(back.allButtons.count == starter.allButtons.count + buttons.count + 2)

        for button in buttons {
            let r = await s.result(.deckRun(id: button.id), id: button.id)
            #expect(r?.ok == true, "\(button.title): \(r?.message ?? "no answer")")
        }
        #expect(s.env.opened.contains("com.apple.Notes"))
        #expect(s.env.urls.map(\.absoluteString).contains("https://www.apple.com"))
        #expect(s.env.urls.map(\.path).contains("/Users/test/Downloads"))
        #expect(s.env.runs.contains { $0.0 == "/usr/bin/shortcuts" && $0.1 == ["run", "Focus On"] })
        #expect(s.env.pressed.contains(Keystroke(key: .character("t"), modifiers: [.command])))
        #expect(s.env.macros == [macroID])
        #expect(s.env.typed == ["Hello"])
        #expect(s.env.selectedOutput == "AirPods Pro")
        let captures = s.env.runs.filter { $0.0 == "/usr/sbin/screencapture" }.map(\.1)
        #expect(captures.count == 3)
        #expect(captures.contains { $0.first == "-l" && $0.dropFirst().first == "4242" })
        #expect(captures.contains { $0.starts(with: ["-i", "-s"]) })
        #expect(s.env.copiedToClipboard.count == 1)
        // The two shots that go to the phone arrive as images.
        let images = s.inbox.messages.compactMap { m -> DeckImageDestination? in
            if case .deckImage(_, let data, let d) = m, !data.isEmpty { return d } else { return nil }
        }
        #expect(images.sorted { $0.rawValue < $1.rawValue } == [.clipboard, .photos])

        // A folder's child runs; the folder itself opens on the phone.
        let inner = try #require(folder.children?.first)
        #expect(await s.result(.deckRun(id: inner.id), id: inner.id)?.ok == true)
        #expect(s.env.typed.last == "inside")
        let f = await s.result(.deckRun(id: folder.id), id: folder.id)
        #expect(f?.ok == false && f?.message == "Folders open on your iPhone")

        // A recording starts, then stops on the second tap.
        let rec = DeckButton(title: "Record", symbol: "record.circle", action: .screenRecording)
        layout = back
        layout.pages[layout.pages.count - 1].buttons.append(rec)
        #expect(await s.send(.deckSave(layout)) { isCase($0, "deckSaveResult") } == .deckSaveResult(ok: true, message: nil))
        #expect(await s.result(.deckRun(id: rec.id), id: rec.id)?.ok == true)
        #expect(s.env.started.last?.1.starts(with: ["-v"]) == true)
        #expect(await s.result(.deckRun(id: rec.id), id: rec.id)?.ok == true)
        #expect(s.env.lastProcess?.interrupted == 1)

        // Unknown ids, a missing sound output and a missing file fail in words.
        let ghost = UUID()
        #expect(await s.result(.deckRun(id: ghost), id: ghost)?.message == "Button not found")
        s.env.existing.remove("/Users/test/Downloads")
        let file = try #require(buttons.first { $0.title == "File" })
        let gone = await s.result(.deckRun(id: file.id), id: file.id)
        #expect(gone?.ok == false && gone?.message?.contains("Downloads") == true)

        let catalog = await s.send(.deckCatalogRequest) { isCase($0, "deckCatalog") }
        #expect(catalog == .deckCatalog(DeckCatalog(audioOutputs: s.env.outputs, shortcuts: await s.env.shortcutNames())))
        #expect(s.server.stats.malformed == 0)
    }

    @Test func deckNeverTakesShellButtonsFromThePhone() async throws {
        let s = try await PhoneSession()
        defer { s.close() }
        let first = await s.send(.deckRequest) { isCase($0, "deckLayout") }
        guard case .deckLayout(var layout)? = first else { Issue.record("no layout"); return }
        let shell = DeckButton(title: "rm", symbol: "terminal", action: .shellScript("echo hi"))
        layout.pages[0].buttons.append(shell)
        let r = await s.send(.deckSave(layout)) { isCase($0, "deckSaveResult") }
        guard case .deckSaveResult(false, let why?)? = r else { Issue.record("shell button saved from the phone"); return }
        #expect(why.contains("Mac"))
        #expect(s.router.deck.config.layout.button(id: shell.id) == nil)
        // A layout that says it allows shell commands changes nothing either.
        layout.pages[0].buttons.removeLast()
        layout.allowsShellCommands = true
        #expect(await s.send(.deckSave(layout)) { isCase($0, "deckSaveResult") } == .deckSaveResult(ok: true, message: nil))
        #expect(s.router.deck.config.allowShellCommands == false)

        // A shell button made on the Mac runs only when the Mac allows it.
        var cfg = s.router.deck.config
        cfg.pages?[0].buttons.append(shell)
        try s.router.deck.update(cfg)
        let off = await s.result(.deckRun(id: shell.id), id: shell.id)
        #expect(off?.ok == false && off?.message == "Shell commands are turned off on the Mac")
        cfg.allowShellCommands = true
        try s.router.deck.update(cfg)
        #expect(await s.result(.deckRun(id: shell.id), id: shell.id)?.ok == true)
        #expect(s.env.runs.last?.0 == "/bin/zsh" && s.env.runs.last?.1 == ["-c", "echo hi"])
    }

    /// Every Mac control, as a Deck button: the ones that change or lose something need the
    /// phone's confirmation first, the rest run straight away, and none is left unbuilt.
    @Test func everyMacControlRunsFromTheDeck() async throws {
        let s = try await PhoneSession()
        defer { s.close() }
        let first = await s.send(.deckRequest) { isCase($0, "deckLayout") }
        guard case .deckLayout(var layout)? = first else { Issue.record("no layout"); return }
        let controls = DeckSystemAction.allCases.map {
            DeckButton(title: $0.title, symbol: $0.symbol, action: .system($0), color: $0.color)
        }
        layout.pages.append(DeckPage(title: "Controls", buttons: controls))
        #expect(await s.send(.deckSave(layout)) { isCase($0, "deckSaveResult") } == .deckSaveResult(ok: true, message: nil))

        for button in controls {
            guard case .system(let action) = button.action else { continue }
            if action.needsConfirmation {
                let runs = s.env.runs.count
                let refused = await s.result(.deckRun(id: button.id), id: button.id)
                #expect(refused?.ok == false && refused?.message == "Confirm on your iPhone first.", "\(action)")
                #expect(s.env.runs.count == runs, "\(action) ran without confirmation")
                let confirmed = await s.result(.deckRunConfirmed(id: button.id), id: button.id)
                #expect(confirmed?.ok == true, "\(action): \(confirmed?.message ?? "no answer")")
            } else {
                let r = await s.result(.deckRun(id: button.id), id: button.id)
                #expect(r != nil, "\(action): no answer")
                #expect(r?.message != "Not built yet", "\(action) is not built on the Mac")
                #expect(r?.ok == true, "\(action): \(r?.message ?? "")")
            }
        }
        #expect(s.env.runs.contains { $0.0 == "/usr/bin/pmset" && $0.1 == ["sleepnow"] })
        #expect(s.env.runs.contains { $0.0 == DeckMode.osascript && $0.1.last?.contains("empty trash") == true })
        #expect(s.env.runs.contains { $0.0 == "/usr/bin/pmset" && $0.1 == ["displaysleepnow"] })
        #expect(s.env.mediaCommands == [.playPause, .nextTrack, .previousTrack])
    }

    // MARK: Clipboard

    @Test func clipboardGoesBothWaysWithTextAndImages() async throws {
        let s = try await PhoneSession()
        defer { s.close() }
        await s.send(.modeSelected(.clipboard))

        // Empty pasteboard: nil.
        s.pasteboard.clearContents()
        #expect(await s.send(.clipboardPull) { isCase($0, "clipboardContent") } == .clipboardContent(nil))

        // Phone to Mac, text.
        let pushed = await s.send(.clipboardPush(.text("from the phone ✓"))) { isCase($0, "clipboardPushResult") }
        #expect(pushed == .clipboardPushResult(ok: true, message: nil))
        #expect(s.pasteboard.string(forType: .string) == "from the phone ✓")

        // Mac to phone, text.
        s.pasteboard.clearContents()
        s.pasteboard.setString("from the Mac", forType: .string)
        #expect(await s.send(.clipboardPull) { isCase($0, "clipboardContent") } == .clipboardContent(.text("from the Mac")))

        // Phone to Mac, image; then back again.
        let png = try Self.png(width: 64, height: 48)
        let img = await s.send(.clipboardPush(.imagePNG(png))) { isCase($0, "clipboardPushResult") }
        #expect(img == .clipboardPushResult(ok: true, message: nil))
        #expect(s.pasteboard.data(forType: .png) == png)
        let pulled = await s.send(.clipboardPull) { isCase($0, "clipboardContent") }
        guard case .clipboardContent(.imagePNG(let back)?)? = pulled else { Issue.record("no image back"); return }
        let rep = try #require(NSBitmapImageRep(data: back))
        #expect(rep.pixelsWide == 64 && rep.pixelsHigh == 48)

        // Too much text either way: refused in words, never cut, pasteboard left alone.
        let huge = String(repeating: "a", count: ClipboardContent.maxTextBytes + 1)
        let refused = await s.send(.clipboardPush(.text(huge)), timeout: 10) { isCase($0, "clipboardPushResult") }
        guard case .clipboardPushResult(false, let why?)? = refused else { Issue.record("huge push accepted"); return }
        #expect(why.contains("MB"))
        #expect(s.pasteboard.data(forType: .png) == png)
        s.pasteboard.clearContents()
        s.pasteboard.setString(huge, forType: .string)
        let start = s.inbox.messages.count
        #expect(await s.send(.clipboardPull, timeout: 10) { isCase($0, "clipboardContent") } == .clipboardContent(nil))
        #expect(s.inbox.messages.dropFirst(start).contains { isCase($0, "clipboardPullRefused") })
        #expect(s.server.stats.malformed == 0)
        #expect(s.client.state == .connected(rttMs: nil))
    }

    static func png(width: Int, height: Int) throws -> Data {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.setColor(.systemTeal, atX: 3, y: 3)
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    // MARK: Present

    @Test func presentStepsSlidesAndMovesTheLaser() async throws {
        let s = try await PhoneSession()
        defer { s.close() }
        await s.send(.modeSelected(.present))
        await s.send(.presentNext)
        await s.send(.presentPrevious)
        #expect(await eventually { s.keyDowns().count == 2 })
        #expect(s.keyDowns() == [124, 123])
        await s.send(.presentLaser(on: true))
        await s.send(.presentLaserPosition(x: 0.5, y: 0.25))
        await s.send(.presentLaserPosition(x: 2, y: -1))         // clamped to the screen
        await s.send(.presentLaser(on: false))
        let log = s.present.laserLog
        #expect(log.map(\.visible) == [true, true, true, false])
        let screen = NSScreen.screens.first?.frame ?? .zero
        #expect(log[1].point == PresentMode.screenPoint(x: 0.5, y: 0.25, screen: screen))
        #expect(log[2].point == CGPoint(x: screen.maxX, y: screen.maxY))
        // Leaving Present hides the laser.
        await s.send(.presentLaser(on: true))
        await s.send(.modeSelected(.trackpad))
        #expect(s.present.laserLog.last?.visible == false)
    }

    // MARK: Macros

    @Test func macrosListAndRunTheStarterButtons() async throws {
        let s = try await PhoneSession(seedMacros: true)
        defer { s.close() }
        let harness = try #require(s.macros)
        let listed = await s.send(.modeSelected(.macros)) { if case .macro(.macroList) = $0 { true } else { false } }
        guard case .macro(.macroList(let active, let all))? = listed else { Issue.record("no macro list"); return }
        #expect(all.count == StarterLibrary.macros.count)
        #expect(active.name == "Finder")
        #expect(!active.macros.isEmpty)

        let again = await s.send(.macro(.listMacros)) { if case .macro(.macroList) = $0 { true } else { false } }
        #expect(again != nil)

        // Finder's New Folder is shift+cmd+N.
        let newFolder = try #require(StarterLibrary.macros.first { $0.name == "New Folder" })
        let done = await s.send(.macro(.run(macroID: newFolder.id)), timeout: 5) {
            if case .macro(.runFinished(newFolder.id, _, _, _)) = $0 { true } else { false }
        }
        guard case .macro(.runFinished(_, let outcome, let message, _))? = done else { Issue.record("no run result"); return }
        #expect(outcome == .completed, "\(message ?? "")")
        let downs = harness.poster.events.filter { $0.type == .keyDown }
        #expect(downs.last?.getIntegerValueField(.keyboardEventKeycode) == 45)
        #expect(downs.last?.flags.contains([.maskCommand, .maskShift]) == true)

        // Unknown macro: fails in words, the session stays.
        let ghost = UUID()
        let failed = await s.send(.macro(.run(macroID: ghost))) {
            if case .macro(.runFinished(ghost, _, _, _)) = $0 { true } else { false }
        }
        guard case .macro(.runFinished(_, .failed, _, _))? = failed else { Issue.record("ghost macro ran"); return }
        await s.send(.macro(.cancelRun))
        await s.send(.macro(.gesture(name: "fourFingerTap")))
        #expect(s.server.stats.malformed == 0)
        #expect(s.client.state == .connected(rttMs: nil))
    }

    // MARK: Remote

    @Test func remoteRunsOneTapControlsAndRefusesTheRiskyOnes() async throws {
        let s = try await PhoneSession()
        defer { s.close() }
        let front = await s.send(.modeSelected(.remote)) { isCase($0, "frontmostApp") }
        #expect(front == .frontmostApp(bundleID: "com.apple.Safari"))
        #expect(await eventually { s.inbox.messages.contains { isCase($0, "mediaState") } })

        for action in DeckSystemAction.allCases {
            let id = UUID()
            let runs = s.env.runs.count
            let r = await s.result(.remoteSystem(id: id, action: action), id: id)
            if action.needsConfirmation {
                // Refused, with a reason in words (the wording belongs to the Mac side).
                #expect(r?.ok == false && r?.message?.isEmpty == false, "\(action)")
                #expect(s.env.runs.count == runs, "\(action) ran from the remote")
            } else {
                #expect(r?.message != "Not built yet", "\(action) is not built on the Mac")
                #expect(r?.ok == true, "\(action): \(r?.message ?? "no answer")")
            }
        }
        #expect(!s.env.runs.contains { $0.1 == ["sleepnow"] })
        #expect(!s.env.runs.contains { $0.1.last?.contains("empty trash") == true })

        // The remote's own buttons are plain keys and media commands.
        let keymap = RemoteKeymap(player: .browser(.youtube))
        for action in RemoteAction.allCases {
            guard let out = keymap.output(action) else { continue }
            for m in RemoteKeymap.message(for: out, position: 30, canSeek: true, duration: 100) { await s.send(m) }
        }
        #expect(!s.poster.events.isEmpty)
        #expect(s.server.stats.malformed == 0)
    }

    // MARK: Displays

    @Test func displaysWatchMoveWindowsAndChangeDisplays() async throws {
        let s = try await PhoneSession()
        defer { s.close() }
        let fake = FakeDisplays()
        s.router.displays = DisplaysMode(backend: fake)
        await s.send(.modeSelected(.displays))
        let first = await s.send(.displaysWatch(on: true)) { isCase($0, "displaysState") }
        guard case .displaysState(let state)? = first else { Issue.record("no displays state"); return }
        #expect(state.displays.count == 2 && state.windows.count == 2)

        func run(_ m: ModeMessage, _ id: UUID) async -> (ok: Bool, message: String?)? {
            let r = await s.send(m) { if case .displaysResult(id, _, _) = $0 { true } else { false } }
            guard case .displaysResult(_, let ok, let text)? = r else { return nil }
            return (ok, text)
        }
        let commands: [WindowCommand] = [.raise, .split(with: 101), .move(display: 2, origin: nil),
                                         .move(display: 1, origin: CGPoint(x: 10, y: 40)), .minimize, .fullScreen, .close]
            + WindowTile.allCases.map(WindowCommand.tile)
        // Each command answers for its own id.
        for c in commands {
            let id = UUID()
            let r = await run(.windowCommand(id: id, windowID: 100, command: c), id)
            #expect(r?.ok == true, "\(c): \(r?.message ?? "no answer")")
        }
        #expect(!fake.operations.isEmpty)
        let gone = UUID()
        #expect(await run(.windowCommand(id: gone, windowID: 999, command: .raise), gone)?.ok == false)

        let displayCommands: [DisplayCommand] = [
            .brightness(display: 1, value: 0.8), .makeMain(display: 2),
            .arrange([DisplayOrigin(display: 1, origin: .zero), DisplayOrigin(display: 2, origin: CGPoint(x: -2560, y: 0))]),
            .resolution(display: 1, id: 10), .keepChanges, .mirror(display: 2, of: 1), .revertChanges,
        ]
        for c in displayCommands {
            let id = UUID()
            let r = await run(.displayCommand(id: id, command: c), id)
            #expect(r?.ok == true, "\(c): \(r?.message ?? "no answer")")
        }
        #expect(fake.brightness.first?.1 == 0.8)
        #expect(fake.restored == 1)
        let missing = UUID()
        #expect(await run(.displayCommand(id: missing, command: .makeMain(display: 77)), missing)?.ok == false)
        await s.send(.displaysWatch(on: false))
        #expect(s.server.stats.malformed == 0)
    }

    // MARK: Layouts

    /// Several panes on screen: the phone reports one primary screen (`LayoutWirePlan`). Each
    /// pane must still get its live data from the Mac: the frontmost app for Dock, Actions and
    /// Remote, and Dock list pushes for Dock.
    @Test func layoutsTellTheMacEnoughForEveryPane() async throws {
        let s = try await PhoneSession()
        defer { s.close() }
        var app = 0
        func gaps(_ modes: [GlasspadMode]) async -> [String] {
            let plan = LayoutWirePlan(modes: modes)
            await s.send(.modeSelected(plan.primary))
            if let shown = plan.shown { await s.send(.modesShown(shown)) }
            if plan.requestsMedia {
                #expect(await s.send(.mediaRequest) { isCase($0, "mediaState") } != nil)
            }
            let start = s.inbox.messages.count
            app += 1
            let bundle = "com.example.app\(app)"
            s.router.workspaceChanged(activated: bundle, name: "App", url: nil)
            var missing: [String] = []
            let name = modes.map(\.rawValue).joined(separator: "+")
            if modes.contains(where: { [GlasspadMode.dock, .deck, .remote].contains($0) }) {
                let got = await eventually(0.5) { s.inbox.messages.dropFirst(start).contains(.frontmostApp(bundleID: bundle)) }
                if !got { missing.append("\(name): no frontmost app") }
            }
            if modes.contains(.dock) {
                let got = await eventually(1) { s.inbox.messages.dropFirst(start).contains { isCase($0, "dockList") } }
                if !got { missing.append("\(name): no Dock updates") }
            }
            return missing
        }
        // The built-in templates, with their phone mode names.
        // The phone's AppMode.wireMode: panes that need nothing from the Mac report as the trackpad.
        let wire: [String: GlasspadMode] = ["actions": .deck, "nowPlaying": .media, "clock": .trackpad, "calendar": .trackpad]
        for t in LayoutTemplate.builtIn {
            let modes = t.panes.compactMap { wire[$0] ?? GlasspadMode(rawValue: $0) }
            #expect(modes.count == t.panes.count, "\(t.id)")
            let missing = await gaps(modes)
            #expect(missing.isEmpty, "\(t.name): \(missing)")
        }
        // Any two panes the editor can put together.
        var pairGaps: [String] = []
        let all = GlasspadMode.allCases
        for (i, a) in all.enumerated() { for b in all[(i + 1)...] { pairGaps += await gaps([a, b]) } }
        #expect(pairGaps.isEmpty, "\(pairGaps)")
    }

    // MARK: Echoes and newer or older builds

    @Test func macToPhoneMessagesEchoedBackAreIgnored() async throws {
        let s = try await PhoneSession()
        defer { s.close() }
        let id = UUID()
        let echoes: [ModeMessage] = [
            .dockList(apps: []), .dockOpenResult(bundleID: "x", ok: true, message: nil), .dockCatalog(apps: []),
            .dockIcons(apps: []), .frontmostApp(bundleID: nil), .macDockState(MacDockState(hidden: true, hideWhileConnected: true)),
            .mediaState(MediaState()), .deckButtons([]), .deckResult(id: id, ok: true, message: nil),
            .deckLayout(DeckLayout(pages: [])), .deckSaveResult(ok: true, message: nil), .deckCatalog(DeckCatalog()),
            .deckImage(id: id, imageData: Data([1]), destination: .photos), .clipboardContent(nil),
            .clipboardPushResult(ok: true, message: nil), .clipboardPullRefused(message: "x"),
        ]
        for m in echoes { await s.send(m) }
        // Only the Dock state the first message of a session announces; nothing answers the echoes.
        let answers = s.inbox.messages.filter { !isCase($0, "macDockState") && !isCase($0, "dockCatalog") }
        #expect(answers.isEmpty, "\(answers.map(\.tag))")
        #expect(s.env.runs.isEmpty && s.env.opened.isEmpty)
        #expect(s.dockDefaults.writes == 0)
        #expect(await s.send(.dockRequest) { isCase($0, "dockList") } != nil)
    }

    /// The protocol's promise: a message this build does not know is dropped, and the session
    /// carries on. Both directions, through the real sealed channel.
    @Test func unknownMessagesFromOtherBuildsAreDroppedAndTheSessionLives() async throws {
        let s = try await PhoneSession()
        defer { s.close() }
        let id = UUID().uuidString
        let fromNewerPhones = [
            #"{"t":"mode","mode":{"t":"holographicDeck","depth":3}}"#,               // a whole new mode message
            #"{"t":"mode","mode":{"t":"remoteSystem","id":"\#(id)","action":"teleport"}}"#,   // a new Mac control
            #"{"t":"mode","mode":{"t":"modeSelected","mode":"hologram"}}"#,          // a new screen
            #"{"t":"mode","mode":{"t":"deckRun"}}"#,                                 // broken fields
            #"{"t":"somethingElse","x":1}"#,                                        // a new control message
        ]
        for json in fromNewerPhones {
            s.client.sendRawJSONForTesting(Data(json.utf8))
            #expect(await s.send(.dockRequest) { isCase($0, "dockList") } != nil, "session lost after \(json)")
        }
        #expect(s.server.stats.malformed == 4)          // the unknown control type is not even counted
        #expect(s.server.stats.authFailures == 0)
        #expect(s.client.state == .connected(rttMs: nil))
        #expect(s.env.runs.isEmpty)

        // Mac to phone: a newer Mac's messages never reach the phone's screens, and the next one does.
        let fromNewerMacs = [
            #"{"t":"mode","mode":{"t":"weather","sunny":true}}"#,
            #"{"t":"mode","mode":{"t":"deckResult","id":"\#(id)"}}"#,
            #"{"t":"aurora"}"#,
        ]
        for json in fromNewerMacs { s.server.sendRawJSONForTesting(Data(json.utf8)) }
        #expect(await s.send(.dockRequest) { isCase($0, "dockList") } != nil)
        #expect(!s.inbox.other.contains { if case .unknown = $0 { true } else { false } })
        #expect(s.client.state == .connected(rttMs: nil))
    }
}
