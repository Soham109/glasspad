import Foundation

/// Which taps wait for a reconnect, and for how long. After the phone unlocks the link takes a
/// moment to come back; a Next, a play or a button tapped in that moment is held and sent once
/// it is up, instead of vanishing. Only one-shot taps are held: touch frames, typing, the laser
/// and volume are live input, and a late copy would be wrong.
public enum TapHold {
    /// A held tap is dropped (and fails) after this long.
    public static let lifetime: TimeInterval = 3
    /// At most this many wait; one more pushes the oldest out.
    public static let capacity = 8
    /// Taps are held only while the link has been down for less than this. Longer, and the Mac
    /// is most likely not coming back soon: the tap fails at once.
    public static let maxDowntime: TimeInterval = 5
    /// How long screens keep their "not connected" message back after the app comes to the
    /// front or a connected link restarts, so a quick reconnect shows nothing.
    public static let grace: TimeInterval = 2.5

    /// The messages that are held while the link comes back.
    public static func holds(_ message: ModeMessage) -> Bool {
        switch message {
        case .deckRun, .deckRunConfirmed, .mediaCommand, .presentNext, .presentPrevious, .remoteSystem, .dockOpen:
            return true
        case .macro(.run):
            return true
        default:
            return false
        }
    }

    /// The same tap again while it waits counts once: Next tapped twice because nothing seemed
    /// to happen must not skip a slide, and Play or Pause twice must not undo itself. Taps that
    /// report a result (they carry an id) are all kept, so none waits for an answer in vain.
    public static func isRepeat(_ new: ModeMessage, of held: ModeMessage) -> Bool {
        switch new {
        case .presentNext, .presentPrevious, .mediaCommand: new == held
        default: false
        }
    }

    /// Whether a tap made now may wait for the link, or should fail at once.
    /// - Parameters:
    ///   - macSelected: a Mac is paired and chosen.
    ///   - inFront: the app is in the foreground.
    ///   - linkGivenUp: the link failed or another iPhone took the Mac (it is not retrying).
    ///   - knownAbsent: the phone knows why the Mac is not there (asleep, Glasspad off, blocked).
    ///   - downFor: seconds since the link was last up, or since the app came to the front.
    public static func mayWait(macSelected: Bool, inFront: Bool, linkGivenUp: Bool, knownAbsent: Bool,
                               downFor: TimeInterval) -> Bool {
        macSelected && inFront && !linkGivenUp && !knownAbsent && downFor < maxDowntime
    }
}

/// Taps waiting for the link, oldest first. Pure: the caller passes the time, sends what
/// `drain` returns and fails what comes back expired or pushed out.
public struct TapOutbox<Item> {
    private var held: [(item: Item, at: TimeInterval)] = []

    public init() {}

    public var isEmpty: Bool { held.isEmpty }
    public var count: Int { held.count }
    /// When the oldest held tap runs out, nil when nothing waits.
    public var nextExpiry: TimeInterval? { held.first.map { $0.at + TapHold.lifetime } }
    /// Everything waiting, oldest first (without taking it out).
    public var items: [Item] { held.map(\.item) }

    /// Holds `item`, unless it repeats one already waiting (`isRepeat`). Returns the taps
    /// pushed out to make room (the oldest, when full).
    @discardableResult
    public mutating func hold(_ item: Item, at now: TimeInterval,
                              isRepeat: (_ new: Item, _ held: Item) -> Bool = { _, _ in false }) -> [Item] {
        if held.contains(where: { isRepeat(item, $0.item) }) { return [] }
        held.append((item, now))
        guard held.count > TapHold.capacity else { return [] }
        let out = held.prefix(held.count - TapHold.capacity).map(\.item)
        held.removeFirst(held.count - TapHold.capacity)
        return out
    }

    /// The link is up: everything still fresh, in the order it was tapped, and what ran out.
    /// The outbox is empty afterwards, so each tap is sent at most once.
    public mutating func drain(at now: TimeInterval) -> (send: [Item], expired: [Item]) {
        let all = held
        held = []
        var send: [Item] = [], expired: [Item] = []
        for h in all {
            if now - h.at < TapHold.lifetime { send.append(h.item) } else { expired.append(h.item) }
        }
        return (send, expired)
    }

    /// Takes out and returns the taps that ran out.
    public mutating func expire(at now: TimeInterval) -> [Item] {
        let out = held.filter { now - $0.at >= TapHold.lifetime }.map(\.item)
        held.removeAll { now - $0.at >= TapHold.lifetime }
        return out
    }

    /// Takes out and returns everything.
    public mutating func removeAll() -> [Item] {
        defer { held = [] }
        return held.map(\.item)
    }
}
