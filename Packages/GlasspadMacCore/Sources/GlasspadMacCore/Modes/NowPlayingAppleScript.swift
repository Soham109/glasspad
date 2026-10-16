import AppKit
import Foundation
import GlasspadKit

/// The players Glasspad can also reach with Apple Events, as a fallback when MediaRemote gives
/// nothing. Scripts only run while the player is running, so they never launch it.
public enum ScriptablePlayer: String, CaseIterable, Sendable {
    case spotify = "com.spotify.client"
    case music = "com.apple.Music"

    public var bundleID: String { rawValue }
    public var name: String { self == .spotify ? "Spotify" : "Music" }
    var provider: NowPlayingSnapshot.Provider { self == .spotify ? .spotify : .music }

    static let separator = "\u{1F}"

    /// One line of fields separated by U+001F (unit separator):
    /// state, name, artist, album, duration, position, artwork url, shuffle, repeat, track id, volume.
    /// Returns "stopped" or "notRunning" instead when there is no track.
    var statusScript: String {
        switch self {
        case .spotify:
            // Spotify: duration in milliseconds, position in seconds, repeating is on or off.
            return """
            if application id "com.spotify.client" is not running then return "notRunning"
            tell application id "com.spotify.client"
                set sep to (character id 31)
                set st to player state as string
                if st is "stopped" then return "stopped"
                set t to current track
                return st & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & ((duration of t) as string) & sep & ((player position) as string) & sep & (artwork url of t) & sep & (shuffling as string) & sep & (repeating as string) & sep & (id of t) & sep & ((sound volume) as string)
            end tell
            """
        case .music:
            // Music: duration and position in seconds, song repeat is off, one or all.
            return """
            if application id "com.apple.Music" is not running then return "notRunning"
            tell application id "com.apple.Music"
                set sep to (character id 31)
                set st to player state as string
                if st is "stopped" then return "stopped"
                set t to current track
                return st & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & ((duration of t) as string) & sep & ((player position) as string) & sep & "" & sep & (shuffle enabled as string) & sep & (song repeat as string) & sep & (persistent ID of t) & sep & ((sound volume) as string)
            end tell
            """
        }
    }

    /// Music keeps artwork as data; the script returns it raw.
    var artworkScript: String? {
        self == .music ? """
        if application id "com.apple.Music" is not running then return ""
        tell application id "com.apple.Music"
            if (count of artworks of current track) is 0 then return ""
            return raw data of artwork 1 of current track
        end tell
        """ : nil
    }

    func commandScript(_ command: MediaCommand) -> String? {
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .play: verb = "play"
        case .pause: verb = "pause"
        case .nextTrack: verb = "next track"
        case .previousTrack: verb = "previous track"
        case .mute: return nil
        }
        return tell(verb)
    }

    func controlScript(_ control: MediaControl) -> String? {
        switch control {
        case .seek(let t):
            return tell("set player position to \(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), max(0, t)))")
        case .setShuffle(let on):
            return tell(self == .spotify ? "set shuffling to \(on)" : "set shuffle enabled to \(on)")
        case .setRepeat(let mode):
            if self == .spotify { return tell("set repeating to \(mode != .off)") }
            return tell("set song repeat to \(mode.rawValue)")
        case .selectOutput:
            return nil
        }
    }

    func volumeScript(_ value: Double) -> String {
        tell("set sound volume to \(Int((min(1, max(0, value)) * 100).rounded()))")
    }

    private func tell(_ body: String) -> String {
        """
        if application id "\(bundleID)" is running then
            tell application id "\(bundleID)" to \(body)
        end if
        """
    }

    /// Parses `statusScript` output. nil when nothing is loaded.
    func parseStatus(_ text: String, now: Date) -> NowPlayingSnapshot? {
        let fields = text.components(separatedBy: Self.separator)
        guard fields.count >= 10 else { return nil }
        let state = fields[0].lowercased()
        let title = fields[1]
        guard state != "stopped", !title.isEmpty else { return nil }
        let rawDuration = Self.number(fields[4])
        let duration = rawDuration.map { self == .spotify ? $0 / 1000 : $0 }
        let shuffle = Self.bool(fields[7])
        let repeatMode: MediaRepeatMode? = self == .spotify
            ? Self.bool(fields[8]).map { $0 ? .all : .off }
            : MediaRepeatMode(rawValue: fields[8].lowercased())
        let artURL = fields[6].isEmpty ? nil : URL(string: fields[6])
        return NowPlayingSnapshot(
            provider: provider, title: title, artist: fields[2].isEmpty ? nil : fields[2],
            album: fields[3].isEmpty ? nil : fields[3], duration: duration.flatMap { $0 > 0 ? $0 : nil },
            elapsed: Self.number(fields[5]), elapsedAt: now, playbackRate: state == "playing" ? 1 : 0,
            isPlaying: state == "playing", bundleID: bundleID, appName: name,
            artworkURL: artURL.flatMap { $0.scheme == "https" || $0.scheme == "http" ? $0 : nil },
            shuffle: shuffle, repeatMode: repeatMode, trackID: fields[9].isEmpty ? nil : fields[9])
    }

    /// AppleScript writes reals with the Mac's decimal separator; "215,5" and "215.5" both read.
    static func number(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if let v = Double(t) { return v }
        if !t.contains("."), let v = Double(t.replacingOccurrences(of: ",", with: ".")) { return v }
        return nil
    }

    static func bool(_ s: String) -> Bool? {
        switch s.trimmingCharacters(in: .whitespaces).lowercased() {
        case "true", "yes": true
        case "false", "no": false
        default: nil
        }
    }
}

/// How one script went.
public enum AppleScriptOutcome: Equatable, Sendable {
    case text(String)
    case data(Data)
    /// `code` is the AppleScript error number: -1743 means the user refused Automation,
    /// -600 the app is not running, -1712 it timed out.
    case failed(code: Int, message: String)

    public static let notPermitted = -1743
    public static let wouldRequireConsent = -1744

    var isPermissionDenied: Bool {
        if case .failed(let code, _) = self { return code == Self.notPermitted }
        return false
    }
}

/// Runs AppleScript. A protocol so tests use a fake and never reach a real app.
public protocol AppleScriptRunning: Sendable {
    func run(_ source: String) async -> AppleScriptOutcome
    /// Whether Glasspad may send Apple Events to the app: nil not decided yet, without asking.
    func permission(for bundleID: String) -> Bool?
}

/// NSAppleScript on one serial queue (scripts are compiled once and reused).
///
/// Off the main thread on purpose: since Mac OS X 10.6 "OSA and AppleScript are now thread-safe
/// ... This also applies to NSAppleScript" (AppleScript Release Notes, 10.6), which replaces the
/// older Threading Programming Guide's main-thread-only rule. Two limits remain: one script must
/// not run on two threads at once (the serial queue guarantees that, and the compiled cache is
/// only touched there), and scripting-addition commands are sent to the main thread, so the
/// scripts here use none (`character id 31`, not Standard Additions' `ASCII character 31`) and
/// never wait on the main thread, which posts the pointer events.
public final class LiveAppleScriptRunner: AppleScriptRunning, @unchecked Sendable {
    private let queue = DispatchQueue(label: "glasspad.media.applescript", qos: .userInitiated)
    private var compiled: [String: NSAppleScript] = [:]

    public init() {
        self.check = LiveAppleScriptRunner.askMacOS
    }

    public func run(_ source: String) async -> AppleScriptOutcome {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.runNow(source))
            }
        }
    }

    private func runNow(_ source: String) -> AppleScriptOutcome {
        let script: NSAppleScript
        if let cached = compiled[source] {
            script = cached
        } else {
            guard let made = NSAppleScript(source: source) else { return .failed(code: -2700, message: "Script did not compile") }
            var error: NSDictionary?
            guard made.compileAndReturnError(&error) else { return Self.failure(error) }
            if compiled.count > 64 { compiled.removeAll() }
            compiled[source] = made
            script = made
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error { return Self.failure(error) }
        let textTypes: Set<DescType> = [DescType(typeUnicodeText), DescType(typeUTF8Text), DescType(typeChar)]
        if textTypes.contains(result.descriptorType) { return .text(result.stringValue ?? "") }
        if result.descriptorType == DescType(typeNull) { return .text("") }
        // Artwork comes back as raw image data ('tdta', 'PNGf', 'JPEG').
        return .data(result.data)
    }

    private static func failure(_ error: NSDictionary?) -> AppleScriptOutcome {
        .failed(code: (error?[NSAppleScript.errorNumber] as? Int) ?? -1,
                message: (error?[NSAppleScript.errorMessage] as? String) ?? "AppleScript failed")
    }

    /// The last answer macOS gave for each app, refreshed in the background. Never waits:
    /// `AEDeterminePermissionToAutomateTarget` can block forever when macOS doesn't answer, and
    /// called from the main thread it froze the menu bar icon. A refresh that never comes back
    /// only holds one background thread, and no second one starts for that app meanwhile.
    public func permission(for bundleID: String) -> Bool? {
        permissionLock.lock()
        let known = permissions[bundleID] ?? nil
        let start = !checking.contains(bundleID)
        if start { checking.insert(bundleID) }
        permissionLock.unlock()
        if start {
            DispatchQueue.global(qos: .utility).async {
                let answer = self.check(bundleID)
                self.permissionLock.lock()
                self.permissions[bundleID] = answer
                self.checking.remove(bundleID)
                self.permissionLock.unlock()
            }
        }
        return known
    }

    private let permissionLock = NSLock()
    private var permissions: [String: Bool?] = [:]
    private var checking: Set<String> = []
    private let check: @Sendable (String) -> Bool?

    /// `check` stands in for the real permission call in tests.
    init(check: @escaping @Sendable (String) -> Bool?) {
        self.check = check
    }

    static func askMacOS(_ bundleID: String) -> Bool? {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return nil }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, false)
        switch Int(status) {
        case Int(noErr): return true
        case AppleScriptOutcome.notPermitted: return false
        default: return nil
        }
    }
}

/// Polls one scriptable player and remembers why it could not.
@MainActor
final class AppleScriptNowPlaying {
    private let runner: AppleScriptRunning
    /// Players the user refused Automation for. Not asked again this launch.
    private(set) var denied: Set<ScriptablePlayer> = []
    private var artworkTrack: [ScriptablePlayer: String] = [:]
    private var artwork: [ScriptablePlayer: Data] = [:]

    init(runner: AppleScriptRunning) {
        self.runner = runner
    }

    func isDenied(_ player: ScriptablePlayer) -> Bool { denied.contains(player) }

    /// Already allowed (so a script will not bring up the consent prompt).
    func isAllowed(_ player: ScriptablePlayer) -> Bool { runner.permission(for: player.bundleID) == true }

    func noteDecision(_ player: ScriptablePlayer) {
        switch runner.permission(for: player.bundleID) {
        case false?: denied.insert(player)
        case true?: denied.remove(player)
        case nil: break
        }
    }

    /// What the player has loaded, nil when nothing (or not allowed).
    func poll(_ player: ScriptablePlayer, now: Date = Date()) async -> NowPlayingSnapshot? {
        guard !denied.contains(player) else { return nil }
        let outcome = await runner.run(player.statusScript)
        if outcome.isPermissionDenied {
            denied.insert(player)
            return nil
        }
        guard case .text(let text) = outcome, var snapshot = player.parseStatus(text, now: now) else { return nil }
        if let script = player.artworkScript {
            let key = snapshot.trackID ?? snapshot.trackKey
            if artworkTrack[player] != key {
                artworkTrack[player] = key
                if case .data(let data) = await runner.run(script), !data.isEmpty {
                    artwork[player] = data
                } else {
                    artwork[player] = nil
                }
            }
            snapshot.artworkData = artwork[player]
        }
        return snapshot
    }

    /// Runs a command script; false when it could not.
    @discardableResult
    func perform(_ script: String?, on player: ScriptablePlayer) async -> Bool {
        guard let script, !denied.contains(player) else { return false }
        let outcome = await runner.run(script)
        if outcome.isPermissionDenied { denied.insert(player) }
        if case .failed = outcome { return false }
        return true
    }
}
