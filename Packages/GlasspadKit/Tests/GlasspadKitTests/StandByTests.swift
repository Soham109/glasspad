import Foundation
import Testing
@testable import GlasspadKit

@Suite struct StandByTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: hour, minute: minute, second: second))!
    }

    // MARK: Faces

    @Test func facesCycleThroughEveryOneAndWrap() {
        #expect(ClockFace.digital.next == .analog)
        #expect(ClockFace.analog.next == .minimal)
        #expect(ClockFace.minimal.next == .digital)
        var face = ClockFace.digital
        var seen: Set<ClockFace> = []
        for _ in ClockFace.allCases { seen.insert(face); face = face.next }
        #expect(seen == Set(ClockFace.allCases))
        #expect(face == .digital)
    }

    // MARK: Time text

    @Test func twelveHourDropsTheLeadingZeroAndShowsTwelveAtNoonAndMidnight() {
        #expect(ClockText.parts(date(9, 41), uses24Hour: false, calendar: calendar) == ("9", "41"))
        #expect(ClockText.parts(date(21, 5), uses24Hour: false, calendar: calendar) == ("9", "05"))
        #expect(ClockText.parts(date(0, 0), uses24Hour: false, calendar: calendar) == ("12", "00"))
        #expect(ClockText.parts(date(12, 30), uses24Hour: false, calendar: calendar) == ("12", "30"))
    }

    @Test func twentyFourHourKeepsTheLeadingZero() {
        #expect(ClockText.parts(date(9, 41), uses24Hour: true, calendar: calendar) == ("09", "41"))
        #expect(ClockText.parts(date(21, 5), uses24Hour: true, calendar: calendar) == ("21", "05"))
        #expect(ClockText.parts(date(0, 0), uses24Hour: true, calendar: calendar) == ("00", "00"))
    }

    @Test func clockFollowsTheLocale() {
        #expect(ClockText.uses24Hour(locale: Locale(identifier: "en_US")) == false)
        #expect(ClockText.uses24Hour(locale: Locale(identifier: "en_GB")) == true)
        #expect(ClockText.uses24Hour(locale: Locale(identifier: "de_DE")) == true)
    }

    @Test func handsPointWhereAClocksWould() {
        let three = ClockText.handAngles(date(15, 0), calendar: calendar)
        #expect(three.hour == 90 && three.minute == 0 && three.second == 0)
        let half = ClockText.handAngles(date(6, 30, 15), calendar: calendar)
        #expect(abs(half.hour - 195.125) < 0.001)
        #expect(abs(half.minute - 181.5) < 0.001)
        #expect(half.second == 90)
    }

    // MARK: Burn in

    @Test func shiftStaysSmallMovesEveryMinuteAndOnlyBySmallSteps() {
        let amplitude = 3.0
        var last = BurnInShift.offset(at: date(10, 0), amplitude: amplitude)
        var spots = Set<String>()
        for minute in 1...60 {
            let now = BurnInShift.offset(at: date(10, 0).addingTimeInterval(Double(minute) * 60), amplitude: amplitude)
            #expect(abs(now.x) <= amplitude && abs(now.y) <= amplitude)
            #expect(now != last, "moves every minute")
            #expect(abs(now.x - last.x) <= amplitude && abs(now.y - last.y) <= amplitude, "one small step")
            spots.insert("\(now.x),\(now.y)")
            last = now
        }
        #expect(spots.count == 9, "uses the whole area, not one spot")
    }

    @Test func shiftHoldsStillWithinAMinute() {
        let a = BurnInShift.offset(at: date(10, 7, 1))
        let b = BurnInShift.offset(at: date(10, 7, 59))
        #expect(a == b)
    }

    @Test func shiftWorksBeforeTheReferenceDate() {
        let old = Date(timeIntervalSinceReferenceDate: -90)
        let o = BurnInShift.offset(at: old)
        #expect(abs(o.x) <= 3 && abs(o.y) <= 3)
    }

    // MARK: Keeping the screen on

    @Test func staysOnOnlyWhileVisibleAndPluggedInOrAsked() {
        #expect(StandByPower(visible: true, charging: true, keepOnUnplugged: false, lowPower: false, heat: .nominal).keepsScreenOn)
        #expect(!StandByPower(visible: true, charging: false, keepOnUnplugged: false, lowPower: false, heat: .nominal).keepsScreenOn)
        #expect(StandByPower(visible: true, charging: false, keepOnUnplugged: true, lowPower: false, heat: .nominal).keepsScreenOn)
        #expect(!StandByPower(visible: false, charging: true, keepOnUnplugged: true, lowPower: false, heat: .nominal).keepsScreenOn)
    }

    @Test func lowPowerModeOnBatteryLetsTheScreenLock() {
        #expect(!StandByPower(visible: true, charging: false, keepOnUnplugged: true, lowPower: true, heat: .nominal).keepsScreenOn)
        // On power, Low Power Mode still allows it (StandBy does the same).
        #expect(StandByPower(visible: true, charging: true, keepOnUnplugged: false, lowPower: true, heat: .nominal).keepsScreenOn)
    }

    @Test func aHotPhoneDimsAndStopsTicking() {
        let cool = StandByPower(visible: true, charging: true, keepOnUnplugged: false, lowPower: false, heat: .fair)
        #expect(cool.brightness == 1 && cool.ticksSeconds)
        let warm = StandByPower(visible: true, charging: true, keepOnUnplugged: false, lowPower: false, heat: .serious)
        // Warm and charging: the screen may lock, to spare the battery.
        #expect(warm.brightness < 1 && !warm.ticksSeconds && !warm.keepsScreenOn)
        #expect(!StandByPower(visible: true, charging: false, keepOnUnplugged: true, lowPower: false, heat: .serious).keepsScreenOn)
        #expect(StandByPower(visible: true, charging: true, keepOnUnplugged: false, lowPower: false, heat: .fair).keepsScreenOn)
        let hot = StandByPower(visible: true, charging: true, keepOnUnplugged: false, lowPower: false, heat: .critical)
        #expect(hot.brightness < warm.brightness && !hot.keepsScreenOn)
        let saving = StandByPower(visible: true, charging: true, keepOnUnplugged: false, lowPower: true, heat: .nominal)
        #expect(saving.brightness < 1 && !saving.ticksSeconds)
    }

    // MARK: Night

    @Test func nightModeFollowsTheChoiceAndTheHour() {
        #expect(!NightMode.off.isActive(at: date(23, 0), calendar: calendar))
        #expect(NightMode.always.isActive(at: date(12, 0), calendar: calendar))
        #expect(NightMode.atNight.isActive(at: date(22, 0), calendar: calendar))
        #expect(NightMode.atNight.isActive(at: date(3, 30), calendar: calendar))
        #expect(NightMode.atNight.isActive(at: date(6, 59), calendar: calendar))
        #expect(!NightMode.atNight.isActive(at: date(7, 0), calendar: calendar))
        #expect(!NightMode.atNight.isActive(at: date(21, 59), calendar: calendar))
    }

    // MARK: Up next

    @Test func upcomingPutsTimedEventsInOrderThenAllDayAndDropsFinishedOnes() {
        let now = date(10, 0)
        let events = [
            UpNextEvent(id: "lunch", title: "Lunch", start: date(12, 0), end: date(13, 0)),
            UpNextEvent(id: "done", title: "Standup", start: date(9, 0), end: date(9, 15)),
            UpNextEvent(id: "holiday", title: "Holiday", start: date(0, 0), end: date(23, 59), allDay: true),
            UpNextEvent(id: "review", title: "Review", start: date(9, 45), end: date(10, 30)),
        ]
        #expect(UpNextEvent.upcoming(events, at: now).map(\.id) == ["review", "lunch", "holiday"])
        #expect(UpNextEvent.upcoming(events, at: now, limit: 1).map(\.id) == ["review"])
    }

    @Test func timingSaysNowSoonOrLater() {
        let now = date(10, 0)
        #expect(UpNextEvent(id: "a", title: "", start: date(9, 45), end: date(10, 30)).timing(at: now) == .now(minutesLeft: 30))
        #expect(UpNextEvent(id: "b", title: "", start: date(10, 25), end: date(11, 0)).timing(at: now) == .soon(minutes: 25))
        #expect(UpNextEvent(id: "c", title: "", start: date(10, 0, 20), end: date(11, 0)).timing(at: now) == .soon(minutes: 1))
        #expect(UpNextEvent(id: "d", title: "", start: date(11, 30), end: date(12, 0)).timing(at: now) == .later)
    }
}
