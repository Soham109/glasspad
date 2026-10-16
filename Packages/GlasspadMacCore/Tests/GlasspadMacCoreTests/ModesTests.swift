import AppKit
import Foundation
import GlasspadKit
import Testing
@testable import GlasspadMacCore

func tempURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("glasspad-tests-\(UUID().uuidString)/\(name)")
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

/// French AZERTY's letter and digit row as UCKeyTranslate reports it (key codes are US positions).
let azerty = KeyLayout(
    plain: ["a": 12, "z": 13, "e": 14, "r": 15, "q": 0, "s": 1, "d": 2, "w": 6, "x": 7, "c": 8, "v": 9,
            "m": 41, ",": 46, "&": 18, "é": 19, "\"": 20, "'": 21],
    shifted: ["A": 12, "Q": 0, "1": 18, "2": 19, "3": 20, "4": 21, "?": 46])

@Suite struct KeyboardLayoutTests {
    /// Reliability C1: on AZERTY the US "a" position types "q", so Select All became Cmd+Q
    /// (quit) and Undo became Cmd+W (close the window).
    @Test func azertyShortcutsPressTheKeyThatTypesTheLetter() throws {
        let selectAll = try #require(KeysMode.keyStroke(for: Keystroke(key: .character("a"), modifiers: [.command]), layout: azerty))
        #expect(selectAll.keyCode == 12 && selectAll.command && !selectAll.shift)
        let undo = try #require(KeysMode.keyStroke(for: Keystroke(key: .character("z"), modifiers: [.command]), layout: azerty))
        #expect(undo.keyCode == 13)
        let close = try #require(KeysMode.keyStroke(for: Keystroke(key: .character("w"), modifiers: [.command]), layout: azerty))
        #expect(close.keyCode == 6)
        let one = try #require(KeysMode.keyStroke(for: Keystroke(key: .character("1")), layout: azerty))
        #expect(one.keyCode == 18 && one.shift)      // digits are shifted on AZERTY
        let copy = try #require(KeysMode.keyStroke(for: Keystroke(key: .character("c"), modifiers: [.command]), layout: azerty))
        #expect(copy.keyCode == 8)
        // Named keys never move.
        #expect(KeysMode.keyStroke(for: Keystroke(key: .special(.left)), layout: azerty)?.keyCode == 123)
        #expect(KeysMode.keyStroke(for: Keystroke(key: .special(.f5)), layout: azerty)?.keyCode == 96)
    }

    @Test func keysModePostsTheActiveLayoutsKey() {
        let poster = CapturingEventPoster()
        KeysMode(poster: poster, source: nil, layout: { azerty }).press(Keystroke(key: .character("a"), modifiers: [.command]))
        let down = poster.events.first { $0.type == .keyDown }
        #expect(down?.getIntegerValueField(.keyboardEventKeycode) == 12)
        #expect(down?.flags.contains(.maskCommand) == true)
    }

    /// A layout without Latin letters (Russian, Greek): macOS matches Command shortcuts by US
    /// positions there, but plain typing must not press a US position (it would type Cyrillic).
    @Test func nonLatinLayoutUsesUSPositionsOnlyForShortcuts() throws {
        let russian = KeyLayout(plain: ["ф": 0, "с": 8, "й": 12], shifted: ["Ф": 0])
        let copy = try #require(KeysMode.keyStroke(for: Keystroke(key: .character("c"), modifiers: [.command]), layout: russian))
        #expect(copy.keyCode == 8)
        #expect(KeysMode.keyStroke(for: Keystroke(key: .character("c")), layout: russian) == nil)
        let poster = CapturingEventPoster()
        KeysMode(poster: poster, source: nil, layout: { russian }).press(Keystroke(key: .character("c")))
        #expect(KeyboardSynth.unicodeString(of: poster.events[0]) == "c")
    }
}

/// A pretend set of input sources: records switches, never touches the real ones.
final class FakeInputSources: InputSources {
    var selected: (id: String, composes: Bool)
    var log: [String] = []
    init(_ id: String, composes: Bool) { selected = (id, composes) }
    func current() -> (id: String, composes: Bool)? { selected }
    func selectASCIICapable() -> Bool {
        log.append("select ascii")
        selected = ("com.apple.keylayout.ABC", false)
        return true
    }
    func select(id: String) -> Bool {
        log.append("select \(id)")
        selected = (id, true)
        return true
    }
}

/// Posts nothing; notes each key event in the shared log so ordering can be checked.
final class LoggingPoster: EventPoster {
    let sources: FakeInputSources
    init(_ sources: FakeInputSources) { self.sources = sources }
    func post(_ event: CGEvent, tap: CGEventTapLocation, after delay: TimeInterval) {
        if event.type == .keyDown { sources.log.append("key \(KeyboardSynth.unicodeString(of: event))") }
    }
    func perform(_ action: SystemAction) {}
}

@Suite struct InputMethodTests {
    let kana = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"

    /// Reliability M2: with Japanese or Pinyin selected, typed text went into an uncommitted
    /// composition. Typing now goes through the ASCII layout and the input method comes back after.
    @Test func typingWithAnInputMethodSwitchesToASCIIThenRestores() {
        let sources = FakeInputSources(kana, composes: true)
        var pending: [() -> Void] = []
        let guardian = InputMethodGuard(sources: sources, restoreDelay: 0.5, after: { _, work in pending.append(work) })
        let keys = KeysMode(poster: LoggingPoster(sources), source: nil, inputMethods: guardian)
        keys.type("konnichiwa")
        keys.type(" sekai")
        #expect(sources.log == ["select ascii", "key konnichiwa", "key  sekai"])
        #expect(guardian.switchedFrom == kana)
        pending.first?()                     // the first burst's timer: superseded, does nothing
        #expect(sources.log.last == "key  sekai")
        pending.last?()                      // quiet for restoreDelay: put the input method back
        #expect(sources.log.last == "select \(kana)")
        #expect(guardian.switchedFrom == nil)
        #expect(sources.selected.id == kana)
    }

    @Test func plainLayoutIsLeftAlone() {
        let sources = FakeInputSources("com.apple.keylayout.French", composes: false)
        let guardian = InputMethodGuard(sources: sources, after: { _, _ in })
        KeysMode(poster: LoggingPoster(sources), source: nil, inputMethods: guardian).type("bonjour")
        #expect(sources.log == ["key bonjour"])
    }

    @Test func bareLetterKeystrokeIsGuardedButShortcutsAreNot() {
        let sources = FakeInputSources(kana, composes: true)
        let guardian = InputMethodGuard(sources: sources, after: { _, _ in })
        let keys = KeysMode(poster: LoggingPoster(sources), source: nil, inputMethods: guardian)
        keys.press(Keystroke(key: .character("c"), modifiers: [.command]))
        #expect(sources.log.allSatisfy { !$0.hasPrefix("select") })
        let before = sources.log.count
        keys.press(Keystroke(key: .character("k")))
        #expect(sources.log.dropFirst(before).first == "select ascii")
        guardian.restore()                   // session end puts it back at once
        #expect(sources.log.last == "select \(kana)")
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
    @Test func textAndImageRoundTrip() async throws {
        let pb = NSPasteboard(name: NSPasteboard.Name("glasspad-test-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let clip = ClipboardMode(pasteboard: pb)
        clip.push(.text("hello"))
        #expect(await clip.pull() == .text("hello"))
        let png = try #require(DockMode.renderPNG(NSImage(size: NSSize(width: 8, height: 8)), pixels: 8))
        clip.push(.imagePNG(png))
        if case .imagePNG(let d) = await clip.pull() { #expect(d == png) } else { Issue.record("expected image") }
        // The TIFF copy for apps that only read TIFF follows shortly.
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, pb.data(forType: .tiff) == nil { try await Task.sleep(for: .milliseconds(10)) }
        let tiff = try #require(pb.data(forType: .tiff))
        #expect(NSBitmapImageRep(data: tiff)?.pixelsWide == 8)
        #expect(pb.data(forType: .png) == png)
    }

    /// A TIFF-only clipboard (some apps) comes out as PNG.
    @Test func tiffIsPulledAsPNG() async throws {
        let pb = NSPasteboard(name: NSPasteboard.Name("glasspad-test-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let png = try #require(DockMode.renderPNG(NSImage(size: NSSize(width: 8, height: 8)), pixels: 8))
        pb.clearContents()
        pb.setData(try #require(NSImage(data: png)?.tiffRepresentation), forType: .tiff)
        guard case .imagePNG(let d) = await ClipboardMode(pasteboard: pb).pull() else { Issue.record("expected image"); return }
        #expect(NSBitmapImageRep(data: d)?.pixelsWide == 8)
    }

    /// A big screenshot on the Mac clipboard used to go out whole: over the phone's frame limit,
    /// so pulling it dropped the connection. It is scaled down until it fits one message.
    @Test func largeImageIsScaledToFitOneMessage() async throws {
        let pb = NSPasteboard(name: NSPasteboard.Name("glasspad-test-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        // Noise does not compress: 3 bytes per pixel, so 2100 x 2100 is about 13 MB.
        let side = 2100
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                                samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0))
        let bytes = try #require(rep.bitmapData)
        arc4random_buf(bytes, rep.bytesPerRow * side)
        let big = try #require(rep.representation(using: .png, properties: [:]))
        #expect(big.count > ClipboardContent.maxImageBytes)
        pb.clearContents()
        pb.setData(big, forType: .png)
        // The shrinking runs off the main thread: the main actor keeps running meanwhile.
        let clip = ClipboardMode(pasteboard: pb)
        let pull = Task { await clip.pull() }
        var mainTurns = 0
        let ticker = Task { @MainActor in
            while !Task.isCancelled { mainTurns += 1; try? await Task.sleep(for: .milliseconds(5)) }
        }
        let result = await pull.value
        ticker.cancel()
        #expect(mainTurns > 5)
        guard case .imagePNG(let d) = result else { Issue.record("expected image"); return }
        // Reliability M1: small enough to arrive inside the phone's silence timeout on slow Wi-Fi.
        #expect(d.count <= ClipboardLimits.maxImageBytes)
        let out = try #require(NSBitmapImageRep(data: d))
        #expect(out.pixelsWide < side && out.pixelsWide > 0)
    }

    /// Reliability M1: huge text had no cap; it is refused whole with a reason, never cut.
    @Test func hugeTextIsRefusedWithAReason() async {
        let pb = NSPasteboard(name: NSPasteboard.Name("glasspad-test-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let clip = ClipboardMode(pasteboard: pb)
        let huge = String(repeating: "x", count: ClipboardLimits.maxTextBytes + 1)
        clip.push(.text(huge))
        #expect(await clip.pullResult() == .tooLarge(bytes: huge.utf8.count))
        #expect(await clip.pull() == nil)
        #expect(clip.lastRefusal?.contains("MB") == true)
        let fits = String(repeating: "y", count: ClipboardLimits.maxTextBytes)
        clip.push(.text(fits))
        #expect(await clip.pull() == .text(fits))
        #expect(clip.lastRefusal == nil)
        // Counted in UTF-8 bytes: multi-byte text hits the cap with fewer characters.
        #expect(ClipboardMode.checkText(String(repeating: "é", count: ClipboardLimits.maxTextBytes / 2 + 1))
                == .tooLarge(bytes: ClipboardLimits.maxTextBytes + 2))
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
