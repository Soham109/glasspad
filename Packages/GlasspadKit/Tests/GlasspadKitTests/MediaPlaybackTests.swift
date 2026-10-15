import Foundation
import Testing
@testable import GlasspadKit

@Suite struct MediaPlaybackTests {
    let t0 = Date(timeIntervalSince1970: 1000)

    func state(playing: Bool = true, elapsed: Double? = 10, title: String = "Song", shuffle: Bool? = false,
               repeatMode: MediaRepeatMode? = .off) -> MediaState {
        MediaState(title: title, artist: "A", isPlaying: playing, duration: 100, elapsed: elapsed,
                   playbackRate: playing ? 1 : 0, shuffle: shuffle, repeatMode: repeatMode,
                   outputs: [MediaOutput(id: "speakers", name: "Speakers", kind: "builtIn", isCurrent: true),
                             MediaOutput(id: "pods", name: "AirPods", kind: "bluetooth", isCurrent: false)])
    }

    @Test func positionTicksLocallyBetweenUpdates() {
        var p = MediaPlayback()
        #expect(p.position(at: t0) == nil)
        #expect(!p.hasTrack)
        p.receive(state(), at: t0)
        #expect(p.hasTrack)
        #expect(p.position(at: t0.addingTimeInterval(2.5)) == 12.5)
        #expect(p.position(at: t0.addingTimeInterval(500)) == 100)
        p.receive(state(playing: false, elapsed: 20), at: t0.addingTimeInterval(10))
        #expect(p.position(at: t0.addingTimeInterval(30)) == 20)
    }

    @Test func pauseShowsAtOnceAndFreezesProgress() {
        var p = MediaPlayback()
        p.receive(state(), at: t0)
        let tap = t0.addingTimeInterval(4)
        #expect(p.togglePlay(at: tap) == .playPause)
        #expect(!p.isPlaying(at: tap))
        #expect(p.position(at: tap.addingTimeInterval(1)) == 14)
        // A state sent before the Mac saw the tap does not undo it.
        p.receive(state(playing: true, elapsed: 14.2), at: tap.addingTimeInterval(0.1))
        #expect(!p.isPlaying(at: tap.addingTimeInterval(0.2)))
        #expect(p.position(at: tap.addingTimeInterval(1)) == 14)
        // The Mac agrees: its state takes over.
        p.receive(state(playing: false, elapsed: 14.3), at: tap.addingTimeInterval(0.4))
        #expect(!p.isPlaying(at: tap.addingTimeInterval(1)))
        #expect(p.position(at: tap.addingTimeInterval(3)) == 14.3)
    }

    @Test func unconfirmedTapRevertsToTheMac() {
        var p = MediaPlayback()
        p.receive(state(), at: t0)
        _ = p.togglePlay(at: t0)
        #expect(!p.isPlaying(at: t0.addingTimeInterval(1)))
        // No reply at all: after the confirm window the Mac's last word is shown again.
        #expect(p.isPlaying(at: t0.addingTimeInterval(3)))
        #expect(p.position(at: t0.addingTimeInterval(3)) == 13)
        // A reply after the window that still disagrees: the Mac wins.
        _ = p.togglePlay(at: t0.addingTimeInterval(10))
        p.receive(state(playing: true, elapsed: 30), at: t0.addingTimeInterval(13))
        #expect(p.isPlaying(at: t0.addingTimeInterval(13)))
    }

    @Test func seekJumpsAndWaitsForTheMac() {
        var p = MediaPlayback()
        p.receive(state(), at: t0)
        #expect(p.seek(to: 60, at: t0) == .seek(60))
        #expect(p.position(at: t0.addingTimeInterval(1)) == 61)
        // Old position still in flight: ignored.
        p.receive(state(elapsed: 10.5), at: t0.addingTimeInterval(0.2))
        #expect(p.position(at: t0.addingTimeInterval(1)) == 61)
        p.receive(state(elapsed: 60.4), at: t0.addingTimeInterval(0.5))
        #expect(p.position(at: t0.addingTimeInterval(1.5)) == 61.4)
        #expect(p.seek(to: 500, at: t0) == .seek(100))
        #expect(p.seek(to: -5, at: t0) == .seek(0))
    }

    @Test func skipRestartsTheBarUntilTheNewSongArrives() {
        var p = MediaPlayback()
        p.receive(state(elapsed: 50), at: t0)
        p.skipped(at: t0)
        #expect(p.position(at: t0) == 0)
        p.receive(state(elapsed: 0.3, title: "Next"), at: t0.addingTimeInterval(0.3))
        #expect(p.position(at: t0.addingTimeInterval(1.3)) == 1.3)
    }

    @Test func shuffleRepeatAndOutputAreOptimistic() {
        var p = MediaPlayback()
        p.receive(state(), at: t0)
        #expect(p.toggleShuffle(at: t0) == .setShuffle(true))
        #expect(p.shuffle(at: t0) == true)
        #expect(p.cycleRepeat(at: t0) == .setRepeat(.all))
        #expect(p.repeatMode(at: t0) == .all)
        #expect(p.selectOutput("pods", at: t0) == .selectOutput(id: "pods"))
        #expect(p.outputs(at: t0).first(where: \.isCurrent)?.id == "pods")
        // Not confirmed in time: back to the Mac's values.
        let later = t0.addingTimeInterval(5)
        #expect(p.shuffle(at: later) == false)
        #expect(p.repeatMode(at: later) == .off)
        #expect(p.outputs(at: later).first(where: \.isCurrent)?.id == "speakers")
    }

    @Test func resetForgetsEverything() {
        var p = MediaPlayback()
        p.receive(state(), at: t0)
        _ = p.togglePlay(at: t0)
        p.reset()
        #expect(p == MediaPlayback())
        #expect(p.mac == nil)
    }
}
