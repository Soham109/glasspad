import Foundation

/// What the Lock Screen and Dynamic Island show while Remote, Media or Present is in use with
/// Glasspad in the background: the Live Activity's whole state. The app sends a new one only
/// when something on it changes; the Present timer counts by itself from a date, so nothing
/// is sent per second.
public struct LiveControls: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case remote, present
    }

    public var kind: Kind
    public var macName: String
    /// Why the last button press did not reach the Mac, shown until one does.
    public var problem: String?
    public var remote: Remote?
    public var present: Present?

    public init(kind: Kind, macName: String, problem: String? = nil, remote: Remote? = nil, present: Present? = nil) {
        self.kind = kind
        self.macName = macName
        self.problem = problem
        self.remote = remote
        self.present = present
    }

    public static func remote(_ remote: Remote, macName: String, problem: String? = nil) -> LiveControls {
        LiveControls(kind: .remote, macName: macName, problem: problem, remote: remote)
    }

    public static func present(_ present: Present, macName: String, problem: String? = nil) -> LiveControls {
        LiveControls(kind: .present, macName: macName, problem: problem, present: present)
    }

    // MARK: Remote

    /// The Remote's three buttons and what is playing.
    public struct Remote: Codable, Hashable, Sendable {
        public var title: String
        public var detail: String?
        public var isPlaying: Bool
        /// Back and forward change the song (music apps) instead of jumping 10 seconds.
        public var skipsTracks: Bool
        public var hasBack: Bool
        public var hasForward: Bool

        public init(title: String, detail: String?, isPlaying: Bool, skipsTracks: Bool,
                    hasBack: Bool, hasForward: Bool) {
            self.title = title
            self.detail = detail
            self.isPlaying = isPlaying
            self.skipsTracks = skipsTracks
            self.hasBack = hasBack
            self.hasForward = hasForward
        }

        /// From the Mac's now playing, as the Remote screen shows it. `isPlaying` includes a
        /// tap the Mac has not confirmed yet (`MediaPlayback.isPlaying(at:)`).
        public init(state: MediaState?, isPlaying: Bool, frontmost: String?) {
            let nowPlaying = [state?.title, state?.artist, state?.album]
            let keymap = RemoteKeymap(frontmost: frontmost, playing: state?.sourceBundleID, nowPlaying: nowPlaying)
            let canSeek = Self.canSeek(state: state, keymap: keymap)
            let hasTrack = !(state?.title ?? "").isEmpty
            self.init(title: hasTrack ? (state?.title ?? "") : "Nothing Playing",
                      detail: Self.detail(state: state, keymap: keymap, hasTrack: hasTrack),
                      isPlaying: hasTrack && isPlaying,
                      skipsTracks: keymap.skipsTracks,
                      hasBack: keymap.has(.back, canSeek: canSeek),
                      hasForward: keymap.has(.forward, canSeek: canSeek))
        }

        /// Seeking through now playing is only right when the controls are the playing app's.
        public static func canSeek(state: MediaState?, keymap: RemoteKeymap) -> Bool {
            guard state?.canSeek == true else { return false }
            return RemoteKeymap.player(bundleID: state?.sourceBundleID,
                                       nowPlaying: [state?.title, state?.artist, state?.album]) == keymap.player
        }

        /// "Netflix in Safari", "Radiohead", "Apple TV"; nil when there is nothing to add.
        private static func detail(state: MediaState?, keymap: RemoteKeymap, hasTrack: Bool) -> String? {
            guard hasTrack else { return nil }
            let app = state?.sourceName
            switch (keymap.player, keymap.name, app) {
            case (.browser(let site), let name?, let app?) where site != .other: return "\(name) in \(app)"
            case (.music, _, _), (.appleMusic, _, _):
                if let artist = state?.artist, !artist.isEmpty { return artist }
                return app
            case (_, _, let app?): return app
            case (_, let name?, _): return name
            default: return nil
            }
        }

        public var backSymbol: String { skipsTracks ? "backward.fill" : "gobackward.10" }
        public var forwardSymbol: String { skipsTracks ? "forward.fill" : "goforward.10" }
        public var backLabel: String { skipsTracks ? "Previous" : "Back 10 seconds" }
        public var forwardLabel: String { skipsTracks ? "Next" : "Forward 10 seconds" }
    }

    // MARK: Present

    /// The talk timer. Drawn with the system's date-relative text, so it keeps counting on the
    /// Lock Screen with no updates.
    public struct Present: Codable, Hashable, Sendable {
        /// While running: the moment the clock read 0:00 (now minus the time so far). Nil when paused.
        public var countingFrom: Date?
        /// The time so far, when paused.
        public var elapsed: TimeInterval
        /// The talk length, when one is set: the clock counts down.
        public var length: TimeInterval?

        public init(countingFrom: Date?, elapsed: TimeInterval, length: TimeInterval? = nil) {
            self.countingFrom = countingFrom
            self.elapsed = elapsed
            self.length = length
        }

        /// From the Present timer's values at `now`.
        public init(isRunning: Bool, elapsed: TimeInterval, length: TimeInterval?, now: Date) {
            let whole = max(0, elapsed)
            self.init(countingFrom: isRunning ? now.addingTimeInterval(-whole) : nil,
                      elapsed: isRunning ? 0 : whole,
                      length: length.flatMap { $0 > 0 ? $0 : nil })
        }

        public var isRunning: Bool { countingFrom != nil }

        /// When a running talk with a length reaches zero.
        public var endsAt: Date? {
            guard let countingFrom, let length else { return nil }
            return countingFrom.addingTimeInterval(length)
        }

        /// The time to show while paused: what is left with a length ("+0:12" once over), the
        /// time so far without.
        public var pausedText: String {
            guard let length else { return Self.clock(elapsed) }
            let left = length - elapsed
            return left >= 0 ? Self.clock(left) : "+" + Self.clock(-left)
        }

        /// "4:05", "1:02:03".
        public static func clock(_ t: TimeInterval) -> String {
            let s = Int(max(0, t).rounded(.down))
            return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                             : String(format: "%d:%02d", s / 60, s % 60)
        }
    }
}

/// After a Lock Screen button reaches the Mac, the connection is kept for a short while so the
/// next press goes out at once instead of connecting again. Each press moves the end later.
public struct LiveLinger: Equatable, Sendable {
    /// How long the connection stays after the last press.
    public static let hold: TimeInterval = 20

    public private(set) var until: TimeInterval?

    public init() {}

    /// A press at uptime `now`. Returns true when nothing holds the connection yet (start one).
    public mutating func pressed(at now: TimeInterval) -> Bool {
        let starting = !isHolding(at: now)
        until = now + Self.hold
        return starting
    }

    public func isHolding(at now: TimeInterval) -> Bool {
        guard let until else { return false }
        return now < until
    }

    /// Seconds left to wait before letting go (0 when it is time).
    public func remaining(at now: TimeInterval) -> TimeInterval {
        max(0, (until ?? now) - now)
    }

    /// iOS is about to suspend the app: let go now.
    public mutating func stop() { until = nil }
}
