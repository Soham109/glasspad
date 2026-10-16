import Foundation
import Testing
@testable import GlasspadKit

@Suite struct RemoteKeymapTests {
    private func key(_ c: String, _ m: KeyModifiers = []) -> Keystroke { Keystroke(key: .character(c), modifiers: m) }
    private func special(_ k: SpecialKey, _ m: KeyModifiers = []) -> Keystroke { Keystroke(key: .special(k), modifiers: m) }
    private let fullScreenShortcut = Keystroke(key: .character("f"), modifiers: [.command, .control])

    @Test func appsAreRecognised() {
        #expect(RemoteKeymap.player(bundleID: "com.apple.Safari") == .browser(.other))
        #expect(RemoteKeymap.player(bundleID: "company.thebrowser.Browser", nowPlaying: ["Stranger Things", "Netflix"]) == .browser(.netflix))
        #expect(RemoteKeymap.player(bundleID: "com.google.Chrome", nowPlaying: [nil, "www.youtube.com"]) == .browser(.youtube))
        #expect(RemoteKeymap.player(bundleID: "org.mozilla.firefox", nowPlaying: ["Prime Video: Reacher"]) == .browser(.primeVideo))
        #expect(RemoteKeymap.player(bundleID: "com.apple.Safari", nowPlaying: ["Disney+"]) == .browser(.disneyPlus))
        #expect(RemoteKeymap.player(bundleID: "com.apple.TV") == .appleTV)
        #expect(RemoteKeymap.player(bundleID: "com.apple.QuickTimePlayerX") == .quickTime)
        #expect(RemoteKeymap.player(bundleID: "com.colliderli.iina") == .iina)
        #expect(RemoteKeymap.player(bundleID: "org.videolan.vlc") == .vlc)
        #expect(RemoteKeymap.player(bundleID: "com.firecore.infuse") == .infuse)
        #expect(RemoteKeymap.player(bundleID: "com.spotify.client") == .music)
        #expect(RemoteKeymap.player(bundleID: "com.apple.Music") == .appleMusic)
        #expect(RemoteKeymap.player(bundleID: "com.apple.finder") == .other)
        #expect(RemoteKeymap.player(bundleID: nil) == .other)
    }

    @Test func aVideoAppInFrontWinsOtherwiseTheAppPlaying() {
        // The keys go to the frontmost app, so a video app in front decides.
        #expect(RemoteKeymap(frontmost: "com.apple.TV", playing: "com.spotify.client").player == .appleTV)
        // Finder in front, Spotify playing: Spotify's controls (play and skip reach it anyway).
        #expect(RemoteKeymap(frontmost: "com.apple.finder", playing: "com.spotify.client").player == .music)
        #expect(RemoteKeymap(frontmost: nil, playing: "com.colliderli.iina").player == .iina)
        #expect(RemoteKeymap(frontmost: "com.apple.finder", playing: nil).player == .other)
        // A browser left in front while Spotify plays: songs, not web keys.
        #expect(RemoteKeymap(frontmost: "com.apple.Safari", playing: "com.spotify.client").player == .music)
        #expect(RemoteKeymap(frontmost: "com.apple.Safari", playing: "com.apple.Safari", nowPlaying: ["Netflix"]).player == .browser(.netflix))
        #expect(RemoteKeymap(frontmost: "com.apple.Safari", playing: "com.example.unknown").player == .browser(.other))
    }

    @Test func playAndPauseAlwaysUseNowPlaying() {
        for player: RemotePlayer in [.browser(.netflix), .browser(.youtube), .appleTV, .quickTime, .iina, .vlc, .infuse, .music, .appleMusic, .other] {
            #expect(RemoteKeymap(player: player).output(.playPause) == .media(.playPause))
        }
    }

    @Test func webPlayers() {
        let youtube = RemoteKeymap(player: .browser(.youtube))
        #expect(youtube.output(.back) == .keystroke(key("j")))
        #expect(youtube.output(.forward) == .keystroke(key("l")))
        #expect(youtube.output(.fullScreen) == .keystroke(key("f")))
        #expect(youtube.output(.subtitles) == .keystroke(key("c")))
        #expect(youtube.output(.next) == .keystroke(key("n", .shift)))
        #expect(youtube.output(.previous) == .keystroke(key("p", .shift)))
        #expect(youtube.searchPrefix == [key("/")])

        let netflix = RemoteKeymap(player: .browser(.netflix))
        #expect(netflix.output(.back) == .keystroke(special(.left)))
        #expect(netflix.output(.forward) == .keystroke(special(.right)))
        #expect(netflix.output(.fullScreen) == .keystroke(key("f")))
        #expect(netflix.output(.skipIntro) == .keystroke(key("s")))
        #expect(!netflix.has(.subtitles))
        #expect(!netflix.has(.next))
        #expect(netflix.searchPrefix.isEmpty)

        for site: RemoteSite in [.primeVideo, .disneyPlus] {
            let map = RemoteKeymap(player: .browser(site))
            #expect(map.output(.forward) == .keystroke(special(.right)))
            #expect(map.output(.fullScreen) == .keystroke(key("f")))
            #expect(!map.has(.skipIntro))
        }
        #expect(RemoteKeymap(player: .browser(.primeVideo)).output(.subtitles) == .keystroke(key("c")))
        #expect(!RemoteKeymap(player: .browser(.disneyPlus)).has(.subtitles))
        // An unknown site gets the keys most players share.
        let web = RemoteKeymap(player: .browser(.other))
        #expect(web.output(.back) == .keystroke(special(.left)))
        #expect(web.output(.subtitles) == .keystroke(key("c")))
        #expect(web.name == "Web Video")
    }

    @Test func macPlayersSeekThroughNowPlayingWithAKeyAsFallback() {
        #expect(RemoteKeymap(player: .appleTV).output(.back) == .seek(-10, fallback: special(.left)))
        #expect(RemoteKeymap(player: .iina).output(.forward) == .seek(10, fallback: special(.right)))
        #expect(RemoteKeymap(player: .vlc).output(.forward) == .seek(10, fallback: special(.right, [.command, .control])))
        for player: RemotePlayer in [.appleTV, .iina, .infuse, .other] {
            #expect(RemoteKeymap(player: player).output(.fullScreen) == .keystroke(fullScreenShortcut))
            #expect(!RemoteKeymap(player: player).has(.subtitles))
        }
        #expect(RemoteKeymap(player: .vlc).output(.fullScreen) == .keystroke(key("f", .command)))
        #expect(!RemoteKeymap(player: .quickTime).has(.subtitles))
    }

    @Test func quickTimeJumpsOnlyThroughNowPlaying() {
        // Its arrows step frames, so there is no key to fall back on and the buttons hide
        // when the player cannot seek.
        let qt = RemoteKeymap(player: .quickTime)
        #expect(qt.output(.forward) == .seek(10, fallback: nil))
        #expect(qt.has(.forward, canSeek: true))
        #expect(!qt.has(.forward, canSeek: false))
        #expect(qt.output(.fullScreen) == .keystroke(key("f", .command)))
        #expect(RemoteKeymap(player: .appleTV).has(.forward, canSeek: false))
    }

    @Test func keysAreLeftOutWhenThePlayerIsBehindAnotherApp() {
        // Finder in front, IINA playing: a full screen key would go to Finder.
        let behind = RemoteKeymap(frontmost: "com.apple.finder", playing: "com.colliderli.iina")
        #expect(behind.player == .iina)
        #expect(!behind.keysReachPlayer)
        #expect(!behind.has(.fullScreen))
        #expect(behind.output(.forward) == .seek(10, fallback: nil))
        // A video in Chrome while Safari is in front: no web keys at all.
        let web = RemoteKeymap(frontmost: "com.apple.Safari", playing: "com.google.Chrome", nowPlaying: ["YouTube"])
        #expect(web.player == .browser(.youtube))
        #expect(web.output(.back) == .seek(-10, fallback: nil))
        #expect(!web.has(.subtitles) && !web.has(.next) && web.searchPrefix.isEmpty)
        #expect(RemoteKeymap(frontmost: "com.apple.Safari", playing: "com.apple.Safari", nowPlaying: ["YouTube"]).keysReachPlayer)
    }

    @Test func musicSkipsSongs() {
        let music = RemoteKeymap(player: .music)
        #expect(music.skipsTracks)
        #expect(music.output(.back) == .media(.previousTrack))
        #expect(music.output(.forward) == .media(.nextTrack))
        #expect(music.output(.next) == .media(.nextTrack))
        #expect(!music.has(.fullScreen))
        #expect(!music.has(.subtitles))
        #expect(music.name == nil)

        let appleMusic = RemoteKeymap(player: .appleMusic)
        #expect(appleMusic.skipsTracks)
        #expect(appleMusic.output(.forward) == .media(.nextTrack))
        #expect(appleMusic.output(.fullScreen) == .keystroke(key("f", [.command, .shift])))
        // Behind another app its full screen key would go elsewhere.
        #expect(!RemoteKeymap(frontmost: "com.apple.finder", playing: "com.apple.Music").has(.fullScreen))
    }

    @Test func resolvingSeeksClampsAndFallsBack() {
        let seek = RemoteOutput.seek(-10, fallback: special(.left))
        #expect(RemoteKeymap.message(for: seek, position: 64, canSeek: true) == [.mediaControl(.seek(54))])
        #expect(RemoteKeymap.message(for: seek, position: 4, canSeek: true) == [.mediaControl(.seek(0))])
        #expect(RemoteKeymap.message(for: .seek(10, fallback: nil), position: 95, canSeek: true, duration: 100)
                == [.mediaControl(.seek(100))])
        #expect(RemoteKeymap.message(for: seek, position: nil, canSeek: true) == [.keysKeystroke(special(.left))])
        #expect(RemoteKeymap.message(for: seek, position: 30, canSeek: false) == [.keysKeystroke(special(.left))])
        #expect(RemoteKeymap.message(for: .seek(10, fallback: nil), position: nil, canSeek: false).isEmpty)
        #expect(RemoteKeymap.message(for: .media(.mute), position: nil, canSeek: false) == [.mediaCommand(.mute)])
        #expect(RemoteKeymap.message(for: .keystrokes([key("/"), key("a")]), position: nil, canSeek: false)
                == [.keysKeystroke(key("/")), .keysKeystroke(key("a"))])
    }

    @Test func volumeMovesInTheMacsSteps() {
        #expect(RemoteKeymap.volume(from: 0.5, steps: 1) == 0.5625)
        #expect(RemoteKeymap.volume(from: 0.5, steps: -2) == 0.375)
        // Snapped first, so an odd value lands on a step.
        #expect(RemoteKeymap.volume(from: 0.51, steps: 1) == 0.5625)
        #expect(RemoteKeymap.volume(from: 0.97, steps: 3) == 1)
        #expect(RemoteKeymap.volume(from: 0.02, steps: -1) == 0)
    }

    @Test func remoteMessagesRoundTripAndTheModeIsHiddenAtFirst() throws {
        let id = UUID()
        for m: ModeMessage in [.modeSelected(.remote), .remoteSystem(id: id, action: .sleepDisplay),
                               .remoteSystem(id: id, action: .doNotDisturb)] {
            let data = try ControlMessage.mode(m).jsonData()
            #expect(try ControlMessage.from(jsonData: data) == .mode(m))
        }
        #expect(ModeListLayout().visible(known: ModeListLayout.defaultOrder) == ["trackpad", "keys", "media", "dock", "actions"])
        // A list saved before Remote existed gets it, hidden, so nothing changes in the pill.
        let old = #"{"order":["keys","trackpad","media"],"hidden":["media"],"splitActions":false}"#
        let decoded = try JSONDecoder().decode(ModeListLayout.self, from: Data(old.utf8))
        // (The StandBy screens, added later, join the same way.)
        #expect(decoded.order == ["keys", "trackpad", "media", "remote", "clock", "nowPlaying", "calendar"])
        #expect(decoded.hidden == ["media", "remote", "clock", "nowPlaying", "calendar"])
        // Once shown, it stays shown after saving and loading.
        var shown = decoded
        shown.hidden.remove("remote")
        let again = try JSONDecoder().decode(ModeListLayout.self, from: JSONEncoder().encode(shown))
        #expect(again.visible(known: ModeListLayout.defaultOrder).contains("remote"))
    }
}

@Suite struct RemoteSwipeTests {
    @Test func aStillTouchIsATap() {
        var s = RemoteSwipe()
        #expect(s.moved(dx: 3, dy: -2) == nil)
        #expect(s.ended(dx: 4, dy: -2) == .tap)
    }

    @Test func sidewaysStepsEveryStepX() {
        var s = RemoteSwipe()
        #expect(s.moved(dx: 20, dy: 2) == nil)
        #expect(s.moved(dx: 75, dy: 5) == .step(.horizontal, 1))
        #expect(s.moved(dx: 100, dy: 30) == nil)
        #expect(s.moved(dx: 150, dy: 60) == .step(.horizontal, 1))
        // Moving back steps back, like turning a dial.
        #expect(s.moved(dx: 60, dy: 0) == .step(.horizontal, -2))
        #expect(s.ended(dx: 60, dy: 0) == nil)
    }

    @Test func upIsLouderAndStepsAreSmaller() {
        var s = RemoteSwipe()
        #expect(s.moved(dx: 2, dy: -31) == .step(.vertical, 1))
        #expect(s.moved(dx: 2, dy: -95) == .step(.vertical, 2))
        #expect(s.ended(dx: 2, dy: -95) == nil)
        var down = RemoteSwipe()
        #expect(down.ended(dx: 0, dy: 40) == .step(.vertical, -1))
    }

    @Test func aShortFlickCountsAsOneStep() {
        var s = RemoteSwipe()
        #expect(s.moved(dx: -30, dy: 3) == nil)
        #expect(s.ended(dx: -40, dy: 3) == .step(.horizontal, -1))
        // The tracker is fresh after each lift.
        #expect(s.axis == nil)
        #expect(s.ended(dx: 1, dy: 1) == .tap)
    }

    @Test func aWobbleThatIsNeitherIsIgnored() {
        var s = RemoteSwipe()
        #expect(s.moved(dx: 19, dy: 4) == nil)
        #expect(s.ended(dx: 22, dy: 4) == nil)
    }
}
