import CoreGraphics
import GlasspadKit

/// Keys mode: streamed text as unicode key events, and keystrokes with modifiers. Also does
/// the key presses for Deck and Present.
///
/// Characters go through the Mac's active keyboard layout (`KeyLayout`), so shortcuts press the
/// key that types that character there; named keys (arrows, F-keys, Return) are fixed codes.
/// While an input method is selected, typing goes through the ASCII layout (`InputMethodGuard`).
public final class KeysMode {
    private let poster: EventPoster
    private let source: CGEventSource?
    private let layout: () -> KeyLayout
    private let inputMethods: InputMethodGuard?

    /// `layout` defaults to US ANSI and no input method handling, which is what tests want; the
    /// app uses `live(poster:)`.
    public init(poster: EventPoster, source: CGEventSource? = EventSynthesizer.makeSource(),
                layout: @escaping () -> KeyLayout = { .ansi }, inputMethods: InputMethodGuard? = nil) {
        self.poster = poster
        self.source = source
        self.layout = layout
        self.inputMethods = inputMethods
    }

    /// Follows the Mac's keyboard layout and input method.
    public static func live(poster: EventPoster) -> KeysMode {
        let layout = LiveKeyLayout()
        return KeysMode(poster: poster, layout: { layout.current() },
                        inputMethods: InputMethodGuard(sources: LiveInputSources()))
    }

    /// Puts back an input method switched away from for typing (session end, quit).
    public func restoreInputMethod() { inputMethods?.restore() }

    public func type(_ text: String) {
        guard !text.isEmpty else { return }
        inputMethods?.willType()
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
        if let stroke = Self.keyStroke(for: keystroke, layout: layout()) {
            // A bare character key would go into an input method's composition too.
            if case .character = keystroke.key, !stroke.command, !stroke.control { inputMethods?.willType() }
            press(stroke)
        } else if case .character(let s) = keystroke.key {
            // No key types this character on the Mac's layout: type it as unicode.
            type(s)
        }
    }

    public func press(_ stroke: KeyStroke) {
        KeyboardSynth.events(for: stroke, source: source).forEach { poster.post($0) }
    }

    /// Maps the kit's `Keystroke` to a virtual key code + flags. Characters use `layout` (the
    /// Mac's active one in the app); named keys use fixed codes.
    public static func keyStroke(for k: Keystroke, layout: KeyLayout = .ansi) -> KeyStroke? {
        let code: UInt16
        var shift = k.modifiers.contains(.shift)
        switch k.key {
        case .special(let s):
            guard let c = specialCodes[s] else { return nil }
            code = c
        case .character(let s):
            guard s.count == 1, let ch = s.first else { return nil }
            let shortcut = k.modifiers.contains(.command) || k.modifiers.contains(.control)
            guard let key = layout.key(for: ch, shortcut: shortcut) else { return nil }
            code = key.code
            if key.shift { shift = true }
        }
        return KeyStroke(keyCode: code, command: k.modifiers.contains(.command), option: k.modifiers.contains(.option),
                         control: k.modifiers.contains(.control), shift: shift, function: k.modifiers.contains(.function))
    }

    static let specialCodes: [SpecialKey: UInt16] = [
        .returnKey: 36, .tab: 48, .space: 49, .delete: 51, .forwardDelete: 117, .escape: 53,
        .left: 123, .right: 124, .down: 125, .up: 126, .home: 115, .end: 119, .pageUp: 116, .pageDown: 121,
        // kVK_F1 ... kVK_F12 (HIToolbox Events.h).
        .f1: 122, .f2: 120, .f3: 99, .f4: 118, .f5: 96, .f6: 97, .f7: 98, .f8: 100,
        .f9: 101, .f10: 109, .f11: 103, .f12: 111,
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
