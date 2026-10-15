import CoreGraphics
import GlasspadKit

/// Keys mode: streamed text as unicode key events, and keystrokes with modifiers.
public final class KeysMode {
    private let poster: EventPoster
    private let source: CGEventSource?

    public init(poster: EventPoster, source: CGEventSource? = EventSynthesizer.makeSource()) {
        self.poster = poster
        self.source = source
    }

    public func type(_ text: String) {
        // Newlines are sent as Return so text fields and terminals behave.
        var pending = ""
        func flush() {
            guard !pending.isEmpty else { return }
            KeyboardSynth.unicodeEvents(for: pending, source: source).forEach { poster.post($0) }
            pending = ""
        }
        for ch in text {
            if ch == "\n" || ch == "\r\n" {
                flush()
                press(KeyStroke(.returnKey))
            } else {
                pending.append(ch)
            }
        }
        flush()
    }

    public func press(_ keystroke: Keystroke) {
        if let stroke = Self.keyStroke(for: keystroke) {
            press(stroke)
        } else if case .character(let s) = keystroke.key {
            // No key code for this character on a US layout: type it as unicode.
            type(s)
        }
    }

    public func press(_ stroke: KeyStroke) {
        KeyboardSynth.events(for: stroke, source: source).forEach { poster.post($0) }
    }

    /// Maps the kit's `Keystroke` to a virtual key code + flags. Characters use the US ANSI
    /// layout; a non-US layout may place some punctuation on other keys.
    public static func keyStroke(for k: Keystroke) -> KeyStroke? {
        let code: UInt16
        var shift = k.modifiers.contains(.shift)
        switch k.key {
        case .special(let s): code = specialCodes[s]!
        case .character(let s):
            guard s.count == 1, let ch = s.first else { return nil }
            if let c = ansiCodes[ch] {
                code = c
            } else if let c = shiftedANSI[ch] {
                code = c
                shift = true
            } else if let lower = ch.lowercased().first, ch.isUppercase, let c = ansiCodes[lower] {
                code = c
                shift = true
            } else {
                return nil
            }
        }
        return KeyStroke(keyCode: code, command: k.modifiers.contains(.command), option: k.modifiers.contains(.option),
                         control: k.modifiers.contains(.control), shift: shift, function: k.modifiers.contains(.function))
    }

    static let specialCodes: [SpecialKey: UInt16] = [
        .returnKey: 36, .tab: 48, .space: 49, .delete: 51, .forwardDelete: 117, .escape: 53,
        .left: 123, .right: 124, .down: 125, .up: 126, .home: 115, .end: 119, .pageUp: 116, .pageDown: 121,
    ]

    /// kVK_ANSI_* codes (HIToolbox Events.h).
    static let ansiCodes: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41,
        "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50, " ": 49,
    ]

    static let shiftedANSI: [Character: UInt16] = [
        "!": 18, "@": 19, "#": 20, "$": 21, "^": 22, "%": 23, "+": 24, "(": 25, "&": 26, "_": 27, "*": 28, ")": 29,
        "}": 30, "{": 33, "\"": 39, ":": 41, "|": 42, "<": 43, "?": 44, ">": 47, "~": 50,
    ]
}
