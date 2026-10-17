import Foundation

/// The modifier keys of Glasspad's keyboard, the way the iPad's keyboard does them:
/// - tap a modifier and it applies to the next key; tap twice quickly and it stays on until
///   tapped again (`StickyModifiers`);
/// - or hold it down with one finger and press keys with another, like a real keyboard: it
///   applies while held and lets go with the finger, without latching;
/// - Caps Lock types capitals until pressed again. A locked Shift does the same for letters.
/// Pure value, driven by the caller's clock.
public struct KeyboardModifierState: Equatable, Sendable {
    public enum State: Equatable, Sendable { case off, latched, locked, held }

    public private(set) var sticky = StickyModifiers()
    /// Modifiers whose key is down, and whether another key was pressed while it was.
    private var held: [UInt8: Bool] = [:]
    public private(set) var capsLock = false

    public init() {}

    public func state(of m: KeyModifiers) -> State {
        if held[m.rawValue] != nil { return .held }
        switch sticky.state(of: m) {
        case .off: return .off
        case .latched: return .latched
        case .locked: return .locked
        }
    }

    /// Every modifier the next key gets.
    public var active: KeyModifiers {
        held.keys.reduce(sticky.active) { $0.union(KeyModifiers(rawValue: $1)) }
    }

    public var isEmpty: Bool { active.isEmpty }

    /// Letters come out as capitals (Caps Lock, or Shift on).
    public var capitals: Bool { capsLock || active.contains(.shift) }

    /// A modifier key went down.
    public mutating func down(_ m: KeyModifiers) {
        held[m.rawValue] = false
    }

    /// A modifier key came up. Used as a chord (another key pressed while it was down), it
    /// simply lets go; otherwise it was a tap, which latches, locks or releases it.
    public mutating func up(_ m: KeyModifiers, at time: TimeInterval) {
        guard let used = held.removeValue(forKey: m.rawValue) else { return }
        if !used { sticky.tap(m, at: time) }
    }

    /// A key that types was pressed: the modifiers it carries. Latched ones let go, locked and
    /// held ones stay.
    public mutating func consume() -> KeyModifiers {
        for key in held.keys { held[key] = true }
        let out = active
        _ = sticky.consume()
        return out
    }

    public mutating func toggleCapsLock() { capsLock.toggle() }

    /// Everything off (the Mac went away, the keyboard left the screen).
    public mutating func clear() {
        sticky.clear()
        held = [:]
        capsLock = false
    }

    /// Touches were cancelled (a call, Control Center): held keys let go without latching.
    public mutating func releaseHeld() { held = [:] }
}

/// What a key press sends to the Mac, through the existing `keysText` and `keysKeystroke`
/// messages. Pure.
public enum KeyboardOutput {
    /// The message for `kind` pressed with `modifiers` (from `KeyboardModifierState.consume()`).
    /// `capsLock` capitalises letters only, like a Mac.
    ///
    /// A character with nothing but Shift is typed as text, so the Mac shows exactly the
    /// character on the key whatever its own layout does. With Command, Control or Option it
    /// is a keystroke on the key's base character, which the Mac presses on the key of its
    /// layout that types it (`KeyLayout`), so Command-Z is Undo on AZERTY too.
    /// fn turns the arrows into Home, End, Page Up and Page Down, and Delete into Forward
    /// Delete, as on a Mac.
    public static func message(for kind: KeyboardKeyKind, modifiers: KeyModifiers, capsLock: Bool,
                               letters: KeyboardLetters) -> ModeMessage? {
        var mods = modifiers
        let fn = mods.contains(.function)
        mods.remove(.function)
        switch kind {
        case .character(let code):
            let cap = letters.cap(code)
            guard !cap.base.isEmpty else { return nil }
            if mods.intersection([.command, .control, .option]).isEmpty {
                return .keysText(typed(cap, shift: mods.contains(.shift), capsLock: capsLock))
            }
            return .keysKeystroke(Keystroke(key: .character(cap.base.lowercased()), modifiers: mods))
        case .special(let s):
            let key = fn ? fnSpecial(s) : s
            if key == .space && mods.isEmpty { return .keysText(" ") }
            // An F-key keeps fn off the Mac: the phone's fn only chose the key.
            return .keysKeystroke(Keystroke(key: .special(key), modifiers: mods))
        case .modifier, .capsLock, .symbols:
            return nil
        }
    }

    /// The character a key types: Shift picks the shifted character; Caps Lock capitalises a
    /// letter (and only a letter); both together give the lower case, like the iPhone.
    public static func typed(_ cap: KeyCap, shift: Bool, capsLock: Bool) -> String {
        if shift { return capsLock && isLetter(cap) ? cap.base : cap.shifted }
        if capsLock && isLetter(cap) { return cap.base.uppercased() }
        return cap.base
    }

    /// A letter key: Shift gives its capital.
    public static func isLetter(_ cap: KeyCap) -> Bool {
        cap.base != cap.base.uppercased() && cap.base.uppercased() == cap.shifted
    }

    static func fnSpecial(_ s: SpecialKey) -> SpecialKey {
        switch s {
        case .left: .home
        case .right: .end
        case .up: .pageUp
        case .down: .pageDown
        case .delete: .forwardDelete
        default: s
        }
    }

    /// The local echo after a message: typed text is added, Delete takes the last character
    /// off, Return starts again. Shortcuts and moves leave it alone. Kept to the last `limit`
    /// characters.
    public static func echo(_ text: String, after message: ModeMessage, limit: Int = 200) -> String {
        var t = text
        switch message {
        case .keysText(let s): t += s
        case .keysKeystroke(let k) where k.modifiers.intersection([.command, .control, .option]).isEmpty:
            switch k.key {
            case .special(.delete): if !t.isEmpty { t.removeLast() }
            case .special(.returnKey): t = ""
            default: break
            }
        default: break
        }
        return t.count > limit ? String(t.suffix(limit)) : t
    }
}
