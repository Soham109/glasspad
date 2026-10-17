import Foundation
import Testing
@testable import GlasspadKit

@Suite struct LiveControlsTests {
    private func film() -> MediaState {
        var s = MediaState(title: "The Quiet Coast", artist: "Netflix")
        s.isPlaying = true
        s.canSeek = true
        s.sourceBundleID = "com.apple.Safari"
        s.sourceName = "Safari"
        return s
    }

    @Test func aFilmInABrowserJumpsTenSeconds() {
        let r = LiveControls.Remote(state: film(), isPlaying: true, frontmost: "com.apple.Safari")
        #expect(r.title == "The Quiet Coast")
        #expect(r.detail == "Netflix in Safari")
        #expect(r.isPlaying)
        #expect(!r.skipsTracks)
        #expect(r.hasBack && r.hasForward)
        #expect(r.backSymbol == "gobackward.10")
        #expect(r.forwardLabel == "Forward 10 seconds")
    }

    @Test func musicChangesTheSong() {
        var s = MediaState(title: "Everything In Its Right Place", artist: "Radiohead")
        s.isPlaying = false
        s.sourceBundleID = "com.spotify.client"
        s.sourceName = "Spotify"
        let r = LiveControls.Remote(state: s, isPlaying: false, frontmost: "com.apple.finder")
        #expect(r.skipsTracks)
        #expect(r.detail == "Radiohead")
        #expect(!r.isPlaying)
        #expect(r.backSymbol == "backward.fill")
        #expect(r.backLabel == "Previous")
    }

    @Test func nothingPlayingSaysSo() {
        let r = LiveControls.Remote(state: nil, isPlaying: true, frontmost: nil)
        #expect(r.title == "Nothing Playing")
        #expect(r.detail == nil)
        #expect(!r.isPlaying)
    }

    @Test func aJumpWithNoKeyNeedsAPlayerThatCanSeek() {
        // QuickTime's arrows step frames: without seeking there is no 10 second jump.
        var s = MediaState(title: "Clip")
        s.sourceBundleID = "com.apple.QuickTimePlayerX"
        s.sourceName = "QuickTime Player"
        s.canSeek = false
        let r = LiveControls.Remote(state: s, isPlaying: false, frontmost: "com.apple.QuickTimePlayerX")
        #expect(!r.hasBack && !r.hasForward)
        s.canSeek = true
        let seeking = LiveControls.Remote(state: s, isPlaying: false, frontmost: "com.apple.QuickTimePlayerX")
        #expect(seeking.hasBack && seeking.hasForward)
    }

    @Test func aRunningTimerCountsFromADate() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        let p = LiveControls.Present(isRunning: true, elapsed: 125, length: nil, now: now)
        #expect(p.isRunning)
        #expect(p.countingFrom == Date(timeIntervalSinceReferenceDate: 875))
        #expect(p.endsAt == nil)
        // Later reads of the same timer give the same state: nothing to send per second.
        let later = LiveControls.Present(isRunning: true, elapsed: 135, length: nil, now: now.addingTimeInterval(10))
        #expect(later == p)
    }

    @Test func aTalkLengthEndsAtADate() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        let p = LiveControls.Present(isRunning: true, elapsed: 60, length: 600, now: now)
        #expect(p.endsAt == Date(timeIntervalSinceReferenceDate: 1540))
        #expect(LiveControls.Present(isRunning: true, elapsed: 0, length: 0, now: now).length == nil)
    }

    @Test func aPausedTimerShowsItsTime() {
        let now = Date()
        #expect(LiveControls.Present(isRunning: false, elapsed: 65, length: nil, now: now).pausedText == "1:05")
        #expect(LiveControls.Present(isRunning: false, elapsed: 3723, length: nil, now: now).pausedText == "1:02:03")
        #expect(LiveControls.Present(isRunning: false, elapsed: 60, length: 600, now: now).pausedText == "9:00")
        #expect(LiveControls.Present(isRunning: false, elapsed: 612, length: 600, now: now).pausedText == "+0:12")
        #expect(LiveControls.Present(isRunning: false, elapsed: 0, length: nil, now: now).pausedText == "0:00")
    }

    @Test func stateRoundTripsThroughCoding() throws {
        let remote = LiveControls.remote(LiveControls.Remote(state: film(), isPlaying: true, frontmost: nil),
                                         macName: "Studio", problem: "Could not reach Studio")
        let present = LiveControls.present(.init(countingFrom: Date(timeIntervalSinceReferenceDate: 5), elapsed: 0, length: 900),
                                           macName: "Studio")
        for value in [remote, present] {
            let data = try JSONEncoder().encode(value)
            #expect(try JSONDecoder().decode(LiveControls.self, from: data) == value)
        }
    }

    @Test func eachPressKeepsTheConnectionLonger() {
        var linger = LiveLinger()
        #expect(!linger.isHolding(at: 0))
        let first = linger.pressed(at: 10)
        #expect(first)
        #expect(linger.isHolding(at: 29))
        let again = linger.pressed(at: 15)
        #expect(!again)
        #expect(linger.remaining(at: 30) == 5)
        #expect(!linger.isHolding(at: 35))
        #expect(linger.remaining(at: 40) == 0)
        let fresh = linger.pressed(at: 40)
        #expect(fresh)
        linger.stop()
        #expect(!linger.isHolding(at: 41))
    }
}
