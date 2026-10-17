import Foundation
import Testing
@testable import GlasspadKit

@Suite struct PresentTimerTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func countsWhileRunningAndKeepsTimeWhenPaused() {
        var timer = PresentTimer()
        #expect(!timer.hasTime && timer.elapsed(at: t0) == 0)
        timer.toggle(at: t0)
        #expect(timer.isRunning && timer.hasTime)
        #expect(timer.elapsed(at: t0 + 90) == 90)
        timer.toggle(at: t0 + 90)
        #expect(!timer.isRunning)
        #expect(timer.elapsed(at: t0 + 500) == 90)
        timer.toggle(at: t0 + 500)
        #expect(timer.elapsed(at: t0 + 510) == 100)
    }

    @Test func resetWhileRunningRestartsFromNow() {
        var timer = PresentTimer()
        timer.toggle(at: t0)
        timer.reset(at: t0 + 60)
        #expect(timer.isRunning)
        #expect(timer.elapsed(at: t0 + 65) == 5)
        timer.toggle(at: t0 + 65)
        timer.reset(at: t0 + 70)
        #expect(!timer.hasTime && timer.elapsed(at: t0 + 100) == 0)
    }

    @Test func remainingCountsDownAndGoesBelowZero() {
        var timer = PresentTimer()
        #expect(timer.remaining(length: 600, at: t0) == 600)
        timer.toggle(at: t0)
        #expect(timer.remaining(length: 600, at: t0 + 150) == 450)
        #expect(timer.remaining(length: 600, at: t0 + 612) == -12)
    }

    @Test func restoresWhatWasSaved() {
        var timer = PresentTimer()
        timer.toggle(at: t0)
        let running = PresentTimer(restoring: timer.saved(at: t0), at: t0 + 300)
        #expect(running.isRunning && running.elapsed(at: t0 + 300) == 300)
        #expect(running == timer)

        timer.toggle(at: t0 + 40)
        let paused = PresentTimer(restoring: timer.saved(at: t0 + 40), at: t0 + 3_600)
        #expect(!paused.isRunning && paused.elapsed(at: t0 + 9_000) == 40)
    }

    @Test func savedValuesSurviveEncoding() throws {
        var timer = PresentTimer()
        timer.toggle(at: t0)
        let data = try JSONEncoder().encode(timer.saved(at: t0))
        let back = try JSONDecoder().decode(PresentTimer.Saved.self, from: data)
        #expect(PresentTimer(restoring: back, at: t0 + 1) == timer)
    }

    @Test func nothingToSaveAtZero() {
        #expect(PresentTimer().saved(at: t0) == nil)
        #expect(PresentTimer(restoring: nil, at: t0) == PresentTimer())
    }

    @Test func discardsATalkOlderThanTwelveHours() {
        var timer = PresentTimer()
        timer.toggle(at: t0)
        let saved = timer.saved(at: t0)
        #expect(PresentTimer(restoring: saved, at: t0 + PresentTimer.maxAge - 1).isRunning)
        #expect(PresentTimer(restoring: saved, at: t0 + PresentTimer.maxAge) == PresentTimer())
        // Saved "in the future" (the clock was set back a long way): not trusted.
        #expect(PresentTimer(restoring: saved, at: t0 - 3_600) == PresentTimer())
    }
}

@Suite struct TalkClockTests {
    @Test func countsDownRoundingUp() {
        #expect(TalkClock.text(remaining: 1_200) == "20:00")
        #expect(TalkClock.text(remaining: 1_199.2) == "20:00")
        #expect(TalkClock.text(remaining: 45) == "0:45")
        #expect(TalkClock.text(remaining: 0.4) == "0:01")
        #expect(TalkClock.text(remaining: 0) == "0:00")
    }

    @Test func overShowsAPlus() {
        #expect(TalkClock.text(remaining: -0.5) == "0:00")
        #expect(TalkClock.text(remaining: -1) == "+0:01")
        #expect(TalkClock.text(remaining: -12.7) == "+0:12")
        #expect(TalkClock.text(remaining: -754) == "+12:34")
        #expect(TalkClock.text(remaining: -3_725) == "+1:02:05")
    }

    @Test func stages() {
        #expect(TalkClock.stage(remaining: 600) == .normal)
        #expect(TalkClock.stage(remaining: 60.5) == .normal)
        #expect(TalkClock.stage(remaining: 60) == .warning)
        #expect(TalkClock.stage(remaining: 1) == .warning)
        #expect(TalkClock.stage(remaining: 0) == .over)
        #expect(TalkClock.stage(remaining: -30) == .over)
    }

    @Test func spokenForVoiceOver() {
        #expect(TalkClock.spoken(remaining: 750) == "12 minutes 30 seconds left")
        #expect(TalkClock.spoken(remaining: 60) == "1 minute left")
        #expect(TalkClock.spoken(remaining: 1) == "1 second left")
        #expect(TalkClock.spoken(remaining: 0) == "Time is up")
        #expect(TalkClock.spoken(remaining: -12) == "Over by 12 seconds")
        #expect(TalkClock.spoken(remaining: -3_661) == "Over by 1 hour 1 minute 1 second")
    }

    @Test func lengthsOnOffer() {
        #expect(TalkClock.lengths == [10, 15, 20, 30, 45, 60])
    }

    @Test func cuesAtFiveAndOneMinuteLeft() {
        #expect(TalkClock.nextCue(remaining: 1_200) == 300)
        #expect(TalkClock.nextCue(remaining: 300.5) == 300)
        #expect(TalkClock.nextCue(remaining: 300) == 60)
        #expect(TalkClock.nextCue(remaining: 299.9) == 60)
        #expect(TalkClock.nextCue(remaining: 60) == nil)
        #expect(TalkClock.nextCue(remaining: -5) == nil)
    }

    @Test func aLateCueIsDropped() {
        #expect(TalkClock.cueIsDue(300, remaining: 300))
        #expect(TalkClock.cueIsDue(300, remaining: 299.1))
        // Back from the background long after the mark: no tap.
        #expect(!TalkClock.cueIsDue(300, remaining: 200))
        // Not yet.
        #expect(!TalkClock.cueIsDue(60, remaining: 120))
    }
}
