import AppKit
import AudioToolbox
import Combine
import CoreAudio
import GlasspadKit

/// Media mode: what plays on the Mac, transport, seek, shuffle, repeat, output volume, sound
/// output and display brightness.
///
/// Where now playing comes from, best first:
/// 1. `NowPlayingAdapter`: MediaRemote through /usr/bin/perl, for any player. Since macOS 15.4
///    MediaRemote answers only Apple processes, so Glasspad's own calls come back empty; perl is
///    an Apple process and can load Glasspad's small helper library.
/// 2. MediaRemote in this process, which still works before macOS 15.4.
/// 3. Apple Events to Spotify or Music (`AppleScriptNowPlaying`), which needs the user's
///    Automation consent. Also fills in Spotify's full-size artwork when already allowed.
@MainActor
public final class MediaMode {
    private let poster: EventPoster
    private let remote = MediaRemote.shared
    private let adapter: NowPlayingAdapter
    private let scripts: AppleScriptNowPlaying
    private let runningPlayers: @MainActor () -> [ScriptablePlayer]
    private let fetchArtwork: @Sendable (URL) async -> Data?
    /// Read MediaRemote in this process when the helper is not running (before macOS 15.4).
    private let useInProcessRemote: Bool

    /// Called when what plays changed; the router then pushes a fresh state.
    public var onChange: () -> Void = {}

    private var active = false
    private var adapterSnapshot: NowPlayingSnapshot?
    private var adapterReportedNothingSince: Date?
    private var inProcessSnapshot: NowPlayingSnapshot?
    private var scriptSnapshot: NowPlayingSnapshot?
    /// The scriptable player last seen playing, so with Music and Spotify both open and both
    /// paused, commands go to the one the user was listening to.
    private(set) var lastPlayingPlayer: ScriptablePlayer?
    private var pollTimer: Timer?
    private var polling = false
    private var builder = MediaWireBuilder()
    private var outputsCache: (at: Date, list: [MediaOutput])?
    private var artworkCache = ArtworkCache()
    private var iconCache: [String: (name: String?, png: Data?)] = [:]

    public init(poster: EventPoster) {
        self.poster = poster
        self.adapter = NowPlayingAdapter()
        self.scripts = AppleScriptNowPlaying(runner: LiveAppleScriptRunner())
        self.runningPlayers = MediaMode.liveRunningPlayers
        self.fetchArtwork = MediaMode.liveFetchArtwork
        self.useInProcessRemote = true
        wireAdapter()
    }

    /// For tests: every outside dependency injected.
    init(poster: EventPoster, adapter: NowPlayingAdapter, runner: AppleScriptRunning,
         runningPlayers: @escaping @MainActor () -> [ScriptablePlayer],
         fetchArtwork: @escaping @Sendable (URL) async -> Data? = { _ in nil }, useInProcessRemote: Bool = false) {
        self.poster = poster
        self.adapter = adapter
        self.scripts = AppleScriptNowPlaying(runner: runner)
        self.runningPlayers = runningPlayers
        self.fetchArtwork = fetchArtwork
        self.useInProcessRemote = useInProcessRemote
        wireAdapter()
    }

    private func wireAdapter() {
        adapter.onEvent = { [weak self] event in self?.adapterEvent(event) }
        adapter.onStatus = { [weak self] _ in self?.changed() }
    }

    // MARK: Lifecycle

    /// The phone shows Media (true) or left it (false). Sources run only while it shows.
    public func setActive(_ on: Bool) {
        guard on != active else { return }
        active = on
        if on {
            adapter.start()
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pollFallbacks() }
            }
            RunLoop.main.add(t, forMode: .common)
            pollTimer = t
            pollFallbacks()
        } else {
            adapter.stop()
            pollTimer?.invalidate()
            pollTimer = nil
            adapterSnapshot = nil
            scriptSnapshot = nil
            inProcessSnapshot = nil
            adapterReportedNothingSince = nil
        }
    }

    /// The phone asked for the full state: resend artwork and icons with the next state.
    public func phoneWantsEverything() {
        builder.reset()
        outputsCache = nil
        _ = adapter.send(.refresh)
    }

    // MARK: Commands

    public func send(_ command: MediaCommand) {
        if command == .mute {
            toggleMute()
            return
        }
        defer { refreshSoon() }
        if let code = AdapterCommand.code(for: command), adapter.send(.send(code)) { return }
        if let player = scriptTarget, scripts.isAllowed(player) {
            Task { await scripts.perform(player.commandScript(command), on: player) }
            return
        }
        if remote.send(command) { return }
        if let key = Self.mediaKey(for: command) { postMediaKey(key) }
    }

    public func control(_ control: MediaControl) {
        switch control {
        case .selectOutput(let id):
            _ = MediaOutputs.select(uid: id)
            outputsCache = nil
            changed()
            return
        case .seek(let t):
            if adapter.send(.seek(t)) { break }
            runScript(control)
        case .setShuffle(let on):
            if adapter.send(.shuffle(on)) { break }
            runScript(control)
        case .setRepeat(let mode):
            if adapter.send(.setRepeat(mode)) { break }
            runScript(control)
        }
        refreshSoon()
    }

    private func runScript(_ control: MediaControl) {
        guard let player = scriptTarget else { return }
        Task { await scripts.perform(player.controlScript(control), on: player) }
    }

    /// The player AppleScript commands go to: the one now playing when it is scriptable.
    private var scriptTarget: ScriptablePlayer? {
        guard let id = current?.sourceBundleID else { return nil }
        return ScriptablePlayer(rawValue: id)
    }

    /// NX_KEYTYPE_* values (IOKit hidsystem ev_keymap.h, public): play 16, next 17, previous 18.
    nonisolated static func mediaKey(for command: MediaCommand) -> Int32? {
        switch command {
        case .playPause, .play, .pause: 16
        case .nextTrack: 17
        case .previousTrack: 18
        case .mute: 7
        }
    }

    /// Media keys are NSSystemDefined events, subtype 8 (NX_SUBTYPE_AUX_CONTROL_BUTTONS), with
    /// data1 = key << 16 | (0xA down or 0xB up) << 8. Public AppKit + ev_keymap.h values.
    nonisolated static func mediaKeyEvents(_ key: Int32) -> [CGEvent] {
        [true, false].compactMap { down in
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            return NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                                      windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?.cgEvent
        }
    }

    private func postMediaKey(_ key: Int32) {
        Self.mediaKeyEvents(key).forEach { poster.post($0, tap: .cghidEventTap) }
    }

    public func setVolume(_ v: Double) { AudioOutput.setVolume(Float(min(1, max(0, v)))) }
    public func setBrightness(_ v: Double) { Brightness.set(Float(min(1, max(0, v)))) }

    private func toggleMute() {
        if let muted = AudioOutput.isMuted() { AudioOutput.setMuted(!muted) }
    }

    // MARK: State

    /// What plays now, all sources merged.
    var current: NowPlayingSnapshot? {
        NowPlayingMerger.merge(adapter: adapterSnapshot ?? inProcessSnapshot, script: scriptSnapshot)
    }

    /// Calls `completion` with a fresh state, or not at all when the phone's own prediction
    /// (position ticking on) already matches. After `phoneWantsEverything` it always calls.
    public func state(completion: @escaping @MainActor (MediaState) -> Void) {
        if let state = makeState(now: Date(), volume: AudioOutput.volume().map(Double.init),
                                 brightness: Brightness.get().map(Double.init), outputs: outputs()) {
            completion(state)
        }
    }

    func makeState(now: Date, volume: Double?, brightness: Double?, outputs: [MediaOutput]?) -> MediaState? {
        let snapshot = current
        var artwork: (id: String, data: Data)?
        if let snapshot {
            let lookup = artworkCache.artwork(for: snapshot)
            artwork = lookup.ready
            if let url = lookup.load { loadArtwork(url) }
        }
        let source = snapshot?.sourceBundleID.map(appInfo)
        let seekable = snapshot.map { s in
            (s.duration ?? 0) > 0 && (adapter.isRunning || ScriptablePlayer(rawValue: s.sourceBundleID ?? "").map(scripts.isAllowed) == true)
        }
        return builder.build(.init(snapshot: snapshot, now: now, volume: volume, brightness: brightness, outputs: outputs,
                                   notice: notice(snapshot), artwork: artwork, sourceName: source?.name,
                                   sourceIconPNG: source?.png, canSeek: seekable))
    }

    /// Why the phone sees less than it could, nil when all is well.
    func notice(_ snapshot: NowPlayingSnapshot?) -> MediaNotice? {
        let denied = runningPlayers().filter(scripts.isDenied)
        MediaPermissions.shared.update(denied: denied.map(\.name))
        if snapshot == nil, let player = denied.first {
            return MediaNotice(kind: MediaNotice.automationDenied,
                               message: "To show what \(player.name) is playing, allow Glasspad to control \(player.name) in System Settings > Privacy & Security > Automation on your Mac.",
                               app: player.name)
        }
        if snapshot == nil, case .unavailable(let why) = adapter.status, remote.needsAdapter {
            return MediaNotice(kind: MediaNotice.unavailable, message: "Song details are not available on this Mac (\(why)).")
        }
        return nil
    }

    private func outputs() -> [MediaOutput] {
        let now = Date()
        if let cache = outputsCache, now.timeIntervalSince(cache.at) < 3 { return cache.list }
        let list = MediaOutputs.list()
        outputsCache = (now, list)
        return list
    }

    private func appInfo(_ bundleID: String) -> (name: String?, png: Data?) {
        if let cached = iconCache[bundleID] { return cached }
        let ws = NSWorkspace.shared
        guard let url = ws.urlForApplication(withBundleIdentifier: bundleID) else {
            iconCache[bundleID] = (nil, nil)
            return (nil, nil)
        }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        let info = (name: Optional(name), png: DockMode.renderPNG(ws.icon(forFile: url.path), pixels: 120))
        iconCache[bundleID] = info
        return info
    }

    // MARK: Sources

    func adapterEvent(_ event: AdapterStreamParser.Event) {
        switch event {
        case .snapshot(let s):
            adapterSnapshot = s
            adapterReportedNothingSince = nil
        case .nothing:
            adapterSnapshot = nil
            if adapterReportedNothingSince == nil { adapterReportedNothingSince = Date() }
        case .failed:
            adapterSnapshot = nil
        }
        changed()
    }

    /// Fills gaps the adapter leaves, once a second while Media shows.
    func pollFallbacks(now: Date = Date()) {
        guard active, !polling else { return }
        let adapterWorks = adapter.isRunning || adapter.status == .starting
        let players = runningPlayers()
        let targets = scriptTargets(players: players, adapterWorks: adapterWorks, now: now)
        let askInProcess = useInProcessRemote && !adapterWorks && adapterSnapshot == nil && !remote.needsAdapter
        guard !targets.isEmpty || askInProcess else {
            if scriptSnapshot != nil {
                scriptSnapshot = nil
                changed()
            }
            return
        }
        polling = true
        Task { [weak self] in
            guard let self else { return }
            var inProcess: NowPlayingSnapshot?
            if askInProcess { inProcess = await self.remote.snapshot() }
            var polled: [(ScriptablePlayer, NowPlayingSnapshot?)] = []
            for target in targets {
                polled.append((target, await self.scripts.poll(target, now: now)))
                self.scripts.noteDecision(target)
            }
            let script = self.pickPlaying(polled)
            self.polling = false
            guard self.active else { return }
            if inProcess != self.inProcessSnapshot || script != self.scriptSnapshot {
                self.inProcessSnapshot = inProcess
                self.scriptSnapshot = script
                self.changed()
            } else {
                // A newly denied permission changes the notice.
                self.changed()
            }
        }
    }

    /// Which scriptable players to ask. With the adapter playing something, only that player,
    /// and only when it is already allowed (so no consent prompt), for artwork the adapter lacks.
    /// Without adapter data, every running player not refused is asked (the first time, macOS
    /// shows its consent prompt), so the one actually playing can be found: asking only the first
    /// showed Spotify while Music played, and "pause" then started Spotify on top of Music.
    func scriptTargets(players: [ScriptablePlayer], adapterWorks: Bool, now: Date) -> [ScriptablePlayer] {
        if let s = adapterSnapshot {
            guard s.artworkData == nil, let p = ScriptablePlayer(rawValue: s.sourceBundleID ?? ""), players.contains(p),
                  scripts.isAllowed(p) else { return [] }
            return [p]
        }
        if !adapterWorks || now.timeIntervalSince(adapterReportedNothingSince ?? now) >= 2 {
            return players.filter { !scripts.isDenied($0) }
        }
        return []
    }

    /// Of the players asked, the one to show and command: the one playing (the most recently
    /// playing one if several are), else the one last seen playing, else any with a track loaded.
    func pickPlaying(_ polled: [(ScriptablePlayer, NowPlayingSnapshot?)]) -> NowPlayingSnapshot? {
        let loaded = polled.compactMap { p, s in s.map { (p, $0) } }
        let playing = loaded.filter { $0.1.isPlaying }
        if let pick = playing.first(where: { $0.0 == lastPlayingPlayer }) ?? playing.first {
            // When both play, keep the one already followed; a newly started one wins next poll
            // only once the other stops.
            lastPlayingPlayer = pick.0
            return pick.1
        }
        if let last = lastPlayingPlayer, let s = loaded.first(where: { $0.0 == last }) { return s.1 }
        return loaded.first?.1
    }

    private func refreshSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            self?.pollFallbacks()
            self?.changed()
        }
    }

    private func changed() {
        guard active else { return }
        onChange()
    }

    private func loadArtwork(_ url: URL) {
        let fetch = fetchArtwork
        Task { [weak self] in
            let raw = await fetch(url)
            guard let self else { return }
            self.artworkCache.store(url: url, raw: raw)
            self.changed()
        }
    }

    // MARK: Live dependencies

    private static func liveRunningPlayers() -> [ScriptablePlayer] {
        ScriptablePlayer.allCases.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty }
    }

    private static let liveFetchArtwork: @Sendable (URL) async -> Data? = { url in
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode ?? 200 == 200 else { return nil }
        return data
    }
}

/// Artwork prepared for the phone, by source: raw MediaRemote data or a downloaded URL.
struct ArtworkCache {
    private var lastRaw: Data?
    private var lastPrepared: (id: String, data: Data)?
    private var byURL: [URL: (id: String, data: Data)] = [:]
    private var loading: Set<URL> = []
    private var failed: Set<URL> = []

    /// The artwork for this snapshot if ready, and a URL to download when it is one not seen yet.
    mutating func artwork(for s: NowPlayingSnapshot) -> (ready: (id: String, data: Data)?, load: URL?) {
        if let raw = s.artworkData {
            if raw == lastRaw { return (lastPrepared, nil) }
            lastRaw = raw
            lastPrepared = ArtworkEncoder.prepare(raw).map { (ArtworkEncoder.id(for: raw), $0) }
            return (lastPrepared, nil)
        }
        guard let url = s.artworkURL else { return (nil, nil) }
        if let ready = byURL[url] { return (ready, nil) }
        if !loading.contains(url), !failed.contains(url) {
            loading.insert(url)
            return (nil, url)
        }
        return (nil, nil)
    }

    mutating func store(url: URL, raw: Data?) {
        loading.remove(url)
        guard let raw, let prepared = ArtworkEncoder.prepare(raw) else {
            failed.insert(url)
            return
        }
        if byURL.count > 16 { byURL.removeAll() }
        byURL[url] = (ArtworkEncoder.id(for: raw), prepared)
    }
}

/// Automation permissions Media mode was refused, for the Mac app's menu.
@MainActor
public final class MediaPermissions: ObservableObject {
    public static let shared = MediaPermissions()
    /// Player names, e.g. ["Spotify"].
    @Published public private(set) var deniedApps: [String] = []

    func update(denied: [String]) {
        if denied != deniedApps { deniedApps = denied }
    }

    /// Opens System Settings at Privacy & Security > Automation.
    public func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// MediaRemote.framework, loaded at runtime. Symbol names are long-standing and widely used
/// (e.g. by open-source now-playing tools); every call checks the symbol exists.
final class MediaRemote: @unchecked Sendable {
    static let shared = MediaRemote()

    private typealias SendCommandFn = @convention(c) (Int32, CFDictionary?) -> Bool
    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void

    private let sendCommand: SendCommandFn?
    private let getInfo: GetInfoFn?

    private init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        sendCommand = handle.flatMap { dlsym($0, "MRMediaRemoteSendCommand") }.map { unsafeBitCast($0, to: SendCommandFn.self) }
        getInfo = handle.flatMap { dlsym($0, "MRMediaRemoteGetNowPlayingInfo") }.map { unsafeBitCast($0, to: GetInfoFn.self) }
    }

    var available: Bool { sendCommand != nil }

    /// Since macOS 15.4 MediaRemote returns no now-playing info to processes outside Apple, so
    /// Glasspad reads it through the perl helper instead (see NowPlayingAdapter).
    let needsAdapter = ProcessInfo.processInfo.isOperatingSystemAtLeast(
        OperatingSystemVersion(majorVersion: 15, minorVersion: 4, patchVersion: 0))

    /// Now playing read in this process (works before macOS 15.4).
    @MainActor
    func snapshot() async -> NowPlayingSnapshot? {
        await withCheckedContinuation { continuation in
            nowPlaying { info in continuation.resume(returning: info.flatMap(Self.snapshot(from:))) }
        }
    }

    nonisolated static func snapshot(from info: [String: Any]) -> NowPlayingSnapshot? {
        guard let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String, !title.isEmpty else { return nil }
        let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double
        return NowPlayingSnapshot(
            provider: .mediaRemote, title: title, artist: info["kMRMediaRemoteNowPlayingInfoArtist"] as? String,
            album: info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String,
            duration: info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double,
            elapsed: info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double,
            elapsedAt: info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date, playbackRate: rate,
            isPlaying: (rate ?? 0) > 0, artworkData: info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data)
    }

    /// MRMediaRemoteCommand values: play 0, pause 1, togglePlayPause 2, nextTrack 4, previousTrack 5.
    func send(_ c: MediaCommand) -> Bool {
        let code: Int32
        switch c {
        case .play: code = 0
        case .pause: code = 1
        case .playPause: code = 2
        case .nextTrack: code = 4
        case .previousTrack: code = 5
        case .mute: return false
        }
        return sendCommand?(code, nil) ?? false
    }

    func nowPlaying(_ done: @escaping @MainActor ([String: Any]?) -> Void) {
        guard let getInfo else {
            Task { @MainActor in done(nil) }
            return
        }
        getInfo(DispatchQueue.main) { dict in
            nonisolated(unsafe) let info = dict as? [String: Any]
            MainActor.assumeIsolated { done(info) }
        }
    }
}

/// Default output device volume and mute through CoreAudio (public).
enum AudioOutput {
    static func defaultDevice() -> AudioObjectID? {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                   mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    static func volume() -> Float? {
        guard let dev = defaultDevice() else { return nil }
        var addr = volumeAddress
        var v = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr ? v : nil
    }

    static func setVolume(_ v: Float) {
        guard let dev = defaultDevice() else { return }
        var addr = volumeAddress
        var value = Float32(v)
        AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static func isMuted() -> Bool? {
        guard let dev = defaultDevice() else { return nil }
        var addr = muteAddress
        var v = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr ? v != 0 : nil
    }

    static func setMuted(_ muted: Bool) {
        guard let dev = defaultDevice() else { return }
        var addr = muteAddress
        var v = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
    }
}

/// Main display brightness through DisplayServices.framework (private, dlopen). Returns nil when
/// the framework or display does not support it (external monitors usually do not).
enum Brightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private nonisolated(unsafe) static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    static func get() -> Float? {
        guard let h = handle, let sym = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        var v: Float = 0
        return unsafeBitCast(sym, to: GetFn.self)(CGMainDisplayID(), &v) == 0 ? v : nil
    }

    static func set(_ v: Float) {
        guard let h = handle, let sym = dlsym(h, "DisplayServicesSetBrightness") else { return }
        _ = unsafeBitCast(sym, to: SetFn.self)(CGMainDisplayID(), v)
    }
}
