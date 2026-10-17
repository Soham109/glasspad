import Foundation
import GlasspadKit
import Testing
@testable import GlasspadMacCore

/// Where play/pause goes when the helper cannot take it, and what the activity log records.
/// Case from a real report: YouTube played in a browser, Spotify sat paused, and Remote
/// play/pause stopped working for a few minutes.
@MainActor
@Suite(.serialized) struct MediaRoutingTests {
    let spotifyPaused = ["paused", "Song", "Artist", "Album", "200000", "5", "", "false", "false", "s1", "50"]
        .joined(separator: ScriptablePlayer.separator)
    let spotifyPlaying = ["playing", "Song", "Artist", "Album", "200000", "5", "", "false", "false", "s1", "50"]
        .joined(separator: ScriptablePlayer.separator)

    final class Remote {
        var commands: [MediaCommand] = []
    }

    struct Rig {
        let mode: MediaMode
        let runner: FakeAppleScriptRunner
        let poster: CapturingEventPoster
        let remote: Remote
        let log: ActivityLog

        var commandScripts: [String] {
            // Command scripts are one "tell application id ... to <verb>" line.
            runner.scripts.filter { $0.contains("\" to ") }
        }
        var mediaKeys: Int { poster.events.filter { $0.type.rawValue == 14 }.count }   // NSSystemDefined
    }

    /// No helper library, so the adapter is unavailable, as when the helper gave up.
    func rig(spotify line: String?, remoteAnswers: Bool = false) -> Rig {
        let runner = FakeAppleScriptRunner()
        if let line { runner.replies = [("player state", .text(line))] }
        runner.permissions = ["com.spotify.client": true]
        let poster = CapturingEventPoster()
        let mode = MediaMode(poster: poster, adapter: NowPlayingAdapter(library: nil), runner: runner,
                             runningPlayers: { [.spotify] })
        let remote = Remote()
        mode.system = MediaMode.SystemControls(sendRemote: { remote.commands.append($0); return true },
                                               setVolume: { _ in }, isMuted: { false }, setMuted: { _ in },
                                               setBrightness: { _ in }, selectOutput: { _ in },
                                               remoteAnswersThisProcess: remoteAnswers,
                                               frontmostApp: { "com.google.Chrome" })
        let log = ActivityLog()
        log.start(at: tempURL("activity.log"))
        mode.activityLog = log
        return Rig(mode: mode, runner: runner, poster: poster, remote: remote, log: log)
    }

    func settle(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    func chrome(playing: Bool) -> NowPlayingSnapshot {
        NowPlayingSnapshot(provider: .mediaRemote, title: "Video", isPlaying: playing, bundleID: "com.google.Chrome")
    }

    /// The browser was the Mac's now playing, then the helper stopped: the paused Spotify that
    /// the fallback then shows must not get "playpause" (that started Spotify over the video).
    @Test func pausedSpotifyIsNotTheTargetAfterABrowserPlayed() async {
        let r = rig(spotify: spotifyPaused)
        r.mode.setActive(true)
        r.mode.adapterEvent(.snapshot(chrome(playing: true)))
        r.mode.adapterStatusChanged(.unavailable("The now-playing helper keeps stopping (exit 3)"))
        r.mode.pollFallbacks()
        await settle { r.mode.current?.sourceBundleID == ScriptablePlayer.spotify.bundleID }
        #expect(r.mode.current?.isPlaying == false)
        #expect(r.mode.lastNowPlayingSource == "com.google.Chrome")
        #expect(r.mode.commandScriptTarget == nil)

        r.mode.send(.playPause)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(r.commandScripts.isEmpty)
        #expect(r.mediaKeys == 2)   // key down and up, to the Mac's now playing
        r.log.flush()
        #expect(r.log.contents().contains("media cmd=playPause route=mediaKey ok=true np=com.spotify.client playing=false mr=com.google.Chrome front=com.google.Chrome helper=unavailable"))
        r.mode.setActive(false)
    }

    /// Spotify on its own is unchanged: with no other now playing app, AppleScript reaches it.
    @Test func spotifyAloneStillGetsAppleScript() async {
        let r = rig(spotify: spotifyPaused)
        r.mode.setActive(true)
        await settle { r.mode.current != nil }
        #expect(r.mode.commandScriptTarget == .spotify)
        r.runner.replies.append(("playpause", .text("")))
        r.mode.send(.playPause)
        await settle { !r.commandScripts.isEmpty }
        #expect(r.commandScripts.count == 1)
        #expect(r.commandScripts.allSatisfy { $0.contains("com.spotify.client") && $0.contains("playpause") })
        #expect(r.mediaKeys == 0)
        await settle { r.log.contents().contains("route=appleScript") }
        #expect(r.log.contents().contains("media cmd=playPause route=appleScript ok=true np=com.spotify.client"))
        r.mode.setActive(false)
    }

    /// The playing app wins: Spotify playing after a browser was now playing still gets it.
    @Test func playingSpotifyStillGetsAppleScript() async {
        let r = rig(spotify: spotifyPlaying)
        r.mode.setActive(true)
        r.mode.adapterEvent(.snapshot(chrome(playing: false)))
        r.mode.adapterStatusChanged(.unavailable("gone"))
        r.mode.pollFallbacks()
        await settle { r.mode.current?.isPlaying == true }
        #expect(r.mode.commandScriptTarget == .spotify)
        r.mode.send(.pause)
        await settle { !r.commandScripts.isEmpty }
        #expect(r.commandScripts.count == 1)
        #expect(r.mediaKeys == 0)
        r.mode.setActive(false)
    }

    /// MediaRemote "nothing playing" forgets the browser, so Spotify is the target again.
    @Test func nothingPlayingForgetsTheOtherApp() {
        let r = rig(spotify: nil)
        r.mode.setActive(true)
        r.mode.adapterEvent(.snapshot(chrome(playing: true)))
        #expect(r.mode.lastNowPlayingSource == "com.google.Chrome")
        r.mode.adapterEvent(.nothing)
        #expect(r.mode.lastNowPlayingSource == nil)
        r.mode.setActive(false)
    }

    /// What the helper said is only true while it runs: a stopped helper's snapshot used to stay
    /// on the phone and hide the fallbacks.
    @Test func helperStoppingDropsItsSnapshot() {
        let r = rig(spotify: nil)
        r.mode.setActive(true)
        r.mode.adapterEvent(.snapshot(chrome(playing: true)))
        #expect(r.mode.current?.sourceBundleID == "com.google.Chrome")
        r.mode.adapterStatusChanged(.starting)
        #expect(r.mode.current == nil)
        r.log.flush()
        #expect(r.log.contents().contains("media event=helper status=starting"))
        r.mode.setActive(false)
    }

    /// Since macOS 15.4 MediaRemote in this process ignores commands, so the media key goes.
    @Test func remoteInThisProcessOnlyWhereItAnswers() async {
        let old = rig(spotify: nil, remoteAnswers: true)
        old.mode.send(.nextTrack)
        #expect(old.remote.commands == [.nextTrack])
        #expect(old.mediaKeys == 0)

        let new = rig(spotify: nil, remoteAnswers: false)
        new.mode.send(.nextTrack)
        #expect(new.remote.commands.isEmpty)
        #expect(new.mediaKeys == 2)
        new.log.flush()
        #expect(new.log.contents().contains("media cmd=nextTrack route=mediaKey ok=true front=com.google.Chrome helper=stopped"))
    }

    /// The helper's answer to a send is logged and changes nothing else.
    @Test func sentAnswersAreLogged() {
        let r = rig(spotify: nil)
        r.mode.setActive(true)
        r.mode.adapterEvent(.snapshot(chrome(playing: true)))
        r.mode.adapterEvent(.sent(command: 2, ok: false))
        #expect(r.mode.current?.sourceBundleID == "com.google.Chrome")
        r.log.flush()
        let text = r.log.contents()
        #expect(text.contains("media event=nowPlaying app=com.google.Chrome"))
        #expect(text.contains("media event=sent command=2 ok=false"))
        // No titles in the log.
        #expect(!text.contains("Video"))
        r.mode.setActive(false)
    }

    @Test func parserReadsSentLines() {
        var parser = AdapterStreamParser()
        #expect(parser.consume(#"{"type":"sent","command":2,"ok":true}"#) == .sent(command: 2, ok: true))
        #expect(parser.consume(#"{"type":"sent","command":1,"ok":false}"#) == .sent(command: 1, ok: false))
        #expect(parser.consume(#"{"type":"sent"}"#) == nil)
    }

    /// The helper must keep its refresh timer alive (ARC freed a local one, so no first state
    /// and no 5 s refresh ever came). Checked in the source, since the helper runs only in perl.
    @Test func helperKeepsItsRefreshTimer() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Apps/Mac/Helpers/NowPlayingHelper.m")
        let text = try String(contentsOf: source, encoding: .utf8)
        #expect(text.contains("static dispatch_source_t gRefreshTimer;"))
        #expect(text.contains("gRefreshTimer = timer;"))
        #expect(text.contains(#"{\"type\":\"sent\""#))
    }
}
