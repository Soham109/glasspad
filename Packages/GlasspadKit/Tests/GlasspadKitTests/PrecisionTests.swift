import Foundation
import Testing
@testable import GlasspadKit

/// Scripted touches with the contact noise a real finger makes on glass: a 1 to 3 pt wobble
/// while the pad lands (radius growing), a 2 to 6 pt roll in the last 30 to 60 ms before lift
/// (radius shrinking), and centroid shifts as other fingers land and lift. 120 Hz frames.
extension Script {
    static let frameStep = 1.0 / 120

    /// One frame: finger `id` moves by (dx, dy), optionally with a new contact radius.
    func step(_ id: UInt8, _ dx: Double, _ dy: Double, radius: Double? = nil, phase: TouchPhase = .moved) {
        advance(Self.frameStep)
        fingers[id]!.x += dx
        fingers[id]!.y += dy
        if let radius { radii[id] = radius }
        send([id: phase], removing: phase == .ended ? [id] : [])
    }

    /// Lands a finger the way a pad does: the radius grows from 60% to full over three frames
    /// while the contact centre wobbles out by `wobble` pt along `angle` and partly back.
    func land(_ id: UInt8, _ x: Double, _ y: Double, wobble: Double, angle: Double, radius: Double = 22) {
        radii[id] = radius * 0.6
        down(id, x, y)
        let ux = cos(angle), uy = sin(angle)
        var at = 0.0
        for (k, f) in [0.6, 1.0, 0.75].enumerated() {
            let target = wobble * f
            step(id, (target - at) * ux, (target - at) * uy, radius: radius * [0.8, 1.0, 1.0][k])
            at = target
        }
    }

    /// Rolls the pad off the glass: `distance` pt along `angle` over `duration`, the radius
    /// shrinking to half (unless `shrink` is false), and the final frame is the lift itself.
    func rollOff(_ id: UInt8, distance: Double, duration: TimeInterval, angle: Double, shrink: Bool = true) {
        let n = max(Int((duration / Self.frameStep).rounded()), 2)
        let r0 = radii[id] ?? 20
        for k in 1...n {
            let r = shrink ? r0 * (1 - 0.5 * Double(k) / Double(n)) : r0
            step(id, distance / Double(n) * cos(angle), distance / Double(n) * sin(angle), radius: r,
                 phase: k == n ? .ended : .moved)
        }
    }

    /// The finger rests: the Mac sees the client's stationary resends every 20 ms.
    func still(_ duration: TimeInterval) { rest(duration) }

    /// Net pointer motion (moves and drags) in `events[range]`.
    func net(_ evs: ArraySlice<GestureEvent>) -> (x: Double, y: Double) {
        var x = 0.0, y = 0.0
        for e in evs {
            switch e {
            case .move(let dx, let dy), .drag(let dx, let dy): x += dx; y += dy
            default: break
            }
        }
        return (x, y)
    }

    /// Net pointer motion before the first button press (where the press lands).
    var netBeforePress: (x: Double, y: Double) {
        let i = events.firstIndex { if case .button(_, true, _) = $0 { return true }; return false } ?? events.count
        return net(events[..<i])
    }

    var pointerEvents: [(Double, Double)] {
        events.compactMap {
            switch $0 {
            case .move(let x, let y), .drag(let x, let y): return (x, y)
            default: return nil
            }
        }
    }
}

private func near(_ v: (x: Double, y: Double), _ tol: Double = 1e-6) -> Bool { abs(v.x) <= tol && abs(v.y) <= tol }
private func len(_ v: (Double, Double)) -> Double { (v.0 * v.0 + v.1 * v.1).squareRoot() }

@Suite("Precision: tap to click")
struct TapPrecisionTests {
    /// Every combination of wobble, roll size, roll duration and directions inside the brief.
    @Test func noisyTapsNeverMoveThePointer() {
        var rng = SeededRandom(seed: 0x7461_7073)
        for round in 0..<200 {
            let s = Script()
            let wobble = Double.random(in: 1...3, using: &rng)
            let roll = Double.random(in: 2...6, using: &rng)
            let rollTime = Double.random(in: 0.03...0.06, using: &rng)
            let a = Double.random(in: 0..<(2 * .pi), using: &rng), b = Double.random(in: 0..<(2 * .pi), using: &rng)
            s.land(1, 200, 400, wobble: wobble, angle: a)
            s.still(Double.random(in: 0...0.06, using: &rng))
            s.rollOff(1, distance: roll, duration: rollTime, angle: b)
            #expect(s.events == leftClick(1), "round \(round): wobble \(wobble) roll \(roll) in \(rollTime)")
        }
    }

    @Test func tapWithoutRadiusWarningStillClicksWhereItLanded() {
        // Worst case for the hold: wobble and roll line up and the radius never changes, so
        // the finger travels 9 pt. Whatever the pointer did, it is back before the click.
        let s = Script()
        s.land(1, 200, 400, wobble: 3, angle: 0)
        s.rollOff(1, distance: 6, duration: 0.03, angle: 0, shrink: false)
        #expect(s.buttons == leftClick(1))
        #expect(near(s.netBeforePress))
    }

    @Test func doubleTapWithNoiseClicksTwiceInPlace() {
        let s = Script()
        s.land(1, 200, 400, wobble: 2, angle: 1)
        s.rollOff(1, distance: 4, duration: 0.04, angle: 2)
        s.wait(0.1)
        s.land(1, 203, 401, wobble: 2.5, angle: 4)
        s.rollOff(1, distance: 5, duration: 0.05, angle: 0.5)
        #expect(s.events == leftClick(1) + leftClick(2))
    }

    @Test func aimThenTapClicksOnTheTarget() {
        // Point at something, rest, lift with a roll, tap: the click lands where the pointer
        // was when the finger settled on the target.
        let s = Script()
        s.land(1, 100, 400, wobble: 2, angle: 0.3)
        s.move([1], dx: 3, dy: 1, steps: 30)
        let aimed = s.net(s.events[...])
        s.still(0.15)
        s.rollOff(1, distance: 5, duration: 0.05, angle: 2.5)
        s.wait(0.12)
        let before = s.events.count
        s.land(1, 190, 431, wobble: 2, angle: 5)
        s.rollOff(1, distance: 3, duration: 0.04, angle: 1)
        let final = s.net(s.events[...])
        #expect(abs(final.x - aimed.x) < 1e-6 && abs(final.y - aimed.y) < 1e-6)
        #expect(Array(s.events[before...]) == leftClick(1))
    }
}

@Suite("Precision: lift-off roll")
struct LiftRollTests {
    @Test func rollAfterRestNeverMovesThePointer() {
        var rng = SeededRandom(seed: 0x726F_6C6C)
        for round in 0..<100 {
            let s = Script()
            s.land(1, 100, 400, wobble: 2, angle: 0)
            s.move([1], dx: 2.5, dy: -1, steps: 40)
            let settled = s.net(s.events[...])
            s.still(Double.random(in: 0.07...0.4, using: &rng))
            let shrink = round % 2 == 0          // half the rolls give no radius warning
            s.rollOff(1, distance: Double.random(in: 2...6, using: &rng),
                      duration: Double.random(in: 0.03...0.06, using: &rng),
                      angle: Double.random(in: 0..<(2 * .pi), using: &rng), shrink: shrink)
            let final = s.net(s.events[...])
            #expect(abs(final.x - settled.x) < 1e-6 && abs(final.y - settled.y) < 1e-6, "round \(round)")
        }
    }

    @Test func rollWithRadiusWarningIsHeldNotUndone() {
        // With the contact shrinking, the roll is held back as it happens: the pointer never
        // moves out and back.
        let s = Script()
        s.land(1, 100, 400, wobble: 2, angle: 0)
        s.move([1], dx: 2.5, dy: 0, steps: 40)
        s.still(0.2)
        let before = s.events.count
        s.rollOff(1, distance: 5, duration: 0.05, angle: 1.2)
        // Only the first roll frame (before the radius can show a drop) gets out; the rest is
        // held and the lift takes that frame back.
        var x = 0.0, y = 0.0, excursion = 0.0
        for e in s.events[before...] { if case .move(let dx, let dy) = e { x += dx; y += dy; excursion = max(excursion, len((x, y))) } }
        #expect(excursion < 1.5, "\(excursion)")
        #expect(near((x, y)))
    }

    @Test func slowingOntoATargetThenRollingIsHeld() {
        // No rest: the finger decelerates onto the target and rolls off straight away.
        let s = Script()
        s.land(1, 100, 400, wobble: 1, angle: 0)
        s.move([1], dx: 3, dy: 0, steps: 20)
        for k in 0..<6 { s.step(1, 1.5 - Double(k) * 0.25, 0) }
        s.step(1, 0.05, 0)
        let settled = s.net(s.events[...])
        s.rollOff(1, distance: 5, duration: 0.04, angle: 2)
        let final = s.net(s.events[...])
        #expect(len((final.x - settled.x, final.y - settled.y)) < 1.0)
    }

    @Test func flickLiftedAtSpeedKeepsAllItsMotion() {
        func travel(shrink: Bool) -> Double {
            let s = Script()
            s.land(1, 50, 400, wobble: 1, angle: 0)
            s.move([1], dx: 6, dy: 0, steps: 25)
            s.rollOff(1, distance: 24, duration: 0.03, angle: 0, shrink: shrink)   // still moving at 6 pt/frame
            return s.net(s.events[...]).x
        }
        let plain = travel(shrink: false), shrinking = travel(shrink: true)
        #expect(plain > 100)
        #expect(abs(shrinking - plain) / plain < 0.01)
    }

    @Test func slowAimingAfterARestDoesNotStutter() {
        // Rest, then a slow precise move at 3 mm/s: every frame moves the pointer, nothing held.
        let s = Script()
        s.land(1, 100, 400, wobble: 2, angle: 0)
        s.move([1], dx: 3, dy: 0, steps: 20)
        s.still(0.2)
        let before = s.events.count
        let perFrame = GestureTuning.points(mm: 3) / 120
        for _ in 0..<40 { s.step(1, perFrame, 0) }
        let out = s.events[before...].compactMap { e -> Double? in if case .move(let x, _) = e { return x }; return nil }
        #expect(out.count == 40)
        #expect(out.allSatisfy { $0 > 0 })
        let gain = s.r.pointerGain(speed: perFrame * 120)
        #expect(abs(out.reduce(0, +) - perFrame * 40 * gain) / (perFrame * 40 * gain) < 0.01)
    }

    @Test func contactNoiseWhileMovingSteadilyHoldsNothing() {
        // The radius jumps by a wire step now and then while the finger moves at a steady speed.
        let s = Script()
        s.land(1, 50, 400, wobble: 1, angle: 0)
        s.move([1], dx: 3, dy: 0, steps: 10)
        let before = s.events.count
        for k in 0..<60 { s.step(1, 3, 0, radius: k % 7 == 0 ? 16 : 22) }
        let out = s.events[before...].compactMap { e -> Double? in if case .move(let x, _) = e { return x }; return nil }
        #expect(out.count == 60)
        let gain = s.r.pointerGain(speed: 360)
        #expect(out.allSatisfy { abs($0 - 3 * gain) / (3 * gain) < 0.35 })
    }
}

@Suite("Precision: touch-down hysteresis")
struct TouchDownTests {
    @Test func deliberateMoveStartsQuicklyWithoutAJumpOrLoss() {
        // 40 mm/s from touch-down: the pointer starts within three frames, no frame jumps,
        // and the total is the full travel at the curve's gain.
        let s = Script()
        s.land(1, 50, 400, wobble: 1.5, angle: 2)
        let wobbleNet = s.net(s.events[...])
        #expect(near(wobbleNet))
        let perFrame = GestureTuning.points(mm: 40) / 120
        var firstMoveFrame: Int?
        var outputs: [Double] = []
        for k in 0..<40 {
            let before = s.events.count
            s.step(1, perFrame, 0)
            let x = s.net(s.events[before...]).x
            outputs.append(x)
            if firstMoveFrame == nil, x > 0 { firstMoveFrame = k }
        }
        #expect((firstMoveFrame ?? 99) <= 3)          // 1 mm at 40 mm/s is 25 ms, plus frame rounding
        let gain = s.r.pointerGain(speed: perFrame * 120)
        let steady = perFrame * gain
        #expect(outputs.allSatisfy { $0 <= steady * 1.8 }, "largest step \(outputs.max() ?? 0) vs steady \(steady)")
        // Travel since the landing (the wobble's net is about -0.75 pt along x, here it is part of the move).
        let travel = s.fingers[1]!.x - 50
        let total = s.net(s.events[...]).x
        #expect(abs(total - travel * gain) / (travel * gain) < 0.03)
    }

    @Test func slowStartIsNotLost() {
        // 4 mm/s from touch-down: held for the tap window, then fed out; nothing lost.
        let s = Script()
        s.land(1, 50, 400, wobble: 1, angle: 0)
        let perFrame = GestureTuning.points(mm: 4) / 120
        for _ in 0..<80 { s.step(1, perFrame, 0) }
        s.still(0.1)
        let travel = s.fingers[1]!.x - 50
        let gain = s.r.pointerGain(speed: perFrame * 120)
        #expect(abs(s.net(s.events[...]).x - travel * gain) / (travel * gain) < 0.05)
        // The held 1 mm goes out over 40 ms: under 1.5 Mac points a frame at this gain.
        #expect(s.pointerEvents.allSatisfy { len($0) < 1.5 }, "\(s.pointerEvents.map { len($0) }.max() ?? 0)")
    }
}

@Suite("Precision: finger changes")
struct FingerChangeTests {
    @Test func staggeredNoisyTwoFingerTapRightClicksWithoutMoving() {
        let s = Script { $0.smartZoom = false }
        s.land(1, 150, 400, wobble: 2.5, angle: 0.5)
        s.land(2, 230, 400, wobble: 3, angle: 3)
        s.rollOff(1, distance: 4, duration: 0.03, angle: 1)
        s.rollOff(2, distance: 5, duration: 0.04, angle: 2)
        #expect(s.events == rightClick)
    }

    @Test func secondFingerLandingForScrollNeverMovesThePointer() {
        let s = Script()
        s.land(1, 150, 400, wobble: 2, angle: 0)
        s.move([1], dx: 3, dy: 0, steps: 20)
        s.still(0.1)
        let before = s.events.count
        s.land(2, 230, 400, wobble: 3, angle: 1)
        s.move([1, 2], dx: 0, dy: 4, steps: 15)
        s.rollOff(2, distance: 5, duration: 0.04, angle: 0)
        s.rollOff(1, distance: 5, duration: 0.04, angle: 3)
        let tail = Array(s.events[before...])
        #expect(!tail.contains { if case .move(let x, let y) = $0 { return x != 0 || y != 0 }; return false }, "\(tail)")
        #expect(tail.contains { if case .scroll(_, _, .began, _) = $0 { return true }; return false })
    }

    @Test func extraFingerThatComesAndGoesHandsBackWithoutAJump() {
        // Pointing, a second finger touches and leaves (no gesture), the first keeps pointing.
        let s = Script()
        s.land(1, 100, 400, wobble: 1, angle: 0)
        s.move([1], dx: 3, dy: 0, steps: 20)
        s.land(2, 250, 500, wobble: 3, angle: 2)
        s.step(1, 0.4, 0); s.step(1, 0.3, 0)
        s.rollOff(2, distance: 6, duration: 0.04, angle: 1)
        let before = s.events.count
        for _ in 0..<20 { s.step(1, 3, 0) }
        let out = s.events[before...].compactMap { e -> Double? in if case .move(let x, let y) = e { return len((x, y)) }; return nil }
        let steady = 3 * s.r.pointerGain(speed: 360)
        #expect(out.count >= 15)
        #expect(out.allSatisfy { $0 <= steady * 1.8 })
        // The second finger's landing wobble and lift roll moved nothing.
        let during = s.net(s.events[(before - 8)..<before])
        #expect(abs(during.y) < 1e-6)
    }

    @Test func extraFingerDuringADragNeverDragsFromItsNoise() {
        let s = Script()
        s.land(1, 200, 400, wobble: 1, angle: 0)
        s.still(0.5)                                  // force click: the button goes down
        s.move([1], dx: 0, dy: 3, steps: 10)          // drag
        s.still(0.2)
        let before = s.events.count
        s.land(2, 300, 600, wobble: 3, angle: 1)
        s.still(0.05)
        s.rollOff(2, distance: 6, duration: 0.04, angle: 2)
        #expect(near(s.net(s.events[before...])))
        #expect(s.r.isLeftButtonDown)
        s.up(1)
        #expect(!s.r.isLeftButtonDown)
    }
}

@Suite("Precision: press position")
struct PressPositionTests {
    @Test func forceClickPressesWhereTheFingerSettled() {
        let s = Script()
        s.land(1, 200, 400, wobble: 3, angle: 1)
        s.step(1, 0.5, 0.5); s.step(1, -0.3, 0.2)       // settling creep
        s.still(0.5)
        #expect(s.events.contains(.forceClick(stage: 1)))
        #expect(near(s.netBeforePress))
    }

    @Test func forceClickDragStartsWithoutAJump() {
        let s = Script()
        s.land(1, 200, 400, wobble: 2, angle: 0)
        s.still(0.5)
        for _ in 0..<20 { s.step(1, 0, 2.5) }
        let drags = s.drags.map { len($0) }
        let steady = 2.5 * s.r.pointerGain(speed: 300)
        #expect(!drags.isEmpty)
        #expect(drags.allSatisfy { $0 <= steady * 1.8 }, "largest \(drags.max() ?? 0) vs \(steady)")
    }

    @Test func tapDragPressesAtTheTapPosition() {
        let s = Script()
        s.land(1, 200, 400, wobble: 2, angle: 0)
        s.rollOff(1, distance: 3, duration: 0.03, angle: 1)
        s.wait(0.05)
        s.land(1, 204, 402, wobble: 2.5, angle: 2)
        for _ in 0..<10 { s.step(1, 3, 0) }
        #expect(s.r.isLeftButtonDown)
        #expect(near(s.netBeforePress))
        let pressIndex = s.events.lastIndex(of: .button(.left, down: true, clickCount: 1))!
        #expect(near(s.net(s.events[..<pressIndex])))
        s.up(1)
        #expect(!s.r.isLeftButtonDown)
    }
}
