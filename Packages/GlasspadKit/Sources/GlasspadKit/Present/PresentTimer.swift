import Foundation

// The rules behind Present's talk clock: elapsed time that survives pausing, leaving Present
// and a relaunch, and an optional talk length it counts down from. The clock the views share
// lives in the app (PresentClock); this is the part that can be tested.

/// Elapsed time that survives pausing. Wall-clock dates, so a saved one can be restored after
/// the app was closed.
public struct PresentTimer: Equatable, Sendable {
    public private(set) var isRunning = false
    public private(set) var startedAt: Date?
    public private(set) var accumulated: TimeInterval = 0

    public init() {}

    public var hasTime: Bool { isRunning || accumulated > 0 }

    public func elapsed(at date: Date) -> TimeInterval {
        max(0, accumulated + (startedAt.map { date.timeIntervalSince($0) } ?? 0))
    }

    /// Seconds left of a talk `length` long; below zero once it runs over.
    public func remaining(length: TimeInterval, at date: Date) -> TimeInterval {
        length - elapsed(at: date)
    }

    public mutating func toggle(at date: Date = .now) {
        if isRunning {
            accumulated = elapsed(at: date)
            startedAt = nil
        } else {
            startedAt = date
        }
        isRunning.toggle()
    }

    /// Back to zero; a running timer keeps running from now.
    public mutating func reset(at date: Date = .now) {
        accumulated = 0
        startedAt = isRunning ? date : nil
    }

    // MARK: Saving

    /// What is written to disk on each start, pause and reset (not on every tick).
    public struct Saved: Codable, Equatable, Sendable {
        public var startedAt: Date?
        public var accumulated: TimeInterval
        public var savedAt: Date

        public init(startedAt: Date?, accumulated: TimeInterval, savedAt: Date) {
            self.startedAt = startedAt
            self.accumulated = accumulated
            self.savedAt = savedAt
        }
    }

    /// A talk saved longer ago than this is over; the app opens at zero instead.
    public static let maxAge: TimeInterval = 12 * 60 * 60

    /// Nil when there is nothing worth keeping (at zero and stopped).
    public func saved(at date: Date = .now) -> Saved? {
        hasTime ? Saved(startedAt: startedAt, accumulated: accumulated, savedAt: date) : nil
    }

    /// Restores a saved timer, or starts at zero when it is missing or older than `maxAge`.
    public init(restoring saved: Saved?, at date: Date = .now) {
        guard let saved, date.timeIntervalSince(saved.savedAt) < Self.maxAge,
              date.timeIntervalSince(saved.savedAt) > -60 else { return }
        startedAt = saved.startedAt
        accumulated = max(0, saved.accumulated)
        isRunning = saved.startedAt != nil
    }
}

/// How the talk clock reads with a talk length set: counting down, then "+m:ss" once over.
public enum TalkClock {
    /// The lengths offered, in minutes. 0 is Off: the clock counts up.
    public static let lengths = [10, 15, 20, 30, 45, 60]

    /// Seconds left at which the phone gives one tap.
    public static let cues: [TimeInterval] = [5 * 60, 60]

    public enum Stage: Equatable, Sendable {
        /// Plenty of time left.
        case normal
        /// One minute or less left.
        case warning
        /// Time is up.
        case over
    }

    /// Whole seconds as shown: rounded up while counting down (a full length reads "20:00",
    /// and "0:00" is the moment it runs out), and rounded down once over.
    public static func shownSeconds(remaining: TimeInterval) -> Int {
        remaining > -1 ? Int(max(0, remaining).rounded(.up)) : -Int((-remaining).rounded(.down))
    }

    public static func stage(remaining: TimeInterval) -> Stage {
        let s = shownSeconds(remaining: remaining)
        if s <= 0 { return .over }
        return s <= 60 ? .warning : .normal
    }

    /// "12:30" left, or "+0:12" over.
    public static func text(remaining: TimeInterval) -> String {
        let s = shownSeconds(remaining: remaining)
        return s < 0 ? "+" + clock(-s) : clock(s)
    }

    /// For VoiceOver: "12 minutes 30 seconds left", "Over by 12 seconds".
    public static func spoken(remaining: TimeInterval) -> String {
        let s = shownSeconds(remaining: remaining)
        if s == 0 { return "Time is up" }
        return s < 0 ? "Over by \(spokenDuration(-s))" : "\(spokenDuration(s)) left"
    }

    /// "1:05" or "1:02:05".
    public static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func spokenDuration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = seconds / 60 % 60, s = seconds % 60
        func part(_ n: Int, _ unit: String) -> String? { n > 0 ? "\(n) \(unit)\(n == 1 ? "" : "s")" : nil }
        let parts = [part(h, "hour"), part(m, "minute"), part(s, "second")].compactMap { $0 }
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: " ")
    }

    /// The next cue still ahead with `remaining` seconds left (the largest one below it), or nil.
    public static func nextCue(remaining: TimeInterval) -> TimeInterval? {
        cues.filter { $0 < remaining }.max()
    }

    /// Whether a cue whose moment has come should still play: not when the app was away and
    /// only gets to it late (a tap long after the mark would mean nothing).
    public static func cueIsDue(_ cue: TimeInterval, remaining: TimeInterval) -> Bool {
        remaining <= cue + 0.5 && remaining > cue - 2
    }
}
