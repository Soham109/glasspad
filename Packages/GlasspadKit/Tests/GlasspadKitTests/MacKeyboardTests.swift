import CoreGraphics
import Foundation
import Testing
@testable import GlasspadKit

@Suite("Glasspad keyboard")
struct MacKeyboardTests {
    // MARK: Layout model

    @Test func everyRowOfAStyleIsTheSameWidth() {
        for style in [KeyboardStyle.wide, .narrow, .short] {
            for symbols in [false, true] {
                for fn in [false, true] {
                    let rows = MacKeyboard.rows(style, .init(symbols: symbols, functionKeys: fn))
                    let expected = style == .wide ? 14.5 : 10
                    for row in rows { #expect(abs(row.units - expected) < 0.001, "\(style) \(symbols) \(fn) \(row.units)") }
                }
            }
        }
    }

    @Test func wideIsAMacKeyboard() {
        let rows = MacKeyboard.rows(.wide)
        #expect(rows.count == 5)
        let kinds = rows.flatMap(\.keys).map(\.kind)
        // Every character key of the Mac, once.
        for code in KeyboardLetters.allPositions { #expect(kinds.filter { $0 == .character(code) }.count == 1) }
        for special: SpecialKey in [.tab, .delete, .returnKey, .space, .left, .right, .up, .down] {
            #expect(kinds.contains(.special(special)))
        }
        #expect(kinds.contains(.capsLock))
        #expect(kinds.filter { $0 == .modifier(.shift) }.count == 2)
        #expect(kinds.filter { $0 == .modifier(.command) }.count == 2)
        #expect(kinds.contains(.modifier(.control)) && kinds.contains(.modifier(.function)))
        // Two keys of the same kind still have their own identity.
        let ids = rows.flatMap(\.keys).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func fnTurnsTheTopRowIntoFKeys() {
        let wide = MacKeyboard.rows(.wide, .init(functionKeys: true))[0].keys.map(\.kind)
        #expect(wide.first == .special(.escape))
        #expect(wide.contains(.special(.f1)) && wide.contains(.special(.f12)))
        let narrow = MacKeyboard.rows(.narrow, .init(functionKeys: true))[0].keys.map(\.kind)
        #expect(narrow.count == 12 && narrow.last == .special(.f12))
    }

    @Test func narrowLettersAndSymbolsTogetherHaveEveryCharacterKey() {
        let letters = MacKeyboard.rows(.narrow).flatMap(\.keys).map(\.kind)
        let symbols = MacKeyboard.rows(.narrow, .init(symbols: true)).flatMap(\.keys).map(\.kind)
        for code in KeyboardLetters.allPositions {
            #expect(letters.contains(.character(code)) || symbols.contains(.character(code)), "key \(code)")
        }
        // The Mac keys under the space bar.
        for kind: KeyboardKeyKind in [.special(.escape), .special(.tab), .modifier(.function), .modifier(.control),
                                      .modifier(.option), .modifier(.command), .special(.up)] {
            #expect(letters.contains(kind))
        }
    }

    @Test func shortKeepsEscCommandAndArrows() {
        let rows = MacKeyboard.rows(.short)
        #expect(rows.count == 4)
        let kinds = rows.flatMap(\.keys).map(\.kind)
        for kind: KeyboardKeyKind in [.special(.escape), .modifier(.command), .special(.left), .special(.up),
                                      .special(.down), .special(.right), .special(.returnKey), .special(.delete)] {
            #expect(kinds.contains(kind))
        }
    }

    @Test func onlyEditingAndMovingKeysRepeat() {
        #expect(KeyboardKeyKind.special(.delete).repeats)
        #expect(KeyboardKeyKind.special(.left).repeats)
        #expect(KeyboardKeyKind.special(.space).repeats)
        #expect(!KeyboardKeyKind.special(.returnKey).repeats)
        #expect(!KeyboardKeyKind.special(.escape).repeats)
        #expect(!KeyboardKeyKind.character(0).repeats)
        #expect(!KeyboardKeyKind.modifier(.shift).repeats)
    }

    // MARK: Geometry

    @Test func keysFillTheWidthWithEvenGaps() {
        let size = CGSize(width: 390, height: 230)
        let placed = MacKeyboard.place(MacKeyboard.rows(.narrow), in: size, gap: 6)
        let top = placed.filter { $0.row == 0 }
        #expect(abs(top.first!.frame.minX) < 0.01)
        #expect(abs(top.last!.frame.maxX - 390) < 0.01)
        for (a, b) in zip(top, top.dropFirst()) { #expect(abs(b.frame.minX - a.frame.maxX - 6) < 0.01) }
        #expect(abs(placed.map(\.frame.maxY).max()! - 230) < 0.01)
        // The home row is indented half a key on each side.
        let home = placed.filter { $0.row == 1 }
        #expect(home.first!.frame.minX > top.first!.frame.minX + 10)
    }

    @Test func stackedArrowsShareOneSlot() {
        let placed = MacKeyboard.place(MacKeyboard.rows(.wide), in: CGSize(width: 740, height: 270), gap: 6)
        let up = placed.first { $0.key.kind == .special(.up) }!.frame
        let down = placed.first { $0.key.kind == .special(.down) }!.frame
        #expect(up.minX == down.minX && up.maxY < down.minY)
        let right = placed.first { $0.key.kind == .special(.right) }!.frame
        #expect(abs(right.maxX - 740) < 0.01)
    }

    @Test func gapsAndRowEndsStillHitAKey() {
        let gap: CGFloat = 6
        let placed = MacKeyboard.place(MacKeyboard.rows(.narrow), in: CGSize(width: 390, height: 230), gap: gap)
        let q = placed.first { $0.key.kind == .character(12) }!
        let w = placed.first { $0.key.kind == .character(13) }!
        // Between Q and W: whichever is nearer.
        let between = CGPoint(x: q.frame.maxX + 2, y: q.frame.midY)
        #expect(MacKeyboard.key(at: between, in: placed, gap: gap)?.key.kind == .character(12))
        #expect(MacKeyboard.key(at: CGPoint(x: w.frame.minX - 2, y: w.frame.midY), in: placed, gap: gap)?.key.kind == .character(13))
        // The indent left of A types A.
        let a = placed.first { $0.key.kind == .character(0) }!
        #expect(MacKeyboard.key(at: CGPoint(x: 2, y: a.frame.midY), in: placed, gap: gap)?.key.kind == .character(0))
        // Outside the keyboard: nothing.
        #expect(MacKeyboard.key(at: CGPoint(x: 100, y: -40), in: placed, gap: gap) == nil)
    }

    // MARK: Sizing

    @Test func fullScreenPortraitHasEveryKeyAndRoomToRead() {
        let p = KeyboardPlan.make(width: 402, height: 780)
        #expect(p.fit == .full && p.style == .narrow && p.rows == 5)
        #expect(p.pitch == KeyboardPlan.maxPitch)
        #expect(p.echoHeight > 200)
    }

    @Test func landscapeFullScreenIsTheWholeMacKeyboard() {
        let p = KeyboardPlan.make(width: 750, height: 330)
        #expect(p.style == .wide && p.fit == .full)
        #expect(p.pitch >= KeyboardPlan.minPitch)
        #expect(p.keyboardHeight <= 330)
    }

    @Test func keysAreNeverTooSmallToHit() {
        for width in stride(from: 200.0, through: 900, by: 50) {
            for height in stride(from: 100.0, through: 900, by: 7) {
                let p = KeyboardPlan.make(width: width, height: height)
                guard p.fit != .tooSmall else { continue }
                #expect(p.pitch >= KeyboardPlan.minPitch)
                #expect(p.pitch - KeyboardPlan.gap >= KeyboardPlan.minKeyHeight)
                #expect(p.keyboardHeight + p.echoHeight <= height + 0.01, "\(width)x\(height)")
            }
        }
    }

    @Test func shortPanesGetTheShortKeyboardThenANote() {
        // A third of a portrait screen under the pill.
        let third = KeyboardPlan.make(width: 402, height: 225)
        #expect(third.fit == .short && third.style == .short && third.rows == 4)
        let half = KeyboardPlan.make(width: 402, height: 380)
        #expect(half.fit == .full)
        let tiny = KeyboardPlan.make(width: 402, height: 150)
        #expect(tiny.fit == .tooSmall)
    }

    // MARK: Modifiers

    @Test func tapLatchesForOneKey() {
        var m = KeyboardModifierState()
        m.down(.command)
        #expect(m.state(of: .command) == .held)
        m.up(.command, at: 1)
        #expect(m.state(of: .command) == .latched)
        #expect(m.consume() == .command)
        #expect(m.isEmpty)
    }

    @Test func doubleTapLocks() {
        var m = KeyboardModifierState()
        m.down(.shift); m.up(.shift, at: 1)
        m.down(.shift); m.up(.shift, at: 1.2)
        #expect(m.state(of: .shift) == .locked)
        _ = m.consume()
        #expect(m.capitals)
    }

    @Test func holdingIsAChordThatLetsGo() {
        var m = KeyboardModifierState()
        m.down(.command)
        #expect(m.consume() == .command)
        #expect(m.consume() == .command)      // still held: still applies
        m.up(.command, at: 2)
        #expect(m.state(of: .command) == .off) // used as a chord, so no latch
        #expect(m.consume() == [])
    }

    @Test func heldAndLatchedCombine() {
        var m = KeyboardModifierState()
        m.down(.shift); m.up(.shift, at: 0)
        m.down(.command)
        #expect(m.consume() == [.command, .shift])
        #expect(m.state(of: .shift) == .off)
    }

    @Test func cancelledTouchesDoNotLatch() {
        var m = KeyboardModifierState()
        m.down(.option)
        m.releaseHeld()
        m.up(.option, at: 1)
        #expect(m.isEmpty)
    }

    // MARK: Output

    private func out(_ kind: KeyboardKeyKind, _ mods: KeyModifiers = [], caps: Bool = false,
                     _ letters: KeyboardLetters = .us) -> ModeMessage? {
        KeyboardOutput.message(for: kind, modifiers: mods, capsLock: caps, letters: letters)
    }

    @Test func lettersTypeAsText() {
        #expect(out(.character(0)) == .keysText("a"))
        #expect(out(.character(0), .shift) == .keysText("A"))
        #expect(out(.character(18), .shift) == .keysText("!"))
        #expect(out(.character(0), caps: true) == .keysText("A"))
        #expect(out(.character(18), caps: true) == .keysText("1"))  // Caps Lock leaves numbers alone
        #expect(out(.character(0), .shift, caps: true) == .keysText("a"))
    }

    @Test func shortcutsAreKeystrokesOnTheBaseCharacter() {
        #expect(out(.character(8), .command) == .keysKeystroke(Keystroke(key: .character("c"), modifiers: .command)))
        #expect(out(.character(6), [.command, .shift]) == .keysKeystroke(Keystroke(key: .character("z"), modifiers: [.command, .shift])))
        #expect(out(.character(14), .option) == .keysKeystroke(Keystroke(key: .character("e"), modifiers: .option)))
    }

    @Test func theMacsLayoutDecidesTheCharacter() {
        // AZERTY: the key in the Q position types "a".
        let azerty = KeyboardLetters.from(plain: [12: "a", 0: "q", 13: "z", 6: "w", 18: "&"], shifted: [12: "A", 0: "Q", 18: "1"])
        #expect(out(.character(12), [], azerty) == .keysText("a"))
        #expect(out(.character(18), .shift, azerty) == .keysText("1"))
        #expect(out(.character(13), .command, azerty) == .keysKeystroke(Keystroke(key: .character("z"), modifiers: .command)))
        // Positions it did not send stay US.
        #expect(azerty.cap(1) == KeyCap("s", "S"))
    }

    @Test func specialKeysAndFn() {
        #expect(out(.special(.space)) == .keysText(" "))
        #expect(out(.special(.space), .command) == .keysKeystroke(Keystroke(key: .special(.space), modifiers: .command)))
        #expect(out(.special(.left), .function) == .keysKeystroke(Keystroke(key: .special(.home))))
        #expect(out(.special(.down), [.function, .shift]) == .keysKeystroke(Keystroke(key: .special(.pageDown), modifiers: .shift)))
        #expect(out(.special(.delete), .function) == .keysKeystroke(Keystroke(key: .special(.forwardDelete))))
        #expect(out(.special(.f5), .function) == .keysKeystroke(Keystroke(key: .special(.f5))))
        #expect(out(.special(.tab), .command) == .keysKeystroke(Keystroke(key: .special(.tab), modifiers: .command)))
        #expect(out(.modifier(.shift)) == nil)
        #expect(out(.symbols) == nil)
    }

    @Test func echoFollowsTyping() {
        var e = ""
        e = KeyboardOutput.echo(e, after: .keysText("Hi"))
        e = KeyboardOutput.echo(e, after: .keysText(" there"))
        e = KeyboardOutput.echo(e, after: .keysKeystroke(Keystroke(key: .special(.delete))))
        #expect(e == "Hi ther")
        e = KeyboardOutput.echo(e, after: .keysKeystroke(Keystroke(key: .character("a"), modifiers: .command)))
        #expect(e == "Hi ther")
        e = KeyboardOutput.echo(e, after: .keysKeystroke(Keystroke(key: .special(.returnKey))))
        #expect(e.isEmpty)
        #expect(KeyboardOutput.echo(String(repeating: "x", count: 300), after: .keysText("y"), limit: 10).count == 10)
    }

    // MARK: Wire

    @Test func layoutMessageRoundTrips() throws {
        let letters = KeyboardLetters.from(plain: [12: "a", 0: "q"], shifted: [12: "A"])
        let data = try JSONEncoder().encode(ModeMessage.keysLayout(letters))
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains(#""t":"keysLayout""#))
        #expect(try JSONDecoder().decode(ModeMessage.self, from: data) == .keysLayout(letters))
        // Inside a control message, as the Mac sends it.
        let control = try ControlMessage.mode(.keysLayout(letters)).jsonData()
        #expect(try ControlMessage.from(jsonData: control) == .mode(.keysLayout(letters)))
    }

    @Test func usLettersAreComplete() {
        for code in KeyboardLetters.allPositions { #expect(!KeyboardLetters.us.cap(code).base.isEmpty) }
        #expect(KeyboardLetters.us.cap(42) == KeyCap("\\", "|"))
        #expect(KeyboardLetters.allPositions.count == 47)
    }
}
