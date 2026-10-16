import Foundation

/// Sticky modifier keys for an on-screen keyboard, the way macOS Sticky Keys works:
/// tap a modifier once and it applies to the next key only; tap it again quickly and it locks
/// until tapped once more. Pure value, driven by the caller's clock.
public struct StickyModifiers: Equatable, Sendable {
    public enum State: Equatable, Sendable { case off, latched, locked }

    /// A second tap within this long locks the modifier instead of releasing it.
    public static let doubleTapWindow: TimeInterval = 0.4

    private var states: [UInt8: State] = [:]
    private var lastTap: [UInt8: TimeInterval] = [:]

    public init() {}

    public func state(of modifier: KeyModifiers) -> State { states[modifier.rawValue] ?? .off }

    /// Every modifier the next key gets (latched and locked).
    public var active: KeyModifiers {
        states.reduce(into: KeyModifiers()) { set, entry in
            if entry.value != .off { set.insert(KeyModifiers(rawValue: entry.key)) }
        }
    }

    /// Only the locked ones.
    public var locked: KeyModifiers {
        states.reduce(into: KeyModifiers()) { set, entry in
            if entry.value == .locked { set.insert(KeyModifiers(rawValue: entry.key)) }
        }
    }

    public var isEmpty: Bool { active.isEmpty }

    /// One tap on a modifier key. Off -> latched. Latched -> locked when this tap comes within
    /// `doubleTapWindow` of the one that latched it, otherwise off. Locked -> off.
    public mutating func tap(_ modifier: KeyModifiers, at time: TimeInterval) {
        let key = modifier.rawValue
        switch state(of: modifier) {
        case .off:
            states[key] = .latched
        case .latched:
            let quick = lastTap[key].map { time - $0 <= Self.doubleTapWindow } ?? false
            states[key] = quick ? .locked : .off
        case .locked:
            states[key] = .off
        }
        lastTap[key] = time
    }

    /// A key was pressed: returns the modifiers it carries and releases the latched ones.
    /// Locked ones stay on.
    public mutating func consume() -> KeyModifiers {
        let out = active
        for (key, value) in states where value == .latched { states[key] = .off }
        return out
    }

    /// Everything off (leaving the keyboard, losing the Mac).
    public mutating func clear() {
        states = [:]
        lastTap = [:]
    }
}

/// Press-and-hold repeat for on-screen keys, with the system keyboard's feel: one press at
/// once, then after `initialDelay` a press every `interval`.
public struct KeyRepeat: Equatable, Sendable {
    public var initialDelay: TimeInterval
    public var interval: TimeInterval

    /// About what the iPhone keyboard's delete key does: half a second, then about 11 a second.
    public static let system = KeyRepeat(initialDelay: 0.5, interval: 0.09)

    public init(initialDelay: TimeInterval, interval: TimeInterval) {
        self.initialDelay = initialDelay
        self.interval = max(0.01, interval)
    }

    /// Presses sent in total after holding for `held` seconds, the first one included.
    public func presses(afterHolding held: TimeInterval) -> Int {
        guard held >= initialDelay else { return 1 }
        return 2 + Int(((held - initialDelay) / interval + 1e-9).rounded(.down))
    }

    /// How long to wait before press number `n` (1-based) after press `n - 1`.
    public func delay(beforePress n: Int) -> TimeInterval {
        switch n {
        case ...1: 0
        case 2: initialDelay
        default: interval
        }
    }
}
