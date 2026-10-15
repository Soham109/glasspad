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

    /// A big screenshot on the Mac clipboard used to go out whole: over the phone's frame limit,
    /// so pulling it dropped the connection. It is scaled down until it fits one message.
    @Test func largeImageIsScaledToFitOneMessage() throws {
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
        guard case .imagePNG(let d) = ClipboardMode(pasteboard: pb).pull() else { Issue.record("expected image"); return }
        #expect(d.count <= ClipboardContent.maxImageBytes)
        let out = try #require(NSBitmapImageRep(data: d))
        #expect(out.pixelsWide < side && out.pixelsWide > 0)
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
