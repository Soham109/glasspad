import CoreGraphics
import Foundation

/// Virtual key codes (Carbon kVK_* values, HIToolbox Events.h). Public, stable since Mac OS X.
public enum KeyCode: CGKeyCode, Sendable {
    case a = 0, s = 1, d = 2, f = 3, h = 4, g = 5, z = 6, x = 7, c = 8, v = 9
    case b = 11, q = 12, w = 13, e = 14, r = 15, y = 16, t = 17
    case o = 31, u = 32, i = 34, p = 35, l = 37, j = 38, k = 40, n = 45, m = 46
    case rightBracket = 30, leftBracket = 33
    case returnKey = 36, tab = 48, space = 49, delete = 51, escape = 53
    case forwardDelete = 117, home = 115, end = 119, pageUp = 116, pageDown = 121
    case f11 = 103
    case left = 123, right = 124, down = 125, up = 126
}

/// A keystroke with modifiers, used by gesture fallbacks and by Keys, Deck and Present modes.
public struct KeyStroke: Equatable, Sendable, Codable {
    public var keyCode: UInt16
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var shift: Bool
    public var function: Bool

    public init(_ key: KeyCode, command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false, function: Bool = false) {
        self.init(keyCode: key.rawValue, command: command, option: option, control: control, shift: shift, function: function)
    }

    public init(keyCode: UInt16, command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false, function: Bool = false) {
        self.keyCode = keyCode
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
        self.function = function
    }

    public var flags: CGEventFlags {
        var f: CGEventFlags = []
        if command { f.insert(.maskCommand) }
        if option { f.insert(.maskAlternate) }
        if control { f.insert(.maskControl) }
        if shift { f.insert(.maskShift) }
        if function { f.insert(.maskSecondaryFn) }
        return f
    }
}

/// Builds keyboard CGEvents. Never posts by itself.
public enum KeyboardSynth {
    /// Key down + key up carrying the modifier flags.
    public static func events(for stroke: KeyStroke, source: CGEventSource?) -> [CGEvent] {
        var out: [CGEvent] = []
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: stroke.keyCode, keyDown: down) else { continue }
            // Arrow keys carry the numeric-pad and function flags on real keyboards; apps such as
            // Keynote and the Dock's Spaces shortcuts accept either, so we mirror the hardware.
            var flags = stroke.flags
            if (123...126).contains(stroke.keyCode) { flags.insert([.maskNumericPad, .maskSecondaryFn]) }
            e.flags = flags
            out.append(e)
        }
        return out
    }

    /// Unicode typing: one down/up pair per chunk of up to 20 UTF-16 units. Apple does not
    /// document a limit for CGEventKeyboardSetUnicodeString; 20 is a conservative chunk size
    /// (ASSUMED: some apps are reported to drop characters from longer strings).
    public static func unicodeEvents(for text: String, source: CGEventSource?) -> [CGEvent] {
        var out: [CGEvent] = []
        let units = Array(text.utf16)
        var i = 0
        while i < units.count {
            var end = min(i + 20, units.count)
            // Do not split a surrogate pair.
            if end < units.count, UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 }
            let chunk = Array(units[i..<end])
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                chunk.withUnsafeBufferPointer { buf in
                    e.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                }
                e.flags = []
                out.append(e)
            }
            i = end
        }
        return out
    }

    /// Reads back the unicode string of a keyboard event (used by tests).
    public static func unicodeString(of event: CGEvent) -> String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 64)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        return String(utf16CodeUnits: buffer, count: length)
    }
}
