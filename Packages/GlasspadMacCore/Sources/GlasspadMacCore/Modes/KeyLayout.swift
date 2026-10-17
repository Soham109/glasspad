import AppKit
import Carbon
import GlasspadKit
import GlasspadMacros

/// Which key types which character on one keyboard layout, with and without Shift.
///
/// A key code is a physical key position, and macOS matches Command shortcuts against the
/// character the active layout gives that key. So "Cmd+A" must press the key that types "a" on
/// the Mac's layout: on French AZERTY that is the key a US keyboard calls Q. Using US positions
/// there turned Select All into Quit and Undo into Close Window.
public struct KeyLayout: Equatable, Sendable {
    /// Character typed with no modifiers -> key code.
    public var plain: [String: UInt16]
    /// Character typed with Shift -> key code.
    public var shifted: [String: UInt16]
    /// What each key types, key by key, for the phone's keyboard (`ModeMessage.keysLayout`).
    public var letters: KeyboardLetters

    /// `letters` defaults to the two maps turned around (exact when no two keys type the same
    /// character, as on US); `current()` reads it key by key.
    public init(plain: [String: UInt16], shifted: [String: UInt16], letters: KeyboardLetters? = nil) {
        self.plain = plain
        self.shifted = shifted
        // The layout readers skip the space bar; it is the same key everywhere.
        self.plain[" "] = 49
        self.letters = letters ?? KeyboardLetters.from(plain: Self.byCode(plain), shifted: Self.byCode(shifted))
    }

    static func byCode(_ map: [String: UInt16]) -> [UInt16: String] {
        var out: [UInt16: String] = [:]
        // Sorted so the result does not depend on dictionary order.
        for (char, code) in map.sorted(by: { $0.key < $1.key }) where out[code] == nil { out[code] = char }
        return out
    }

    /// US ANSI, used when the active layout cannot be read.
    public static let ansi = KeyLayout(
        plain: Dictionary(uniqueKeysWithValues: KeysMode.ansiCodes.map { (String($0.key), $0.value) }),
        shifted: Dictionary(uniqueKeysWithValues: KeysMode.shiftedANSI.map { (String($0.key), $0.value) }))

    /// The key and Shift state that type `ch` on this layout, nil when no key types it.
    ///
    /// `shortcut` (Command or Control held): on a layout that has no such character, such as
    /// Russian or Greek for "a", macOS matches shortcuts by US key positions, so the US key is
    /// right. For plain typing a US position would type the layout's own character instead, so
    /// there is no fallback and the caller types the character as text.
    public func key(for ch: Character, shortcut: Bool) -> (code: UInt16, shift: Bool)? {
        if let k = lookup(ch) { return k }
        return shortcut ? KeyLayout.ansi.lookup(ch) : nil
    }

    private func lookup(_ ch: Character) -> (code: UInt16, shift: Bool)? {
        let s = String(ch)
        if let c = plain[s] { return (c, false) }
        if let c = shifted[s] { return (c, true) }
        if ch.isUppercase, let c = plain[s.lowercased()] { return (c, true) }
        return nil
    }

    /// Reads the active keyboard layout (for an input method such as Japanese, the layout it
    /// types with). Text Input Sources must be used from the main thread.
    @MainActor
    public static func current() -> KeyLayout {
        // The unshifted map is the one macro recording and playback already use.
        let map = KeyboardLayoutMap.current()
        guard let shiftedByCode = readShifted(), !map.charToCode.isEmpty else { return .ansi }
        var shifted: [String: UInt16] = [:]
        // Highest code first so the lowest wins: the main block beats the keypad.
        for (code, s) in shiftedByCode.sorted(by: { $0.key > $1.key }) { shifted[s] = code }
        return KeyLayout(plain: map.charToCode, shifted: shifted,
                         letters: KeyboardLetters.from(plain: map.codeToChar, shifted: shiftedByCode))
    }

    /// Key code -> character typed with Shift on the active layout (UCKeyTranslate, public
    /// Carbon API).
    @MainActor
    private static func readShifted() -> [UInt16: String]? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var out: [UInt16: String] = [:]
        data.withUnsafeBytes { buffer in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for code in UInt16(0)..<128 where !Self.nonCharacterCodes.contains(code) {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let shift = UInt32((shiftKey >> 8) & 0xFF)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), shift,
                                            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                            &deadKeys, chars.count, &length, &chars)
                guard status == noErr, length > 0 else { continue }
                let s = String(utf16CodeUnits: chars, count: length)
                guard let scalar = s.unicodeScalars.first, s.count == 1,
                      !CharacterSet.controlCharacters.contains(scalar), s != " " else { continue }
                out[code] = s
            }
        }
        return out
    }

    /// Return, Tab, Space, Delete, Escape, arrows, F-keys and the like: never characters.
    static let nonCharacterCodes: Set<UInt16> = Set(KeysMode.specialCodes.values)
        .union([76, 71, 114])   // keypad Enter, Clear, Help
}

/// Caches the active layout and rereads it when the user switches keyboard layouts.
public final class LiveKeyLayout: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: KeyLayout?
    private var observer: NSObjectProtocol?
    /// Called on the main thread after the user switches keyboard layouts.
    public var onChange: (() -> Void)?

    public init() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main) { [weak self] _ in
            self?.lock.withLock { self?.cached = nil }
            self?.onChange?()
        }
    }

    deinit {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    /// The active layout. Read on the main thread (where Keys, Deck and Present run); from any
    /// other thread the last value read is used.
    public func current() -> KeyLayout {
        if let c = lock.withLock({ cached }) { return c }
        guard Thread.isMainThread else { return .ansi }
        let fresh = MainActor.assumeIsolated { KeyLayout.current() }
        lock.withLock { cached = fresh }
        return fresh
    }
}

// MARK: Input methods

/// The Mac's text input sources, as far as typing needs them. A protocol so tests use a fake
/// and never switch the real input source.
public protocol InputSources: AnyObject {
    /// The selected input source's ID, and whether it composes text (an input method such as
    /// Japanese or Chinese Pinyin, which turns typed letters into an uncommitted composition).
    func current() -> (id: String, composes: Bool)?
    /// Selects the user's ASCII-capable keyboard layout (ABC, U.S., ...). False when it could not.
    func selectASCIICapable() -> Bool
    /// Selects the input source with this ID again.
    @discardableResult func select(id: String) -> Bool
}

/// Text Input Sources (Carbon, public). Main thread only.
public final class LiveInputSources: InputSources {
    public init() {}

    public func current() -> (id: String, composes: Bool)? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let id = Self.string(source, kTISPropertyInputSourceID) else { return nil }
        let type = Self.string(source, kTISPropertyInputSourceType)
        return (id, type != (kTISTypeKeyboardLayout as String))
    }

    public func selectASCIICapable() -> Bool {
        guard let ascii = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() else { return false }
        return TISSelectInputSource(ascii) == noErr
    }

    @discardableResult
    public func select(id: String) -> Bool {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first else { return false }
        return TISSelectInputSource(source) == noErr
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }
}

/// Makes typed text arrive committed while an input method is selected.
///
/// An input method (Japanese, Chinese, Korean) intercepts key events, so text Glasspad types
/// ended up as an uncommitted composition ("konnichiwa" became marked kana). Around a typing
/// burst this selects the user's ASCII-capable layout, and puts the input method back once
/// typing has been quiet for `restoreDelay` (the posted events are handled asynchronously, so
/// restoring at once could still catch them).
public final class InputMethodGuard {
    private let sources: InputSources
    private let restoreDelay: TimeInterval
    private let after: (TimeInterval, @escaping () -> Void) -> Void
    /// The input method to put back, while switched away from it.
    public private(set) var switchedFrom: String?
    private var generation = 0

    public init(sources: InputSources, restoreDelay: TimeInterval = 0.6,
                after: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
                    nonisolated(unsafe) let work = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { work() }
                }) {
        self.sources = sources
        self.restoreDelay = restoreDelay
        self.after = after
    }

    /// Call right before posting typed text.
    public func willType() {
        if switchedFrom == nil, let cur = sources.current(), cur.composes {
            if sources.selectASCIICapable() {
                switchedFrom = cur.id
                GPLog.log("keys: input method \(cur.id) selected, typing through the ASCII layout")
            }
        }
        guard switchedFrom != nil else { return }
        generation += 1
        let gen = generation
        after(restoreDelay) { [weak self] in
            guard let self, gen == self.generation else { return }
            self.restore()
        }
    }

    /// Puts the input method back now (also on quit or disconnect).
    public func restore() {
        guard let id = switchedFrom else { return }
        switchedFrom = nil
        generation += 1
        sources.select(id: id)
    }
}
