import CoreGraphics
import Foundation
import Network
import Testing
@testable import GlasspadKit

@Suite("Feel: macOS acceleration curve")
struct MacCurveTests {
    @Test func noAccelerationIsNinetySixPointsPerInch() {
        // Index 0 is linear (gain 1) below its first tangent, so slow motion is the HID
        // system's plain 96 points per inch.
        let c = MacAcceleration.pointerCurve(trackingSpeed: 0)
        #expect(c.accelerated(2) == 2)
        #expect(abs(MacAcceleration.gain(inchesPerSecond: 1, curve: c) - 96) < 1e-9)
        #expect(abs(MacAcceleration.gain(inchesPerSecond: 0, curve: c) - 96) < 1e-9)
    }

    @Test func handComputedValuesAtTheOwnersTrackingSpeed() {
        // 0.875 is the owner's com.apple.trackpad.scaling and an exact table entry (57344).
        let c = MacAcceleration.pointerCurve(trackingSpeed: 0.875)
        #expect(c.curve == MacAcceleration.trackpadPointerCurves[4])
        // 1 in/s = 3.33 counts per 120 Hz report -> floor 3 -> standardized 0.5025.
        #expect(abs(MacAcceleration.gain(inchesPerSecond: 1, curve: c) - 138.562036) < 1e-4)
        // 5 in/s = 16.67 counts -> floor 16 -> standardized 2.68 (below the 7.0 tangent).
        #expect(abs(MacAcceleration.gain(inchesPerSecond: 5, curve: c) - 349.847048) < 1e-4)
    }

    @Test func trackingSpeedBetweenEntriesBlendsTheTwo() {
        let c = MacAcceleration.pointerCurve(trackingSpeed: 0.78125)    // halfway 0.6875 ... 0.875
        let lo = MacAcceleration.trackpadPointerCurves[3], hi = MacAcceleration.trackpadPointerCurves[4]
        #expect(abs(c.curve.gainLinear - (lo.gainLinear + hi.gainLinear) / 2) < 1e-12)
        #expect(abs(c.curve.gainParabolic - (lo.gainParabolic + hi.gainParabolic) / 2) < 1e-12)
        #expect(abs(c.curve.tangentSpeedParabolicRoot - (lo.tangentSpeedParabolicRoot + hi.tangentSpeedParabolicRoot) / 2) < 1e-12)
        // Above the top entry the top curve is used as is.
        #expect(MacAcceleration.pointerCurve(trackingSpeed: 3).curve == MacAcceleration.trackpadPointerCurves[9])
    }

    @Test func segmentsJoinWithoutJumps() {
        for index in [0.0, 0.5, 0.875, 1.5, 3.0] {
            let c = MacAcceleration.pointerCurve(trackingSpeed: index)
            for x in [c.curve.tangentSpeedLinear, c.curve.tangentSpeedParabolicRoot] where x > 0 {
                let below = c.accelerated(x - 1e-7), above = c.accelerated(x + 1e-7)
                #expect(abs(above - below) < 1e-4, "index \(index) at \(x)")
            }
        }
    }

    @Test func gainGrowsWithSpeedAndTrackingSpeed() {
        let c = MacAcceleration.pointerCurve(trackingSpeed: 1)
        // Output speed (gain x finger speed) never drops as the finger speeds up. The gain per
        // inch itself does fall a little at very high speed, where Apple's square-root segment
        // flattens, so that is not asserted.
        let out = stride(from: 0.5, through: 60, by: 0.5).map { $0 * MacAcceleration.gain(inchesPerSecond: $0, curve: c) }
        #expect(zip(out, out.dropFirst()).allSatisfy { $1 >= $0 - 1e-9 })
        #expect(MacAcceleration.gain(inchesPerSecond: 8, curve: c) > MacAcceleration.gain(inchesPerSecond: 0.5, curve: c) * 3)
        let slow = MacAcceleration.gain(inchesPerSecond: 4, curve: MacAcceleration.pointerCurve(trackingSpeed: 0.5))
        let fast = MacAcceleration.gain(inchesPerSecond: 4, curve: MacAcceleration.pointerCurve(trackingSpeed: 2.5))
        #expect(fast > slow * 1.5)
    }

    @Test func scrollCurveAtTheMacDefault() {
        // 0.3125 sits halfway between the 0.125 and 0.5 scroll entries.
        let c = MacAcceleration.scrollCurve(scrollSpeed: TrackpadSettings.defaultScrollSpeed)
        let lo = MacAcceleration.trackpadScrollCurves[1], hi = MacAcceleration.trackpadScrollCurves[2]
        #expect(abs(c.curve.gainParabolic - (lo.gainParabolic + hi.gainParabolic) / 2) < 1e-12)
        #expect(MacAcceleration.gain(inchesPerSecond: 6, curve: c) > MacAcceleration.gain(inchesPerSecond: 1, curve: c))
    }
}

@Suite("Feel: tuning")
struct TuningTests {
    func travel(_ configure: (inout TrackpadSettings) -> Void, perStep: Double = 3, steps: Int = 60) -> Double {
        let s = Script(configure)
        s.down(1, 20, 400)
        s.move([1], dx: perStep, dy: 0, steps: steps)
        return s.moves.reduce(0) { $0 + $1.0 }
    }

    @Test func pointerSpeedMultipliesTravel() {
        let base = travel { _ in }
        let double = travel { $0.tuning.pointerSpeed = 2 }
        #expect(abs(double / base - 2) < 1e-6)
    }

    @Test func accelerationOffIsSpeedIndependent() {
        let slow = travel({ $0.tuning.acceleration = .off }, perStep: 1, steps: 120)
        let fast = travel({ $0.tuning.acceleration = .off }, perStep: 6, steps: 20)
        // Same 120 pt of finger travel (minus the 4 pt start slop handled alike) either way.
        #expect(abs(slow - fast) / fast < 0.02)
        let inch = GestureRecognizer.pointerGain(speed: 500, settings: {
            var s = TrackpadSettings.macDefault; s.tuning.acceleration = .off; return s }())
        #expect(abs(inch * GestureTuning.phonePointsPerInch - 96) < 1e-9)
    }

    @Test func linearIsConstantAndMacCurveIsNot() {
        var lin = TrackpadSettings.macDefault
        lin.tuning.acceleration = .linear
        #expect(GestureRecognizer.pointerGain(speed: 50, settings: lin) == GestureRecognizer.pointerGain(speed: 3000, settings: lin))
        let mac = TrackpadSettings.macDefault
        #expect(GestureRecognizer.pointerGain(speed: 3000, settings: mac) > GestureRecognizer.pointerGain(speed: 50, settings: mac) * 2)
    }

    @Test func scrollSpeedMultipliesScroll() {
        func scrolled(_ k: Double) -> Double {
            let s = Script { $0.tuning.scrollSpeed = k }
            s.down([1: (150, 400), 2: (230, 400)])
            s.move([1, 2], dx: 0, dy: 6, steps: 20)
            return s.scrolls.reduce(0) { $0 + $1.dy }
        }
        #expect(abs(scrolled(2) / scrolled(1) - 2) < 1e-6)
    }

    func momentumTravel(_ strength: Double) -> Double {
        let s = Script { $0.tuning.momentumStrength = strength }
        s.down([1: (150, 300), 2: (230, 300)])
        s.move([1, 2], dx: 0, dy: 12, steps: 10)
        s.advance(0.008)
        s.up([1, 2])
        _ = s.take()
        s.wait(10)
        return s.scrolls.filter { $0.momentum != .none }.reduce(0) { $0 + $1.dy }
    }

    @Test func momentumStrengthScalesCoasting() {
        let normal = momentumTravel(1), long = momentumTravel(2)
        #expect(normal > 0)
        #expect(long > normal * 1.7)
        #expect(momentumTravel(0) == 0)
        // Strength 1 is the platform's 0.998 per millisecond.
        #expect(abs(GestureRecognizer.momentumRate(strength: 1) - (-log(0.998) * 1000)) < 1e-9)
    }

    @Test func clampedPullsWireValuesIntoRange() {
        let t = TrackpadTuning(pointerSpeed: 99, scrollSpeed: -1, momentumStrength: .nan, clickHaptic: 3).clamped
        #expect(t.pointerSpeed == TrackpadTuning.pointerSpeedRange.upperBound)
        #expect(t.scrollSpeed == TrackpadTuning.scrollSpeedRange.lowerBound)
        #expect(t.momentumStrength == 1)
        #expect(t.clickHaptic == 1)
    }
}

@Suite("Feel: settings on the wire")
struct TuningCodingTests {
    @Test func olderSettingsWithoutNewFieldsStillDecode() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TrackpadSettings.macDefault)) as! [String: Any]
        json.removeValue(forKey: "tuning")
        json.removeValue(forKey: "scrollSpeed")
        let old = try JSONSerialization.data(withJSONObject: json)
        let s = try JSONDecoder().decode(TrackpadSettings.self, from: old)
        #expect(s == .macDefault)
        #expect(s.tuning == .default)
        #expect(s.scrollSpeed == TrackpadSettings.defaultScrollSpeed)
    }

    @Test func partialTuningFillsDefaults() throws {
        let t = try JSONDecoder().decode(TrackpadTuning.self, from: Data(#"{"pointerSpeed":1.5,"acceleration":"linear","future":3}"#.utf8))
        #expect(t.pointerSpeed == 1.5)
        #expect(t.acceleration == .linear)
        #expect(t.scrollSpeed == 1 && t.momentumStrength == 1 && t.dragLockHaptic == 1)
    }

    @Test func settingsCarryTuningBothWays() throws {
        var s = TrackpadSettings.macDefault
        s.tuning = TrackpadTuning(pointerSpeed: 0.5, acceleration: .off, scrollSpeed: 2, momentumStrength: 1.5,
                                  clickHaptic: 0.2, forceClickHaptic: 0.4, dragLockHaptic: 0)
        s.scrollSpeed = 0.75
        let m = try ControlMessage.from(jsonData: ControlMessage.settings(s).jsonData())
        #expect(m == .settings(s))
    }

    @Test func hapticScalePerKind() {
        let t = TrackpadTuning(clickHaptic: 0.3, forceClickHaptic: 0.6, dragLockHaptic: 0.9)
        #expect(t.hapticScale(for: .click) == 0.3)
        #expect(t.hapticScale(for: .forceClick) == 0.6)
        #expect(t.hapticScale(for: .dragLock) == 0.9)
        #expect(t.hapticScale(for: .snap) == 0)
    }
}

@Suite("Feel: haptics only for clicks, force click and drag lock")
struct HapticPolicyTests {
    @Test func tapDragBuzzesClickThenDragLock() {
        let s = Script()
        s.down(1, 200, 400); s.advance(0.06); s.up(1)
        s.advance(0.1)
        s.down(1, 205, 402)
        s.move([1], dx: 6, dy: 0, steps: 5)
        s.up(1)
        #expect(s.haptics == [.click, .dragLock])
    }

    @Test func gesturesStaySilent() {
        // Spaces swipe, Mission Control, two-finger scroll, three-finger page swipe, edge swipe.
        let s = Script { $0.swipeBetweenPages = .threeFinger; $0.swipeBetweenSpaces = .four }
        s.down([1: (100, 400), 2: (180, 400), 3: (260, 400), 4: (300, 420)])
        s.move([1, 2, 3, 4], dx: -10, dy: 0, steps: 15); s.up([1, 2, 3, 4]); s.wait(0.5)
        s.down([1: (100, 600), 2: (180, 600), 3: (260, 600)])
        s.move([1, 2, 3], dx: 0, dy: -12, steps: 15); s.up([1, 2, 3]); s.wait(0.5)
        s.down([1: (150, 400), 2: (230, 400)])
        s.move([1, 2], dx: 0, dy: 12, steps: 10); s.advance(0.008); s.up([1, 2]); s.wait(1)
        s.down([1: (100, 400), 2: (180, 400), 3: (260, 400)])
        s.move([1, 2, 3], dx: 10, dy: 0, steps: 10); s.up([1, 2, 3]); s.wait(0.5)
        s.down([1: (380, 400), 2: (385, 450)])
        s.move([1, 2], dx: -6, dy: 0, steps: 10); s.up([1, 2])
        #expect(s.events.contains(.notificationCenter))
        #expect(s.events.contains(.navigate(back: true)))
        #expect(s.swipes.contains { $0.kind == .spaces })
        #expect(s.haptics.isEmpty)
    }

    @Test func twoFingerClickBuzzes() {
        let s = Script { $0.smartZoom = false }
        s.down([1: (150, 400), 2: (230, 400)]); s.advance(0.05); s.up([1, 2])
        #expect(s.haptics == [.click])
    }
}

@Suite("Feel: clock offset")
struct ClockOffsetTests {
    @Test func offsetFollowsSlowDriftUpward() {
        // The Mac's clock gains 100 ppm on the phone's. A min-only estimate would fall behind
        // by 0.1 ms per second; the creep keeps it within a few milliseconds over 60 s.
        let r = GestureRecognizer(settings: .macDefault)
        var t = 100.0
        let surface = CGSize(width: 390, height: 844)
        for _ in 0..<6000 {
            t += 0.01
            let local = 5000 + t * 1.0001 + 0.002
            _ = r.process(TouchFrame(seq: 0, timestamp: t, touches: [], surface: surface), receivedAt: local)
        }
        let trueOffset = 5000 + t * 0.0001 + 0.002
        #expect(abs((r.learnedClockOffset ?? 0) - trueOffset) < 0.003)
    }
}

@Suite("Feel: Wi-Fi path")
struct WiFiPathTests {
    @Test func phoneUsesSharedNetworkUnlessAskedForPeerToPeer() {
        #expect(GlasspadService.tcpParameters().includePeerToPeer == false)
        #expect(GlasspadService.udpParameters().includePeerToPeer == false)
        #expect(GlasspadService.tcpParameters(peerToPeer: true).includePeerToPeer)
        #expect(GlasspadService.udpParameters().serviceClass == .interactiveVoice)
        #expect(GlasspadService.udpParameters().prohibitedInterfaceTypes?.contains(.cellular) == true)
    }
}
