import AppKit
import Foundation
import GlasspadKit
import Testing
@testable import GlasspadMacCore

/// Scripted AppleScript results; records every script so tests can check none ran.
final class FakeAppleScriptRunner: AppleScriptRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _scripts: [String] = []
    var replies: [(match: String, outcome: AppleScriptOutcome)] = []
    var permissions: [String: Bool] = [:]

    var scripts: [String] { lock.withLock { _scripts } }

    func run(_ source: String) async -> AppleScriptOutcome {
        lock.withLock { _scripts.append(source) }
        return replies.first { source.contains($0.match) }?.outcome ?? .failed(code: -600, message: "not running")
    }

    func permission(for bundleID: String) -> Bool? { permissions[bundleID] }
}

private func line(_ payload: String, diff: Bool = false) -> String {
    #"{"type":"data","diff":\#(diff),"payload":\#(payload)}"#
}

private let sep = ScriptablePlayer.separator

@Suite struct AdapterParserTests {
    @Test func fullPayloadInMicroseconds() throws {
        var parser = AdapterStreamParser()
        let art = Data([0xFF, 0xD8, 0xFF, 0x01]).base64EncodedString()
        let event = parser.consume(line("""
        {"title":"Teardrop","artist":"Massive Attack","album":"Mezzanine","playing":true,"playbackRate":1,
         "durationMicros":330000000,"elapsedTimeMicros":12500000,"timestampEpochMicros":1700000000000000,
         "bundleIdentifier":"com.spotify.client","applicationName":"Spotify","artworkData":"\(art)",
         "shuffleMode":3,"repeatMode":2}
        """.replacingOccurrences(of: "\n", with: "")))
        guard case .snapshot(let s) = event else { Issue.record("no snapshot: \(String(describing: event))"); return }
        #expect(s.title == "Teardrop")
        #expect(s.artist == "Massive Attack")
        #expect(s.duration == 330)
        #expect(s.elapsed == 12.5)
        #expect(s.elapsedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(s.isPlaying)
        #expect(s.bundleID == "com.spotify.client")
        #expect(s.appName == "Spotify")
        #expect(s.artworkData == Data([0xFF, 0xD8, 0xFF, 0x01]))
        #expect(s.shuffle == true)
        #expect(s.repeatMode == .one)
        #expect(s.provider == .mediaRemote)
    }

    @Test func upstreamSecondsAndISOTimestamp() {
        var parser = AdapterStreamParser()
        let event = parser.consume(line(#"{"title":"Song","playing":false,"duration":200.5,"elapsedTime":3,"timestamp":"2025-01-02T03:04:05Z","parentApplicationBundleIdentifier":"com.google.Chrome","bundleIdentifier":"com.google.Chrome.helper"}"#))
        guard case .snapshot(let s) = event else { Issue.record("no snapshot"); return }
        #expect(s.duration == 200.5)
        #expect(s.elapsed == 3)
        #expect(s.elapsedAt == ISO8601DateFormatter().date(from: "2025-01-02T03:04:05Z"))
        #expect(!s.isPlaying)
        #expect(s.sourceBundleID == "com.google.Chrome")
    }

    @Test func diffUpdatesAndNullRemoves() {
        var parser = AdapterStreamParser()
        _ = parser.consume(line(#"{"title":"A","artist":"X","album":"Y","playing":true}"#))
        let event = parser.consume(line(#"{"playing":false,"album":null}"#, diff: true))
        guard case .snapshot(let s) = event else { Issue.record("no snapshot"); return }
        #expect(s.title == "A")
        #expect(s.artist == "X")
        #expect(s.album == nil)
        #expect(!s.isPlaying)
    }

    @Test func nullPayloadIsNothingAndErrorsFail() {
        var parser = AdapterStreamParser()
        #expect(parser.consume(line("null")) == .nothing)
        #expect(parser.consume(line(#"{"title":"","playing":true}"#)) == .nothing)
        #expect(parser.consume(#"{"type":"error","message":"MediaRemote refused"}"#) == .failed("MediaRemote refused"))
        #expect(parser.consume("not json") == nil)
        #expect(parser.consume("") == nil)
        #expect(parser.consume(#"{"type":"other"}"#) == nil)
    }

    @Test func playingFallsBackToRateAndBooleansAreNotNumbers() {
        var parser = AdapterStreamParser()
        guard case .snapshot(let s) = parser.consume(line(#"{"title":"T","playbackRate":1,"shuffleMode":true}"#)) else {
            Issue.record("no snapshot"); return
        }
        #expect(s.isPlaying)
        #expect(s.shuffle == nil)
    }

    @Test func commandLines() {
        #expect(AdapterCommand.send(2).line == "send 2")
        #expect(AdapterCommand.seek(61.25).line == "seek 61.250")
        #expect(AdapterCommand.seek(-3).line == "seek 0.000")
        #expect(AdapterCommand.shuffle(true).line == "shuffle 3")
        #expect(AdapterCommand.setRepeat(.all).line == "repeat 3")
        #expect(AdapterCommand.setRepeat(.one).line == "repeat 2")
        #expect(AdapterCommand.code(for: .playPause) == 2)
        #expect(AdapterCommand.code(for: .mute) == nil)
    }

    @Test func loaderNamesTheEntryPoint() throws {
        #expect(NowPlayingAdapter.loader.contains("glasspad_nowplaying_run"))
        #expect(NowPlayingAdapter.loader.contains("DynaLoader::dl_install_xsub"))
    }
}

/// The helper restart policy, with a fake helper (/bin/sh) instead of perl.
@MainActor @Suite(.serialized) struct AdapterRestartTests {
    /// Says "nothing is playing", then dies right after. The short pause lets the line be read
    /// first: output still in the pipe when the helper exits can be lost (the termination
    /// handler drops the reader), which made this test fail now and then under load.
    static func crashingHelper(_ library: URL) -> (executable: URL, arguments: [String]) {
        (URL(fileURLWithPath: "/bin/sh"), ["-c", #"echo '{"type":"data","diff":false,"payload":null}'; sleep 0.05; exit 3"#])
    }

    func waitFor(_ seconds: Double, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if cond() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return cond()
    }

    /// A helper that reports "nothing" and then crashes used to reset the restart counter with
    /// its output, so it was restarted about once a second forever. Now only a run that stays up
    /// counts as healthy: the pauses grow and Glasspad gives up.
    @Test func crashAfterNothingStillGivesUp() async {
        let adapter = NowPlayingAdapter(library: URL(fileURLWithPath: "/dev/null"), launcher: Self.crashingHelper)
        adapter.restartDelays = [0.05, 0.1, 0.2]
        var events: [AdapterStreamParser.Event] = []
        adapter.onEvent = { events.append($0) }
        adapter.start()
        #expect(await waitFor(6) {
            if case .unavailable = adapter.status { return true }
            return false
        })
        #expect(adapter.launches == NowPlayingAdapter.maxQuickRestarts + 1)
        #expect(events.contains(.nothing))
        if case .unavailable(let why) = adapter.status { #expect(why.contains("keeps stopping")) }
        // Given up means given up: no more launches.
        let launches = adapter.launches
        try? await Task.sleep(for: .milliseconds(400))
        #expect(adapter.launches == launches)
        adapter.stop()
    }

    /// A helper that ran for a good while before it died is restarted with a short pause again.
    @Test func longRunResetsTheBackoff() async {
        let adapter = NowPlayingAdapter(library: URL(fileURLWithPath: "/dev/null"), launcher: { _ in
            (URL(fileURLWithPath: "/bin/sh"), ["-c", "sleep 0.3; exit 1"])
        })
        adapter.restartDelays = [0.05]
        adapter.stableRun = 0.2
        adapter.start()
        // About 3 s of restarts; the margin is for a busy machine (it returns as soon as they happen).
        #expect(await waitFor(15) { adapter.launches >= NowPlayingAdapter.maxQuickRestarts + 3 })
        if case .unavailable(let why) = adapter.status { Issue.record("gave up: \(why)") }
        adapter.stop()
    }
}

@Suite struct AppleScriptParsingTests {
    let now = Date(timeIntervalSince1970: 1000)

    /// Scripting-addition commands run on the main thread even when the script does not; the
    /// player scripts must not need one, so they never wait on the pointer's thread.
    @Test func playerScriptsUseNoScriptingAdditions() {
        for p in ScriptablePlayer.allCases {
            let all = [p.statusScript, p.artworkScript ?? "", p.volumeScript(0.5)]
                + MediaCommand.allCases.compactMap(p.commandScript)
            for script in all {
                for addition in ["ASCII character", "ASCII number", "display dialog", "do shell script", "offset of"] {
                    #expect(!script.contains(addition), "\(p.name) script uses \(addition)")
                }
            }
        }
    }

    @Test func spotifyLine() {
        let text = ["playing", "Paranoid Android", "Radiohead", "OK Computer", "387000", "12,5",
                    "https://i.scdn.co/image/abc", "false", "true", "spotify:track:1", "80"].joined(separator: sep)
        let s = ScriptablePlayer.spotify.parseStatus(text, now: now)
        #expect(s?.title == "Paranoid Android")
        #expect(s?.duration == 387)
        #expect(s?.elapsed == 12.5)
        #expect(s?.isPlaying == true)
        #expect(s?.artworkURL == URL(string: "https://i.scdn.co/image/abc"))
        #expect(s?.shuffle == false)
        #expect(s?.repeatMode == .all)
        #expect(s?.trackID == "spotify:track:1")
        #expect(s?.bundleID == "com.spotify.client")
        #expect(s?.elapsedAt == now)
    }

    @Test func musicLine() {
        let text = ["paused", "Hey Jude", "The Beatles", "1", "431.2", "100.0", "", "true", "one", "ABC123", "50"]
            .joined(separator: sep)
        let s = ScriptablePlayer.music.parseStatus(text, now: now)
        #expect(s?.duration == 431.2)
        #expect(s?.isPlaying == false)
        #expect(s?.playbackRate == 0)
        #expect(s?.artworkURL == nil)
        #expect(s?.repeatMode == .one)
        #expect(s?.shuffle == true)
    }

    @Test func nothingLoaded() {
        #expect(ScriptablePlayer.spotify.parseStatus("stopped", now: now) == nil)
        #expect(ScriptablePlayer.spotify.parseStatus("notRunning", now: now) == nil)
        let empty = ["playing", "", "", "", "0", "0", "", "false", "false", "", "0"].joined(separator: sep)
        #expect(ScriptablePlayer.music.parseStatus(empty, now: now) == nil)
    }

    @Test func scriptsNeverLaunchThePlayer() {
        for player in ScriptablePlayer.allCases {
            #expect(player.statusScript.hasPrefix("if application id \"\(player.bundleID)\" is not running"))
            for command in MediaCommand.allCases {
                guard let script = player.commandScript(command) else { continue }
                #expect(script.contains("is running then"))
            }
        }
        #expect(ScriptablePlayer.spotify.controlScript(.seek(30))?.contains("set player position to 30.00") == true)
        #expect(ScriptablePlayer.music.controlScript(.setRepeat(.all))?.contains("set song repeat to all") == true)
        #expect(ScriptablePlayer.spotify.controlScript(.setRepeat(.one))?.contains("set repeating to true") == true)
        #expect(ScriptablePlayer.spotify.controlScript(.selectOutput(id: "x")) == nil)
    }
}

@Suite struct NowPlayingMergeTests {
    func snap(_ provider: NowPlayingSnapshot.Provider, _ title: String, art: Data? = nil, url: URL? = nil,
              bundle: String = "com.spotify.client") -> NowPlayingSnapshot {
        NowPlayingSnapshot(provider: provider, title: title, artist: "A", isPlaying: true, bundleID: bundle,
                           artworkData: art, artworkURL: url)
    }

    @Test func adapterWinsAndScriptFillsArtwork() {
        let url = URL(string: "https://i.scdn.co/image/x")!
        let merged = NowPlayingMerger.merge(adapter: snap(.mediaRemote, "Song"), script: snap(.spotify, "Song", url: url))
        #expect(merged?.provider == .mediaRemote)
        #expect(merged?.artworkURL == url)
    }

    @Test func otherSongArtworkIsIgnored() {
        let url = URL(string: "https://i.scdn.co/image/x")!
        let merged = NowPlayingMerger.merge(adapter: snap(.mediaRemote, "New"), script: snap(.spotify, "Old", url: url))
        #expect(merged?.title == "New")
        #expect(merged?.artworkURL == nil)
    }

    @Test func scriptStandsInWithoutAdapter() {
        #expect(NowPlayingMerger.merge(adapter: nil, script: snap(.music, "M"))?.provider == .music)
        #expect(NowPlayingMerger.merge(adapter: nil, script: nil) == nil)
    }

    @Test func elapsedAdvancesOnlyWhilePlaying() {
        let t0 = Date(timeIntervalSince1970: 0)
        var s = NowPlayingSnapshot(provider: .mediaRemote, title: "T", duration: 100, elapsed: 10, elapsedAt: t0,
                                   playbackRate: 1, isPlaying: true)
        #expect(s.elapsed(at: t0.addingTimeInterval(5)) == 15)
        #expect(s.elapsed(at: t0.addingTimeInterval(500)) == 100)
        s.isPlaying = false
        #expect(s.elapsed(at: t0.addingTimeInterval(5)) == 10)
    }
}

@Suite struct MediaWireBuilderTests {
    func need(_ s: MediaState?) throws -> MediaState { try #require(s) }

    let t0 = Date(timeIntervalSince1970: 0)

    func inputs(_ s: NowPlayingSnapshot?, at: Date, volume: Double = 0.5, art: (String, Data)? = ("a1", Data([1, 2, 3])),
                icon: Data? = Data([9])) -> MediaWireBuilder.Inputs {
        .init(snapshot: s, now: at, volume: volume, brightness: nil, outputs: nil, notice: nil,
              artwork: art.map { (id: $0.0, data: $0.1) }, sourceName: "Spotify", sourceIconPNG: icon, canSeek: true)
    }

    var playing: NowPlayingSnapshot {
        NowPlayingSnapshot(provider: .mediaRemote, title: "T", artist: "", duration: 200, elapsed: 10, elapsedAt: t0,
                           playbackRate: 1, isPlaying: true, bundleID: "com.spotify.client")
    }

    @Test func artworkAndIconGoOncePerSession() throws {
        var b = MediaWireBuilder()
        let first = try need(b.build(inputs(playing, at: t0)))
        #expect(first.artworkPNG == Data([1, 2, 3]))
        #expect(first.artworkID == "a1")
        #expect(first.sourceIconPNG == Data([9]))
        #expect(first.artist == nil)
        // Same state again: nothing to send.
        #expect(b.build(inputs(playing, at: t0)) == nil)
        // Something else changed: sent, without the artwork and icon the phone already has.
        let louder = try need(b.build(inputs(playing, at: t0, volume: 0.9)))
        #expect(louder.artworkPNG == nil)
        #expect(louder.artworkID == "a1")
        #expect(louder.sourceIconPNG == nil)
        b.reset()
        #expect(b.build(inputs(playing, at: t0))?.artworkPNG != nil)
    }

    @Test func positionIsAlwaysTrueAndPredictableTicksAreSkipped() throws {
        var b = MediaWireBuilder()
        let a = try need(b.build(inputs(playing, at: t0.addingTimeInterval(1))))
        #expect(a.elapsed == 11)
        #expect(b.build(inputs(playing, at: t0.addingTimeInterval(4))) == nil)
        // Another change goes out with the true position, never a stale one.
        let c = try need(b.build(inputs(playing, at: t0.addingTimeInterval(5), volume: 0.1)))
        #expect(c.elapsed == 15)
        // A seek is not predictable: the new position goes out.
        var seeked = playing
        seeked.elapsed = 100
        seeked.elapsedAt = t0.addingTimeInterval(6)
        #expect(b.build(inputs(seeked, at: t0.addingTimeInterval(6), volume: 0.1))?.elapsed == 100)
    }

    @Test func pausedHasRateZero() throws {
        var b = MediaWireBuilder()
        var paused = playing
        paused.isPlaying = false
        let s = try need(b.build(inputs(paused, at: t0.addingTimeInterval(30))))
        #expect(s.playbackRate == 0)
        #expect(s.elapsed == 10)
        #expect(!s.isPlaying)
        #expect(b.build(inputs(paused, at: t0.addingTimeInterval(60))) == nil)
    }

    @Test func nothingPlayingKeepsVolume() throws {
        var b = MediaWireBuilder()
        let s = try need(b.build(inputs(nil, at: t0)))
        #expect(s.title == nil)
        #expect(s.volume == 0.5)
        #expect(s.artworkID == nil)
    }

    @Test func artworkEncoderPassesSmallJPEGAndShrinksBigOnes() throws {
        let small = try jpeg(size: 300)
        #expect(ArtworkEncoder.prepare(small) == small)
        let big = try jpeg(size: 2000)
        let out = try #require(ArtworkEncoder.prepare(big))
        let rep = try #require(NSBitmapImageRep(data: out))
        #expect(max(rep.pixelsWide, rep.pixelsHigh) == ArtworkEncoder.maxPixels)
        #expect(ArtworkEncoder.id(for: small) == ArtworkEncoder.id(for: small))
        #expect(ArtworkEncoder.id(for: small) != ArtworkEncoder.id(for: big))
        #expect(ArtworkEncoder.prepare(Data([1, 2, 3])) == nil)
    }

    private func jpeg(size: Int) throws -> Data {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]))
    }
}

@MainActor
@Suite(.serialized) struct MediaModeSourceTests {
    let spotifyLine = ["playing", "Song", "Artist", "Album", "200000", "5", "", "false", "false", "id1", "50"]
        .joined(separator: ScriptablePlayer.separator)

    func make(_ runner: FakeAppleScriptRunner, players: [ScriptablePlayer] = [.spotify]) -> MediaMode {
        MediaMode(poster: CapturingEventPoster(), adapter: NowPlayingAdapter(library: nil), runner: runner,
                  runningPlayers: { players })
    }

    func settle(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func adapterEventsDriveTheState() async {
        let runner = FakeAppleScriptRunner()
        let mode = make(runner, players: [])
        var changes = 0
        mode.onChange = { changes += 1 }
        mode.setActive(true)
        var parser = AdapterStreamParser()
        mode.adapterEvent(parser.consume(line(#"{"title":"Live","artist":"Band","playing":true,"durationMicros":60000000,"elapsedTimeMicros":1000000}"#))!)
        let state = mode.makeState(now: Date(), volume: nil, brightness: nil, outputs: nil)
        #expect(state?.title == "Live")
        #expect(state?.isPlaying == true)
        #expect(changes >= 1)
        mode.adapterEvent(.nothing)
        #expect(mode.makeState(now: Date(), volume: nil, brightness: nil, outputs: nil)?.title == nil)
        mode.setActive(false)
        #expect(runner.scripts.isEmpty)
    }

    @Test func spotifyFallbackWhenAdapterIsUnavailable() async {
        let runner = FakeAppleScriptRunner()
        runner.replies = [("player state", .text(spotifyLine))]
        runner.permissions = ["com.spotify.client": true]
        let mode = make(runner)
        mode.setActive(true)
        await settle { mode.current != nil }
        let state = mode.makeState(now: Date(), volume: nil, brightness: nil, outputs: nil)
        #expect(state?.title == "Song")
        #expect(state?.duration == 200)
        #expect(state?.canSeek == true)
        #expect(state?.notice == nil)
        mode.setActive(false)
    }

    @Test func deniedAutomationGivesANoticeAndStopsAsking() async {
        let runner = FakeAppleScriptRunner()
        runner.replies = [("player state", .failed(code: AppleScriptOutcome.notPermitted, message: "Not authorized"))]
        runner.permissions = ["com.spotify.client": false]
        let mode = make(runner)
        mode.setActive(true)
        await settle { !runner.scripts.isEmpty }
        await settle { mode.notice(nil) != nil }
        let state = mode.makeState(now: Date(), volume: nil, brightness: nil, outputs: nil)
        #expect(state?.title == nil)
        #expect(state?.notice?.kind == MediaNotice.automationDenied)
        #expect(state?.notice?.app == "Spotify")
        #expect(state?.notice?.message.contains("Automation") == true)
        #expect(MediaPermissions.shared.deniedApps == ["Spotify"])
        let asked = runner.scripts.count
        mode.pollFallbacks()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(runner.scripts.count == asked)
        mode.setActive(false)
    }

    @Test func noPromptWhileAdapterPlaysUndecidedApp() {
        let runner = FakeAppleScriptRunner()
        let mode = make(runner)
        mode.setActive(true)
        mode.adapterEvent(.snapshot(NowPlayingSnapshot(provider: .mediaRemote, title: "T", isPlaying: true,
                                                       bundleID: "com.spotify.client")))
        // Permission undecided (nil): asking would show the consent prompt, so nothing is asked.
        #expect(mode.scriptTargets(players: [.spotify], adapterWorks: true, now: Date()).isEmpty)
        runner.permissions = ["com.spotify.client": true]
        #expect(mode.scriptTargets(players: [.spotify], adapterWorks: true, now: Date()) == [.spotify])
        mode.setActive(false)
    }

    /// Reliability M5: with Music playing and Spotify open but paused, the fallback showed and
    /// commanded Spotify (first in the list), so "pause" started Spotify on top of Music.
    @Test func bothPlayersOpenFollowsTheOneThatPlays() async {
        let runner = FakeAppleScriptRunner()
        let spotifyPaused = ["paused", "Old Song", "S", "A", "200000", "5", "", "false", "false", "s1", "50"]
            .joined(separator: ScriptablePlayer.separator)
        let musicPlaying = ["playing", "Live Song", "M", "B", "100", "1", "", "false", "off", "m1", "40"]
            .joined(separator: ScriptablePlayer.separator)
        // Each status script names only its own player's properties.
        runner.replies = [("repeating as string", .text(spotifyPaused)), ("song repeat as string", .text(musicPlaying))]
        runner.permissions = ["com.spotify.client": true, "com.apple.Music": true]
        let mode = make(runner, players: [.spotify, .music])
        mode.setActive(true)
        await settle { mode.current != nil }
        #expect(mode.current?.title == "Live Song")
        #expect(mode.current?.sourceBundleID == ScriptablePlayer.music.bundleID)
        let before = runner.scripts.count
        mode.send(.pause)
        await settle { runner.scripts.count > before }
        let commands = runner.scripts.dropFirst(before).filter { $0.contains(" to pause") }
        #expect(commands.count == 1)
        #expect(commands.allSatisfy { $0.contains("com.apple.Music") && !$0.contains("com.spotify.client") })
        mode.setActive(false)
    }

    @Test func bothPausedFollowsTheOneLastPlaying() {
        let mode = make(FakeAppleScriptRunner(), players: [.spotify, .music])
        let spotify = NowPlayingSnapshot(provider: .spotify, title: "S", isPlaying: false, bundleID: ScriptablePlayer.spotify.bundleID)
        let musicOn = NowPlayingSnapshot(provider: .music, title: "M", isPlaying: true, bundleID: ScriptablePlayer.music.bundleID)
        var musicOff = musicOn
        musicOff.isPlaying = false
        #expect(mode.pickPlaying([(.spotify, spotify), (.music, musicOn)])?.title == "M")
        #expect(mode.pickPlaying([(.spotify, spotify), (.music, musicOff)])?.title == "M")   // paused Music stays the target
        #expect(mode.lastPlayingPlayer == .music)
    }

    @Test func musicArtworkIsFetchedOncePerTrack() async {
        let runner = FakeAppleScriptRunner()
        let musicLine = ["playing", "Song", "A", "B", "100", "1", "", "false", "off", "P1", "40"]
            .joined(separator: ScriptablePlayer.separator)
        runner.replies = [("raw data", .data(Data([7, 7]))), ("player state", .text(musicLine))]
        let scripts = AppleScriptNowPlaying(runner: runner)
        let a = await scripts.poll(.music)
        let b = await scripts.poll(.music)
        #expect(a?.artworkData == Data([7, 7]))
        #expect(b?.artworkData == Data([7, 7]))
        #expect(runner.scripts.filter { $0.contains("raw data") }.count == 1)
    }
}
