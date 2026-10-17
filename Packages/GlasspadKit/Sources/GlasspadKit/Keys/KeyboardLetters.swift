import Foundation

/// What one key types: on its own and with Shift.
public struct KeyCap: Codable, Equatable, Sendable, Hashable {
    public var base: String
    public var shifted: String

    public init(_ base: String, _ shifted: String) {
        self.base = base
        self.shifted = shifted
    }
}

/// The characters on the Mac's keyboard, key by key, so the phone draws the keys the Mac's
/// layout has (AZERTY, QWERTZ, Dvorak...). Keys are named by their position, as macOS virtual key
/// codes on an ANSI keyboard (kVK_ANSI_*). A position the Mac did not send types what it does on
/// a US keyboard.
public struct KeyboardLetters: Codable, Equatable, Sendable {
    /// Key code, as a decimal string (JSON object keys are strings), -> what it types.
    public var keys: [String: KeyCap]

    public init(keys: [UInt16: KeyCap]) {
        self.keys = Dictionary(uniqueKeysWithValues: keys.map { (String($0.key), $0.value) })
    }

    /// What the key at `code` types here, falling back to US.
    public func cap(_ code: UInt16) -> KeyCap {
        if let c = keys[String(code)], !c.base.isEmpty { return c }
        return Self.usCaps[code] ?? KeyCap("", "")
    }

    /// US English, used until the Mac says otherwise (and with a Mac that never does).
    public static let us = KeyboardLetters(keys: usCaps)

    // MARK: Positions

    /// The character keys of an ANSI Mac keyboard, row by row, left to right.
    public static let numberRow: [UInt16] = [50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24]
    public static let topRow: [UInt16] = [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42]
    public static let homeRow: [UInt16] = [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39]
    public static let bottomRow: [UInt16] = [6, 7, 8, 9, 11, 45, 46, 43, 47, 44]

    /// Every character key position.
    public static let allPositions: [UInt16] = numberRow + topRow + homeRow + bottomRow

    static let usCaps: [UInt16: KeyCap] = {
        let base = Array("`1234567890-=") + Array("qwertyuiop[]\\") + Array("asdfghjkl;'") + Array("zxcvbnm,./")
        let shifted = Array("~!@#$%^&*()_+") + Array("QWERTYUIOP{}|") + Array("ASDFGHJKL:\"") + Array("ZXCVBNM<>?")
        var out: [UInt16: KeyCap] = [:]
        for (i, code) in allPositions.enumerated() { out[code] = KeyCap(String(base[i]), String(shifted[i])) }
        return out
    }()

    /// Builds the caps from a layout's key code -> character maps (plain and with Shift).
    /// Positions a map leaves out keep their US characters.
    public static func from(plain: [UInt16: String], shifted: [UInt16: String]) -> KeyboardLetters {
        var out: [UInt16: KeyCap] = [:]
        for code in allPositions {
            guard let b = plain[code], !b.isEmpty else { continue }
            let s = shifted[code].flatMap { $0.isEmpty ? nil : $0 } ?? b.uppercased()
            out[code] = KeyCap(b, s)
        }
        return KeyboardLetters(keys: out)
    }
}
