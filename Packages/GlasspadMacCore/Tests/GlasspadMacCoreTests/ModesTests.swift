import AppKit
import Foundation
import GlasspadKit
import Testing
@testable import GlasspadMacCore

final class FakeDeckEnvironment: DeckEnvironment {
    var opened: [String] = []
    var urls: [URL] = []
    var runs: [(String, [String])] = []
    var pressed: [Keystroke] = []
    func openApp(bundleID: String) -> Bool { opened.append(bundleID); return bundleID != "missing" }
    func open(url: URL) -> Bool { urls.append(url); return true }
    func run(executable: String, arguments: [String]) -> (ok: Bool, output: String) { runs.append((executable, arguments)); return (true, "") }
    func press(_ keystroke: Keystroke) { pressed.append(keystroke) }
}

func tempURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("glasspad-tests-\(UUID().uuidString)/\(name)")
}

@Suite @MainActor struct DeckTests {
    @Test func configRoundTrip() throws {
        let url = tempURL("deck.json")
        let cfg = DeckConfig(allowShellCommands: true, buttons: [
            DeckButton(title: "App", symbol: "app", action: .openApp(bundleID: "com.apple.Notes")),
            DeckButton(title: "URL", symbol: "link", action: .openURL("https://example.com")),
            DeckButton(title: "Shortcut", symbol: "bolt", action: .runShortcut(name: "Focus")),
            DeckButton(title: "Key", symbol: "keyboard", action: .keystroke(Keystroke(key: .special(.left), modifiers: [.command]))),
            DeckButton(title: "Shell", symbol: "terminal", action: .shellScript("echo hi")),
        ])
        try cfg.save(to: url)
        #expect(DeckConfig.load(from: url) == cfg)
    }

    @Test func missingOrCorruptConfigGivesStarterSet() throws {
        let url = tempURL("deck.json")
        #expect(DeckConfig.load(from: url) == DeckConfig())
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{nope".utf8).write(to: url)
        #expect(DeckConfig.load(from: url).allowShellCommands == false)
    }

    @Test func actionsRunThroughEnvironment() throws {
        let url = tempURL("deck.json")
        let key = Keystroke(key: .character("c"), modifiers: [.command])
        let buttons = [
            DeckButton(title: "A", symbol: "a", action: .openApp(bundleID: "com.apple.Notes")),
            DeckButton(title: "U", symbol: "u", action: .openURL("https://example.com")),
            DeckButton(title: "S", symbol: "s", action: .runShortcut(name: "Focus")),
            DeckButton(title: "K", symbol: "k", action: .keystroke(key)),
        ]
        try DeckConfig(buttons: buttons).save(to: url)
        let env = FakeDeckEnvironment()
        let deck = DeckMode(env: env, url: url)
        for b in buttons { #expect(deck.run(id: b.id) == .deckResult(id: b.id, ok: true, message: nil)) }
        #expect(env.opened == ["com.apple.Notes"])
        #expect(env.urls == [URL(string: "https://example.com")!])
        #expect(env.runs.first?.0 == "/usr/bin/shortcuts")
        #expect(env.runs.first?.1 == ["run", "Focus"])
        #expect(env.pressed == [key])
    }

    @Test func shellNeedsExplicitOptIn() throws {
        let url = tempURL("deck.json")
        let shell = DeckButton(title: "Sh", symbol: "terminal", action: .shellScript("touch /tmp/x"))
        try DeckConfig(allowShellCommands: false, buttons: [shell]).save(to: url)
        let env = FakeDeckEnvironment()
        let deck = DeckMode(env: env, url: url)
        if case .deckResult(_, let ok, let msg) = deck.run(id: shell.id) {
            #expect(!ok)
            #expect(msg?.contains("off") == true)
        }
        #expect(env.runs.isEmpty)

        var cfg = deck.config
        cfg.allowShellCommands = true
        try deck.update(cfg)
        #expect(deck.run(id: shell.id) == .deckResult(id: shell.id, ok: true, message: nil))
        #expect(env.runs.first?.0 == "/bin/zsh")
    }

    @Test func unknownButtonAndFileURLsAreRefused() throws {
        let url = tempURL("deck.json")
        let file = DeckButton(title: "F", symbol: "doc", action: .openURL("file:///Applications/Calculator.app"))
        try DeckConfig(buttons: [file]).save(to: url)
        let deck = DeckMode(env: FakeDeckEnvironment(), url: url)
        let unknown = UUID()
        #expect(deck.run(id: unknown) == .deckResult(id: unknown, ok: false, message: "Button not found"))
        if case .deckResult(_, let ok, _) = deck.run(id: file.id) { #expect(!ok) }
    }
}

@Suite struct KeysTests {
    @Test func unicodeTypingChunksWithoutSplittingSurrogates() {
        let text = String(repeating: "a", count: 19) + "😀" + "bc"
        let events = KeyboardSynth.unicodeEvents(for: text, source: nil)
        let downs = events.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
        let joined = downs.map(KeyboardSynth.unicodeString(of:)).joined()
        #expect(joined == text)
        #expect(downs.count == 2)
        #expect(events.count == 4)
    }

    @Test func typingNewlineSendsReturn() {
        let poster = CapturingEventPoster()
        KeysMode(poster: poster, source: nil).type("hi\nyo")
        let codes = poster.events.filter { $0.type == .keyDown }.map { $0.getIntegerValueField(.keyboardEventKeycode) }
        #expect(codes.contains(36))
        #expect(poster.events.count == 6)
    }

    @Test func keystrokeMapping() throws {
        let cmdC = try #require(KeysMode.keyStroke(for: Keystroke(key: .character("c"), modifiers: [.command])))
        #expect(cmdC.keyCode == 8 && cmdC.command && !cmdC.shift)
        let shiftedQuestion = try #require(KeysMode.keyStroke(for: Keystroke(key: .character("?"))))
        #expect(shiftedQuestion.keyCode == 44 && shiftedQuestion.shift)
        let upperA = try #require(KeysMode.keyStroke(for: Keystroke(key: .character("A"))))
        #expect(upperA.keyCode == 0 && upperA.shift)
        let esc = try #require(KeysMode.keyStroke(for: Keystroke(key: .special(.escape))))
        #expect(esc.keyCode == 53)
        #expect(KeysMode.keyStroke(for: Keystroke(key: .character("é"))) == nil)
        for k in SpecialKey.allCases { #expect(KeysMode.keyStroke(for: Keystroke(key: .special(k))) != nil) }
    }

    @Test func keystrokeEventsCarryFlags() {
        let events = KeyboardSynth.events(for: KeyStroke(.left, control: true), source: nil)
        #expect(events.count == 2)
        #expect(events[0].type == .keyDown && events[1].type == .keyUp)
        #expect(events[0].flags.contains(.maskControl))
        #expect(events[0].getIntegerValueField(.keyboardEventKeycode) == 123)
    }

    @Test func unmappedCharacterFallsBackToUnicode() {
        let poster = CapturingEventPoster()
        KeysMode(poster: poster, source: nil).press(Keystroke(key: .character("é")))
        #expect(KeyboardSynth.unicodeString(of: poster.events[0]) == "é")
    }
}

@Suite struct DockModeTests {
    let sample: [[String: Any]] = [
        ["tile-data": ["bundle-identifier": "com.microsoft.Word", "file-label": "Microsoft Word",
                       "file-data": ["_CFURLString": "file:///Applications/Microsoft%20Word.app/", "_CFURLStringType": 15]],
         "tile-type": "file-tile"],
        ["tile-data": ["file-label": "Spacer"], "tile-type": "spacer-tile"],
        ["tile-data": ["bundle-identifier": "com.apple.apps.launcher", "file-label": "Apps"], "tile-type": "file-tile"],
    ]

    @Test func parsesPersistentApps() {
        let entries = DockMode.parsePersistentApps(sample)
        #expect(entries.map(\.bundleID) == ["com.microsoft.Word", "com.apple.apps.launcher"])
        #expect(entries[0].name == "Microsoft Word")
        #expect(entries[0].url?.path == "/Applications/Microsoft Word.app")
        #expect(DockMode.parsePersistentApps(nil).isEmpty)
    }

    @Test func mergeKeepsDockOrderThenRunning() {
        let dock = DockMode.parsePersistentApps(sample)
        let running = [
            DockMode.RunningApp(bundleID: "com.apple.Terminal", name: "Terminal", url: nil, active: true),
            DockMode.RunningApp(bundleID: "com.microsoft.Word", name: "Word", url: nil, active: false),
        ]
        let merged = DockMode.merge(dock: dock, running: running)
        #expect(merged.map(\.entry.bundleID) == ["com.microsoft.Word", "com.apple.apps.launcher", "com.apple.Terminal"])
        #expect(merged.map(\.running) == [true, false, true])
        #expect(merged.map(\.active) == [false, false, true])
    }

    @Test func rendersExact64PixelPNG() throws {
        let image = NSImage(size: NSSize(width: 512, height: 512))
        let png = try #require(DockMode.renderPNG(image, pixels: 64))
        let rep = try #require(NSBitmapImageRep(data: png))
        #expect(rep.pixelsWide == 64 && rep.pixelsHigh == 64)
    }
}

@Suite struct PresentTests {
    @Test func laserPointConvertsTopLeftToAppKit() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 500)
        #expect(PresentMode.screenPoint(x: 0, y: 0, screen: screen) == CGPoint(x: 0, y: 500))
        #expect(PresentMode.screenPoint(x: 0.5, y: 1, screen: screen) == CGPoint(x: 500, y: 0))
        #expect(PresentMode.screenPoint(x: 2, y: -1, screen: screen) == CGPoint(x: 1000, y: 500))
    }

    @Test func mediaKeyEventsAreSystemDefined() {
        let events = MediaMode.mediaKeyEvents(16)
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.type.rawValue == 14 })   // NX_SYSDEFINED
    }
}

@Suite @MainActor struct ClipboardTests {
    @Test func textAndImageRoundTrip() throws {
        let pb = NSPasteboard(name: NSPasteboard.Name("glasspad-test-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let clip = ClipboardMode(pasteboard: pb)
        clip.push(.text("hello"))
        #expect(clip.pull() == .text("hello"))
        let png = try #require(DockMode.renderPNG(NSImage(size: NSSize(width: 8, height: 8)), pixels: 8))
        clip.push(.imagePNG(png))
        if case .imagePNG(let d) = clip.pull() { #expect(d == png) } else { Issue.record("expected image") }
    }
}

@Suite struct PairingStoreTests {
    @Test func macIDIsStableAndPairingFlows() throws {
        let secrets = InMemorySecretStore()
        let store = PairingStore(store: secrets)
        #expect(PairingStore(store: secrets).macID == store.macID)

        let payload = store.beginPairing(macName: "Test Mac")
        #expect(payload.macID == store.macID)
        #expect(payload.pairKey.count == 32)
        #expect(store.key(for: "phone-1") == payload.pairKey)

        try store.completePairing(phoneID: "phone-1", phoneName: "iPhone")
        #expect(store.pendingKey == nil)
        #expect(store.phones.map(\.phoneID) == ["phone-1"])
        #expect(store.key(for: "phone-1") == payload.pairKey)
        #expect(store.key(for: "stranger") == nil)

        try store.revoke("phone-1")
        #expect(store.phones.isEmpty)
        #expect(store.key(for: "phone-1") == nil)
    }

    @Test func completeWithoutPendingDoesNothing() throws {
        let store = PairingStore(store: InMemorySecretStore())
        #expect(try store.completePairing(phoneID: "x", phoneName: "y") == nil)
    }
}
