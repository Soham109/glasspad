import Foundation

/// Modifier keys held during a keystroke or click.
public struct KeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let control = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let shift = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)

    /// Canonical order, the same order macOS menus print them in.
    static let ordered: [(KeyModifiers, String, String)] = [
        (.control, "control", "⌃"),
        (.option, "option", "⌥"),
        (.shift, "shift", "⇧"),
        (.command, "command", "⌘"),
    ]

    public var names: [String] { Self.ordered.filter { contains($0.0) }.map(\.1) }
    public var symbols: String { Self.ordered.filter { contains($0.0) }.map(\.2).joined() }
}

extension KeyModifiers: Codable {
    public init(from decoder: Decoder) throws {
        let names = try decoder.singleValueContainer().decode([String].self)
        var result: KeyModifiers = []
        for name in names {
            guard let match = Self.ordered.first(where: { $0.1 == name }) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown modifier \"\(name)\""))
            }
            result.insert(match.0)
        }
        self = result
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(names)
    }
}

/// Keys that do not type a character. Raw values are the names used in JSON.
public enum SpecialKey: String, CaseIterable, Sendable {
    case returnKey = "return", tab, space, delete, forwardDelete, escape
    case left, right, up, down, home, end, pageUp, pageDown
    case keypadEnter, help
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10
    case f11, f12, f13, f14, f15, f16, f17, f18, f19, f20

    /// macOS virtual key code (Carbon kVK_* values). These keys are layout independent.
    public var keyCode: UInt16 {
        switch self {
        case .returnKey: 0x24
        case .tab: 0x30
        case .space: 0x31
        case .delete: 0x33
        case .forwardDelete: 0x75
        case .escape: 0x35
        case .left: 0x7B
        case .right: 0x7C
        case .down: 0x7D
        case .up: 0x7E
        case .home: 0x73
        case .end: 0x77
        case .pageUp: 0x74
        case .pageDown: 0x79
        case .keypadEnter: 0x4C
        case .help: 0x72
        case .f1: 0x7A
        case .f2: 0x78
        case .f3: 0x63
        case .f4: 0x76
        case .f5: 0x60
        case .f6: 0x61
        case .f7: 0x62
        case .f8: 0x64
        case .f9: 0x65
        case .f10: 0x6D
        case .f11: 0x67
        case .f12: 0x6F
        case .f13: 0x69
        case .f14: 0x6B
        case .f15: 0x71
        case .f16: 0x6A
        case .f17: 0x40
        case .f18: 0x4F
        case .f19: 0x50
        case .f20: 0x5A
        }
    }

    public init?(keyCode: UInt16) {
        guard let match = Self.allCases.first(where: { $0.keyCode == keyCode }) else { return nil }
        self = match
    }

    public var symbol: String {
        switch self {
        case .returnKey: "↩"
        case .tab: "⇥"
        case .space: "Space"
        case .delete: "⌫"
        case .forwardDelete: "⌦"
        case .escape: "⎋"
        case .left: "←"
        case .right: "→"
        case .up: "↑"
        case .down: "↓"
        case .home: "↖"
        case .end: "↘"
        case .pageUp: "⇞"
        case .pageDown: "⇟"
        case .keypadEnter: "⌤"
        case .help: "Help"
        default: rawValue.uppercased()
        }
    }
}

/// A key on the keyboard.
///
/// Character keys are stored by the character they type with no modifiers held
/// (for example `t`, `/`, `[`), so a macro written on one keyboard layout still
/// presses the right shortcut on another. The output resolves the character to
/// a key code for the active layout at run time.
public enum MacroKey: Hashable, Sendable {
    case character(String)
    case special(SpecialKey)
    /// A raw virtual key code, for keys that have neither a character nor a name.
    case code(UInt16)

    /// Builds a key, normalising letters to lowercase and a space to `.special(.space)`.
    public static func char(_ c: Character) -> MacroKey {
        if c == " " { return .special(.space) }
        return .character(String(c).lowercased())
    }

    public var jsonName: String {
        switch self {
        case .character(let c): c
        case .special(let s): s.rawValue
        case .code(let code): "code:\(code)"
        }
    }

    public init?(jsonName: String) {
        if let special = SpecialKey(rawValue: jsonName) {
            self = .special(special)
        } else if jsonName.hasPrefix("code:"), let code = UInt16(jsonName.dropFirst(5)) {
            self = .code(code)
        } else if jsonName.count == 1, let c = jsonName.first {
            self = .char(c)
        } else {
            return nil
        }
    }

    public var displayName: String {
        switch self {
        case .character(let c): c.uppercased()
        case .special(let s): s.symbol
        case .code(let code): "Key \(code)"
        }
    }

    /// Key code on a US ANSI keyboard. Used as the fallback when the active
    /// layout cannot produce the character.
    public var ansiKeyCode: UInt16? {
        switch self {
        case .special(let s): s.keyCode
        case .code(let code): code
        case .character(let c): ANSIKeyMap.charToCode[c]
        }
    }
}

extension MacroKey: Codable {
    public init(from decoder: Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        guard let key = MacroKey(jsonName: name) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "Unknown key \"\(name)\""))
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(jsonName)
    }
}

/// A key plus the modifiers held with it, e.g. Shift-Command-T.
public struct KeyCombo: Hashable, Codable, Sendable {
    public var key: MacroKey
    public var modifiers: KeyModifiers

    public init(_ key: MacroKey, _ modifiers: KeyModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Convenience: `KeyCombo("t", [.command])`.
    public init(_ char: Character, _ modifiers: KeyModifiers = []) {
        self.init(.char(char), modifiers)
    }

    public var displayString: String { modifiers.symbols + key.displayName }
}

/// US ANSI key codes (Carbon kVK_ANSI_*), keyed by the unshifted character.
enum ANSIKeyMap {
    static let charToCode: [String: UInt16] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
        "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
        "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
        "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, "`": 0x32,
    ]

    static let codeToChar: [UInt16: String] = {
        var map: [UInt16: String] = [:]
        for (k, v) in charToCode { map[v] = k }
        return map
    }()
}
