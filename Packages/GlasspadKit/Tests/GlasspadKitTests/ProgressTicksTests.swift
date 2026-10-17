import Foundation
import Testing
@testable import GlasspadKit

@Suite struct ProgressTicksTests {
    @Test func aShortSongOnAWideBarTicksAtTheFastest() {
        // 3 minutes on 1050 pixels: a pixel every 0.17 s, faster than 0.25 s allows.
        #expect(ProgressTicks.interval(duration: 180, barPixels: 1050, fastest: 0.25) == 0.25)
    }

    @Test func aLongerSongTicksOnlyWhenTheBarMovesAPixel() {
        // 5 minutes on 1050 pixels: a pixel every 0.29 s, so three ticks a second.
        #expect(abs(ProgressTicks.interval(duration: 300, barPixels: 1050, fastest: 0.25) - 1.0 / 3) < 1e-12)
        // 6 minutes: a pixel every 0.34 s, so two.
        #expect(ProgressTicks.interval(duration: 360, barPixels: 1050, fastest: 0.25) == 0.5)
        // 10 minutes: a pixel every 0.57 s, so once a second for the clock.
        #expect(ProgressTicks.interval(duration: 600, barPixels: 1050, fastest: 0.25) == 1)
    }

    @Test func anHourLongPodcastStillTicksEverySecondForTheClock() {
        #expect(ProgressTicks.interval(duration: 3600, barPixels: 1050, fastest: 0.25) == 1)
    }

    @Test func lowPowerKeepsOncePerSecond() {
        #expect(ProgressTicks.interval(duration: 60, barPixels: 1050, fastest: 1) == 1)
    }

    @Test func everyIntervalLandsOnWholeSeconds() {
        for duration in stride(from: 30.0, through: 4000, by: 37) {
            let i = ProgressTicks.interval(duration: duration, barPixels: 1000, fastest: 0.25)
            let steps = 1 / i
            #expect(abs(steps - steps.rounded()) < 1e-9)
            #expect(i >= 0.25 && i <= 1)
        }
    }

    @Test func beforeTheBarHasAWidthItTicksAtTheFastest() {
        #expect(ProgressTicks.interval(duration: 200, barPixels: 0, fastest: 0.25) == 0.25)
        #expect(ProgressTicks.interval(duration: 0, barPixels: 1000, fastest: 0.25) == 0.25)
    }

    @Test func ticksStartWhenTheSongWasLastOnATick() {
        let now = Date(timeIntervalSince1970: 1000)
        // 12.3 s in: the last tick was at 12.01 s, 0.29 s ago.
        #expect(ProgressTicks.start(now: now, position: 12.3, interval: 1).timeIntervalSince1970.isApprox(999.71))
        #expect(ProgressTicks.start(now: now, position: 12.3, interval: 0.25).timeIntervalSince1970.isApprox(999.96))
        // Exactly on a second: the last tick was just after the one before.
        #expect(ProgressTicks.start(now: now, position: 5, interval: 0.5).timeIntervalSince1970.isApprox(999.51))
        #expect(ProgressTicks.start(now: now, position: 5.01, interval: 1) == now)
        // Each tick after it reads a clock just past a whole second.
        let first = ProgressTicks.start(now: now, position: 7.6, interval: 1)
        let positionThen = 7.6 - now.timeIntervalSince(first)
        #expect(positionThen.isApprox(7.01))
    }
}

private extension Double {
    func isApprox(_ other: Double) -> Bool { abs(self - other) < 1e-6 }
}
