import Foundation
import GlasspadKit
import Observation

/// Present's talk clock, shared by every Present screen (the mode, the tool, two panes of a
/// layout) so it keeps counting when you leave Present and come back. Saved on each start,
/// pause and reset, so it also survives the app being closed mid-talk.
@MainActor
@Observable
final class PresentClock {
    static let shared = PresentClock()

    private(set) var timer: PresentTimer
    /// Talk Length in minutes; 0 is Off (the clock counts up).
    var lengthMinutes: Int {
        didSet {
            guard lengthMinutes != oldValue else { return }
            defaults.set(lengthMinutes, forKey: Key.length)
            scheduleCue()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var cueTimer: Timer?

    private enum Key {
        static let startedAt = "presentStartedAt", accumulated = "presentAccumulated"
        static let savedAt = "presentSavedAt", length = "presentTalkLength"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func seconds(_ key: String) -> Double? { defaults.object(forKey: key) == nil ? nil : defaults.double(forKey: key) }
        let saved = seconds(Key.savedAt).map { savedAt in
            PresentTimer.Saved(startedAt: seconds(Key.startedAt).map(Date.init(timeIntervalSince1970:)),
                               accumulated: defaults.double(forKey: Key.accumulated),
                               savedAt: Date(timeIntervalSince1970: savedAt))
        }
        timer = PresentTimer(restoring: saved)
        let minutes = defaults.integer(forKey: Key.length)
        lengthMinutes = TalkClock.lengths.contains(minutes) ? minutes : 0
        scheduleCue()
    }

    var isRunning: Bool { timer.isRunning }
    var hasTime: Bool { timer.hasTime }
    /// The talk length in seconds, nil when Off.
    var length: TimeInterval? { lengthMinutes > 0 ? TimeInterval(lengthMinutes * 60) : nil }

    func elapsed(at date: Date) -> TimeInterval { timer.elapsed(at: date) }

    /// Seconds left of the talk (below zero when over), nil when no length is set.
    func remaining(at date: Date) -> TimeInterval? { length.map { timer.remaining(length: $0, at: date) } }

    func toggle() {
        timer.toggle()
        changed()
    }

    func reset() {
        timer.reset()
        changed()
    }

    private func changed() {
        save()
        scheduleCue()
        // A running talk keeps the phone from locking while Present is on screen.
        ScreenAwake.update()
    }

    private func save() {
        guard let saved = timer.saved() else {
            for key in [Key.startedAt, Key.accumulated, Key.savedAt] { defaults.removeObject(forKey: key) }
            return
        }
        if let started = saved.startedAt {
            defaults.set(started.timeIntervalSince1970, forKey: Key.startedAt)
        } else {
            defaults.removeObject(forKey: Key.startedAt)
        }
        defaults.set(saved.accumulated, forKey: Key.accumulated)
        defaults.set(saved.savedAt.timeIntervalSince1970, forKey: Key.savedAt)
    }

    // MARK: Cues

    /// One click at 5 minutes and at 1 minute left, while the timer runs with a length set.
    private func scheduleCue(after previous: TimeInterval? = nil) {
        cueTimer?.invalidate()
        cueTimer = nil
        guard timer.isRunning, let left = remaining(at: .now),
              let cue = TalkClock.nextCue(remaining: min(left, previous ?? left)) else { return }
        let wait = max(0, left - cue)
        let next = Timer(timeInterval: wait, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.cueFired(cue) }
        }
        next.tolerance = 0.2
        RunLoop.main.add(next, forMode: .common)
        cueTimer = next
    }

    private func cueFired(_ cue: TimeInterval) {
        guard let left = remaining(at: .now) else { return }
        // Late (the app was in the background at the mark): no tap, it would mean nothing now.
        if timer.isRunning, TalkClock.cueIsDue(cue, remaining: left) { Haptics.shared.play(.click) }
        scheduleCue(after: cue)
    }
}
