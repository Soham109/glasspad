import Foundation
import Testing
@testable import GlasspadKit

@Suite struct PhoneStatusTests {
    @Test func roundTripsWithItsWireShape() throws {
        let full = ControlMessage.phoneStatus(PhoneStatus(batteryPercent: 42, charging: false))
        let json = String(decoding: try full.jsonData(), as: UTF8.self)
        #expect(json.contains(#""t":"phoneStatus""#))
        #expect(json.contains(#""batteryPercent":42"#))
        #expect(json.contains(#""charging":false"#))
        #expect(try ControlMessage.from(jsonData: full.jsonData()) == full)

        let bare = ControlMessage.phoneStatus(PhoneStatus())
        #expect(String(decoding: try bare.jsonData(), as: UTF8.self).contains(#""status":{}"#))
        #expect(try ControlMessage.from(jsonData: bare.jsonData()) == bare)
    }

    /// A newer phone may add fields; a broken or out of range level reads as unknown.
    @Test func toleratesNewerAndBrokenFields() throws {
        let newer = #"{"t":"phoneStatus","status":{"batteryPercent":80,"charging":true,"lowPower":true}}"#
        #expect(try ControlMessage.from(jsonData: Data(newer.utf8)) == .phoneStatus(PhoneStatus(batteryPercent: 80, charging: true)))
        let broken = #"{"t":"phoneStatus","status":{"batteryPercent":"lots","charging":1}}"#
        #expect(try ControlMessage.from(jsonData: Data(broken.utf8)) == .phoneStatus(PhoneStatus()))
        let outOfRange = #"{"t":"phoneStatus","status":{"batteryPercent":140}}"#
        #expect(try ControlMessage.from(jsonData: Data(outOfRange.utf8)) == .phoneStatus(PhoneStatus()))
    }

    /// What a Mac from before phoneStatus sees: a type it does not know, which it ignores while
    /// keeping the session (see GlasspadServer's receive path).
    @Test func olderMacsReadItAsUnknown() throws {
        let wire = try ControlMessage.phoneStatus(PhoneStatus(batteryPercent: 42, charging: false)).jsonData()
        let renamed = String(decoding: wire, as: UTF8.self).replacingOccurrences(of: "phoneStatus", with: "zzUnknown")
        #expect(try ControlMessage.from(jsonData: Data(renamed.utf8)) == .unknown(type: "zzUnknown"))
    }

    @Test func levelRoundsToWholePercent() {
        #expect(PhoneStatus(batteryLevel: 0.424, charging: false).batteryPercent == 42)
        #expect(PhoneStatus(batteryLevel: 0.425, charging: false).batteryPercent == 43)
        #expect(PhoneStatus(batteryLevel: 1, charging: true).batteryPercent == 100)
        #expect(PhoneStatus(batteryLevel: 0, charging: false).batteryPercent == 0)
        #expect(PhoneStatus(batteryLevel: -1, charging: false).batteryPercent == nil)
        #expect(PhoneStatus(batteryLevel: -1, charging: false).battery == nil)
    }

    @Test func batterySymbolFollowsTheLevel() {
        func symbol(_ p: Int, _ charging: Bool = false) -> String { PhoneBattery(percent: p, charging: charging).symbol }
        #expect(symbol(5) == "battery.0percent")
        #expect(symbol(15) == "battery.25percent")
        #expect(symbol(42) == "battery.50percent")
        #expect(symbol(70) == "battery.75percent")
        #expect(symbol(95) == "battery.100percent")
        #expect(symbol(15, true) == "battery.100percent.bolt")
        #expect(PhoneBattery(percent: 42, charging: false).text == "42%")
    }

    @Test func lowBatteryTellsOnceAtTwentyAndOnceAtTen() {
        var watch = LowBatteryWatch()
        var told: [Int] = []
        for p in stride(from: 30, through: 3, by: -1) {
            if let shown = watch.update(percent: p, charging: false) { told.append(shown) }
        }
        #expect(told == [20, 10])
        // Jitter back up a point and down again does not repeat it.
        #expect(watch.update(percent: 11, charging: false) == nil)
        #expect(watch.update(percent: 10, charging: false) == nil)
    }

    @Test func lowBatteryStartsOverAfterCharging() {
        var watch = LowBatteryWatch()
        #expect(watch.update(percent: 20, charging: false) == 20)
        #expect(watch.update(percent: 19, charging: true) == nil)
        #expect(watch.update(percent: 19, charging: false) == 19)
        // Charged while Glasspad was closed: back above 25% starts over too.
        #expect(watch.update(percent: 60, charging: false) == nil)
        #expect(watch.update(percent: 20, charging: false) == 20)
    }

    @Test func lowBatteryFirstSeenBelowAThresholdTellsTheRealLevel() {
        var watch = LowBatteryWatch()
        #expect(watch.update(percent: 15, charging: false) == 15)
        #expect(watch.update(percent: 12, charging: false) == nil)
        #expect(watch.update(percent: 10, charging: false) == 10)

        var low = LowBatteryWatch()
        #expect(low.update(percent: 7, charging: false) == 7)
        #expect(low.update(percent: 6, charging: false) == nil)
        #expect(low.update(percent: nil, charging: false) == nil)
    }

    @Test func noticeNeverWhileCharging() {
        var watch = LowBatteryWatch()
        for p in stride(from: 25, through: 1, by: -1) { #expect(watch.update(percent: p, charging: true) == nil) }
    }
}
