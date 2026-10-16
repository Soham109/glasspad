import CoreGraphics
import GlasspadKit
import Testing
@testable import GlasspadMacCore

@Suite("Function keys")
struct FunctionKeyTests {
    /// F1 to F12 from the phone's Fn row become the real virtual keys (kVK_F1 ... kVK_F12).
    @Test func fKeysMapToTheirVirtualKeyCodes() throws {
        let expected: [(SpecialKey, UInt16)] = [
            (.f1, 122), (.f2, 120), (.f3, 99), (.f4, 118), (.f5, 96), (.f6, 97),
            (.f7, 98), (.f8, 100), (.f9, 101), (.f10, 109), (.f11, 103), (.f12, 111),
        ]
        for (key, code) in expected {
            let stroke = try #require(KeysMode.keyStroke(for: Keystroke(key: .special(key), modifiers: [.shift])))
            #expect(stroke.keyCode == code, "\(key)")
            #expect(stroke.shift)
        }
        #expect(Set(expected.map(\.1)) == KeyboardSynth.functionKeyCodes)
    }

    /// Like a hardware keyboard, an F-key event carries the function flag (F11 Show Desktop is
    /// stored with it), and nothing else unless asked.
    @Test func fKeyEventsCarryTheFunctionFlag() {
        let events = KeyboardSynth.events(for: KeyStroke(keyCode: 103), source: nil)
        #expect(events.count == 2)
        for e in events {
            #expect(e.flags.contains(.maskSecondaryFn))
            #expect(!e.flags.contains(.maskNumericPad))
            #expect(!e.flags.contains(.maskCommand))
        }
        let letter = KeyboardSynth.events(for: KeyStroke(.a), source: nil)
        #expect(letter.allSatisfy { !$0.flags.contains(.maskSecondaryFn) })
    }
}
