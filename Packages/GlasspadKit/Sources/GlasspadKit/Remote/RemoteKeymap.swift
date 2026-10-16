import Foundation

/// What the Remote mode's buttons and swipes do, per player on the Mac. A pure table so it can
/// be tested; the phone resolves each `RemoteOutput` into a message (`RemoteKeymap.message`).
///
/// Play and pause always go through the Mac's now playing (the media key), which reaches the
/// player even when another window is in front and works for every site that plays in a
/// browser. Seeking, full screen and subtitles are keystrokes, which go to the frontmost app.
/// Volume and mute are the Mac's own, so they work the same everywhere.

/// A button or swipe on the remote.
public enum RemoteAction: String, CaseIterable, Sendable {
    case playPause, back, forward, previous, next, fullScreen, subtitles, skipIntro
}

/// What a remote action becomes on the Mac.
public enum RemoteOutput: Equatable, Sendable {
    case keystroke(Keystroke)
    /// Several keys in a row (for example "/" to focus a search box).
    case keystrokes([Keystroke])
    case media(MediaCommand)
    /// Jump by this many seconds through the Mac's player. When the position is not known or
    /// the player cannot seek, `fallback` is pressed instead.
    case seek(TimeInterval, fallback: Keystroke?)
}

/// The kinds of player the remote knows. Websites are only told apart when the now playing
/// text names them (`RemoteSite`); every site still gets keys that work on all of them.
public enum RemotePlayer: Equatable, Sendable {
    case browser(RemoteSite)
    case appleTV, quickTime, iina, vlc, infuse
    /// Spotify, Music, Podcasts: songs, so left and right change the song.
    case music
    /// Anything else: the standard full screen shortcut and seeking through now playing.
    case other
}

public enum RemoteSite: String, Equatable, Sendable, CaseIterable {
    case youtube, netflix, primeVideo, disneyPlus, other
}

public struct RemoteKeymap: Equatable, Sendable {
    public let player: RemotePlayer

    public init(player: RemotePlayer) { self.player = player }

    /// The keymap for what the person is watching. A video app in front decides (keys go to
    /// the frontmost app). Otherwise the app playing does: a browser left in front while
    /// Spotify plays should still skip songs. With nothing playing, the frontmost app.
    /// `nowPlaying` is the title, artist and album text, used to spot the website.
    public init(frontmost: String?, playing: String?, nowPlaying: [String?] = []) {
        let front = RemoteKeymap.player(bundleID: frontmost, nowPlaying: nowPlaying)
        let playingPlayer = RemoteKeymap.player(bundleID: playing, nowPlaying: nowPlaying)
        switch front {
        case .appleTV, .quickTime, .iina, .vlc, .infuse: self.init(player: front)
        default: self.init(player: playing != nil && playingPlayer != .other ? playingPlayer : front)
        }
    }

    // MARK: Which player

    public static let browsers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "com.google.Chrome.beta",
        "company.thebrowser.Browser", "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "app.zen-browser.zen", "com.kagi.kagimacOS",
    ]
    public static let musicApps: Set<String> = [
        "com.spotify.client", "com.apple.Music", "com.apple.podcasts", "com.tidal.desktop", "com.amazon.music",
    ]

    public static func player(bundleID: String?, nowPlaying: [String?] = []) -> RemotePlayer {
        guard let id = bundleID else { return .other }
        if browsers.contains(id) { return .browser(site(nowPlaying)) }
        if musicApps.contains(id) { return .music }
        switch id {
        case "com.apple.TV": return .appleTV
        case "com.apple.QuickTimePlayerX": return .quickTime
        case "com.colliderli.iina": return .iina
        case "org.videolan.vlc": return .vlc
        case "com.firecore.infuse", "com.firecore.Infuse": return .infuse
        default: return .other
        }
    }

    /// The website, when the now playing text names it (browsers often put the site there).
    public static func site(_ texts: [String?]) -> RemoteSite {
        let text = texts.compactMap { $0?.lowercased() }.joined(separator: " ")
        if text.contains("youtube") { return .youtube }
        if text.contains("netflix") { return .netflix }
        if text.contains("prime video") || text.contains("primevideo") { return .primeVideo }
        if text.contains("disney") { return .disneyPlus }
        return .other
    }

    /// A short name for the controls in use: "YouTube", "Apple TV", "Spotify and Music".
    public var name: String? {
        switch player {
        case .browser(.youtube): "YouTube"
        case .browser(.netflix): "Netflix"
        case .browser(.primeVideo): "Prime Video"
        case .browser(.disneyPlus): "Disney+"
        case .browser(.other): "Web Video"
        case .appleTV: "Apple TV"
        case .quickTime: "QuickTime Player"
        case .iina: "IINA"
        case .vlc: "VLC"
        case .infuse: "Infuse"
        case .music: nil
        case .other: nil
        }
    }

    // MARK: The table

    /// Left and right step through songs instead of seconds.
    public var skipsTracks: Bool { player == .music }

    /// How far back and forward jump, in seconds, when it is known (YouTube's arrows are 5 s).
    public var seekStep: TimeInterval { 10 }

    /// What `action` does here; nil when this player has nothing for it (the button hides).
    public func output(_ action: RemoteAction) -> RemoteOutput? {
        switch action {
        case .playPause: return .media(.playPause)
        case .back: return skipsTracks ? .media(.previousTrack) : seek(-1)
        case .forward: return skipsTracks ? .media(.nextTrack) : seek(1)
        case .previous: return previous
        case .next: return next
        case .fullScreen: return fullScreen.map(RemoteOutput.keystroke)
        case .subtitles: return subtitles.map(RemoteOutput.keystroke)
        case .skipIntro: return player == .browser(.netflix) ? .keystroke(Self.key("s")) : nil
        }
    }

    public func has(_ action: RemoteAction) -> Bool { output(action) != nil }

    private func seek(_ direction: Double) -> RemoteOutput {
        let left = Self.special(.left), right = Self.special(.right)
        switch player {
        case .browser(.youtube):
            // j and l jump 10 s; the arrows only 5.
            return .keystroke(Self.key(direction < 0 ? "j" : "l"))
        case .browser:
            // Netflix, Prime Video and Disney+ jump 10 s on the arrows; most other sites too.
            return .keystroke(direction < 0 ? left : right)
        case .vlc:
            let k = Keystroke(key: .special(direction < 0 ? .left : .right), modifiers: [.command, .option])
            return .seek(direction * seekStep, fallback: k)
        case .appleTV, .infuse, .iina, .quickTime, .other:
            return .seek(direction * seekStep, fallback: direction < 0 ? left : right)
        case .music:
            return .seek(direction * seekStep, fallback: nil)
        }
    }

    private var previous: RemoteOutput? {
        switch player {
        case .browser(.youtube): .keystroke(Keystroke(key: .character("p"), modifiers: [.shift]))
        case .music: .media(.previousTrack)
        default: nil
        }
    }

    private var next: RemoteOutput? {
        switch player {
        case .browser(.youtube): .keystroke(Keystroke(key: .character("n"), modifiers: [.shift]))
        case .music: .media(.nextTrack)
        default: nil
        }
    }

    private var fullScreen: Keystroke? {
        switch player {
        case .browser: Self.key("f")
        case .vlc: Keystroke(key: .character("f"), modifiers: [.command])
        case .music: nil
        // The standard Enter Full Screen shortcut (View menu) in every other Mac app.
        case .appleTV, .quickTime, .iina, .infuse, .other: Keystroke(key: .character("f"), modifiers: [.command, .control])
        }
    }

    private var subtitles: Keystroke? {
        switch player {
        // YouTube and most other web players. Netflix, Prime Video, Disney+ and the Mac apps
        // have no single key for it, so the button hides there.
        case .browser(.youtube), .browser(.other): Self.key("c")
        default: nil
        }
    }

    /// Pressed before typing a search: "/" puts YouTube's cursor in its search box. Other sites
    /// need the box clicked first.
    public var searchPrefix: [Keystroke] {
        player == .browser(.youtube) ? [Self.key("/")] : []
    }

    // MARK: Resolving

    /// The message for `output`, given the player's position (nil when unknown) and whether it
    /// can seek. nil when there is nothing to send.
    public static func message(for output: RemoteOutput, position: TimeInterval?, canSeek: Bool,
                               duration: TimeInterval? = nil) -> [ModeMessage] {
        switch output {
        case .keystroke(let k): return [.keysKeystroke(k)]
        case .keystrokes(let ks): return ks.map(ModeMessage.keysKeystroke)
        case .media(let c): return [.mediaCommand(c)]
        case .seek(let delta, let fallback):
            if canSeek, let position {
                var target = max(0, position + delta)
                if let duration, duration > 0 { target = min(target, duration) }
                return [.mediaControl(.seek(target))]
            }
            return fallback.map { [.keysKeystroke($0)] } ?? []
        }
    }

    // MARK: Volume

    /// The Mac's volume keys move in sixteenths.
    public static let volumeStep = 1.0 / 16

    /// The volume after `steps` presses up (or down when negative), snapped to the Mac's steps.
    public static func volume(from current: Double, steps: Int) -> Double {
        let snapped = (current / volumeStep).rounded() * volumeStep
        return min(1, max(0, snapped + Double(steps) * volumeStep))
    }

    private static func key(_ c: String) -> Keystroke { Keystroke(key: .character(c)) }
    private static func special(_ k: SpecialKey) -> Keystroke { Keystroke(key: .special(k)) }
}

/// Turns one finger's drag on the remote's surface into steps, like the Siri Remote's touch
/// surface: the first few points pick an axis, then every `stepX` (sideways) or `stepY` (up and
/// down) of travel is one step. A short flick that never reached a step still counts as one.
/// A touch that barely moves is a tap.
public struct RemoteSwipe: Equatable, Sendable {
    public enum Axis: Equatable, Sendable { case horizontal, vertical }

    /// What a change in the drag produced.
    public enum Event: Equatable, Sendable {
        /// Sideways: positive is right (forward). Vertical: positive is up (louder).
        case step(Axis, Int)
        case tap
    }

    public var lockDistance: Double = 18
    public var stepX: Double = 72
    public var stepY: Double = 30
    /// Movement under this, released, is a tap.
    public var tapSlop: Double = 12
    /// A flick needs at least this much travel on its axis to count as one step.
    public var flickDistance: Double = 26

    public private(set) var axis: Axis?
    private var emitted = 0
    private var stepped = false
    private var travelled: Double = 0

    public init() {}

    /// The finger moved: `dx` and `dy` are the total travel since it went down, in points
    /// (y grows downwards, as on screen).
    public mutating func moved(dx: Double, dy: Double) -> Event? {
        travelled = max(travelled, (dx * dx + dy * dy).squareRoot())
        if axis == nil {
            guard max(abs(dx), abs(dy)) >= lockDistance else { return nil }
            axis = abs(dx) >= abs(dy) ? .horizontal : .vertical
        }
        guard let axis else { return nil }
        let along = axis == .horizontal ? dx : -dy
        let size = axis == .horizontal ? stepX : stepY
        let wanted = Int((along / size).rounded(.towardZero))
        guard wanted != emitted else { return nil }
        let delta = wanted - emitted
        emitted = wanted
        stepped = true
        return .step(axis, delta)
    }

    /// The finger lifted, with its total travel.
    public mutating func ended(dx: Double, dy: Double) -> Event? {
        defer { self = RemoteSwipe(tuning: self) }
        if let event = moved(dx: dx, dy: dy) { return event }
        if travelled < tapSlop, axis == nil { return .tap }
        guard let axis, !stepped else { return nil }
        let along = axis == .horizontal ? dx : -dy
        guard abs(along) >= flickDistance else { return nil }
        return .step(axis, along > 0 ? 1 : -1)
    }

    /// A fresh tracker with the same distances.
    private init(tuning other: RemoteSwipe) {
        lockDistance = other.lockDistance
        stepX = other.stepX
        stepY = other.stepY
        tapSlop = other.tapSlop
        flickDistance = other.flickDistance
    }
}
