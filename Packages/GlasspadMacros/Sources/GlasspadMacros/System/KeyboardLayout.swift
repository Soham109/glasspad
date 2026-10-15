import Foundation
import Carbon

/// Maps between key codes and the characters they type with no modifiers,
/// for one keyboard layout.
public struct KeyboardLayoutMap: Sendable {
    public var codeToChar: [UInt16: String]
    public var charToCode: [String: UInt16]

    public init(codeToChar: [UInt16: String]) {
        self.codeToChar = codeToChar
        var reverse: [String: UInt16] = [:]
        // Lowest code wins so the main block beats the keypad for digits.
        for (code, char) in codeToChar.sorted(by: { $0.key > $1.key }) { reverse[char] = code }
        self.charToCode = reverse
    }

    /// US ANSI, used when the active layout cannot be read.
    public static let ansi = KeyboardLayoutMap(codeToChar: ANSIKeyMap.codeToChar)

    /// The key a `MacroKey` should press on this layout.
    public func keyCode(for key: MacroKey) -> UInt16? {
        switch key {
        case .special(let s): return s.keyCode
        case .code(let c): return c
        case .character(let c): return charToCode[c] ?? ANSIKeyMap.charToCode[c]
        }
    }

    /// The `MacroKey` a recorded key code stands for on this layout.
    public func key(for keyCode: UInt16) -> MacroKey {
        if let special = SpecialKey(keyCode: keyCode) { return .special(special) }
        if let c = codeToChar[keyCode] ?? ANSIKeyMap.codeToChar[keyCode], let first = c.first {
            return .char(first)
        }
        return .code(keyCode)
    }

    /// Reads the active keyboard layout. Text Input Sources must be used from
    /// the main thread, hence `@MainActor`.
    @MainActor
    public static func current() -> KeyboardLayoutMap {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return .ansi
        }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var map: [UInt16: String] = [:]
        data.withUnsafeBytes { buffer in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for code in UInt16(0)..<128 where SpecialKey(keyCode: code) == nil {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), 0,
                                            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                            &deadKeys, chars.count, &length, &chars)
                guard status == noErr, length > 0 else { continue }
                let s = String(utf16CodeUnits: chars, count: length)
                guard let scalar = s.unicodeScalars.first, s.count == 1,
                      !CharacterSet.controlCharacters.contains(scalar), s != " " else { continue }
                map[code] = s.lowercased()
            }
        }
        return map.isEmpty ? .ansi : KeyboardLayoutMap(codeToChar: map)
    }
}
