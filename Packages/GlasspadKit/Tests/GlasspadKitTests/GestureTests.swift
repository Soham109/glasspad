import Foundation
import CoreGraphics
import Testing
@testable import GlasspadKit

/// Drives a GestureRecognizer with full-snapshot frames, the way the client sends them.
final class Script {
    let r: GestureRecognizer
    var t: TimeInterval = 1000
    var events: [GestureEvent] = []
    var haptics: [HapticKind] = []
    var fingers: [UInt8: (x: Double, y: Double)] = [:]
    /// Contact radius per finger (phone points); 20 when not set.
    var radii: [UInt8: Double] = [:]
    let surface = CGSize(width: 390, height: 844)
    /// Simulates a different caller clock (the Mac's) from the frame clock (the phone's).
    var localOffset: TimeInterval = 0

    init(_ configure: (inout TrackpadSettings) -> Void = { _ in }) {
        var s = TrackpadSettings.macDefault
        configure(&s)
        r = GestureRecognizer(settings: s)
        r.onHaptic = { [unowned self] in self.haptics.append($0) }
    }

    @discardableResult
    func send(_ changed: [UInt8: TouchPhase], removing: Set<UInt8> = []) -> [GestureEvent] {
        var touches: [Touch] = []
        for (id, p) in fingers.sorted(by: { $0.key < $1.key }) {
            touches.append(Touch(id: id, phase: changed[id] ?? .stationary, x: p.x, y: p.y, majorRadius: radii[id] ?? 20))
        }
        let ev = r.process(TouchFrame(seq: 0, timestamp: t, touches: touches, surface: surface), receivedAt: t + localOffset)
        for id in removing { fingers.removeValue(forKey: id); radii.removeValue(forKey: id) }
        events += ev
        return ev
    }

    func down(_ pts: [UInt8: (Double, Double)]) {
        for (id, p) in pts { fingers[id] = p }
        send(pts.mapValues { _ in .began })
    }

    func down(_ id: UInt8, _ x: Double, _ y: Double) { down([id: (x, y)]) }

    func up(_ ids: [UInt8]) {
        send(Dictionary(uniqueKeysWithValues: ids.map { ($0, TouchPhase.ended) }), removing: Set(ids))
    }

    func up(_ id: UInt8) { up([id]) }

    /// Moves the given fingers by (dx, dy) per step, `steps` frames, `dt` apart.
    func move(_ ids: [UInt8], dx: Double, dy: Double, steps: Int, dt: TimeInterval = 0.008) {
        for _ in 0..<steps {
            advance(dt)
            for id in ids { fingers[id]!.x += dx; fingers[id]!.y += dy }
            send(Dictionary(uniqueKeysWithValues: ids.map { ($0, TouchPhase.moved) }))
        }
    }

    /// Moves each finger with its own per-step delta.
    func moveEach(_ deltas: [UInt8: (Double, Double)], steps: Int, dt: TimeInterval = 0.008) {
        for _ in 0..<steps {
            advance(dt)
            for (id, d) in deltas { fingers[id]!.x += d.0; fingers[id]!.y += d.1 }
            send(deltas.mapValues { _ in .moved })
        }
    }

    /// Fingers rest: stationary snapshots every 20 ms (what the client resends), ticking in between.
    func rest(_ duration: TimeInterval) {
        var left = duration
        while left > 1e-9 {
            let step = min(0.02, left)
            advance(step)
            left -= step
            if !fingers.isEmpty { send([:]) }
        }
    }

    /// Time passes with ticks every 8 ms and no frames.
    func wait(_ duration: TimeInterval) {
        var left = duration
        while left > 1e-9 {
            let step = min(0.008, left)
            advance(step)
            left -= step
        }
    }

    func advance(_ dt: TimeInterval) {
        t += dt
        events += r.tick(now: t + localOffset)
    }

    func take() -> [GestureEvent] { defer { events = [] }; return events }

    // Event filters.
    var buttons: [GestureEvent] { events.filter { if case .button = $0 { return true }; return false } }
    var moves: [(Double, Double)] { events.compactMap { if case .move(let x, let y) = $0 { return (x, y) }; return nil } }
    var drags: [(Double, Double)] { events.compactMap { if case .drag(let x, let y) = $0 { return (x, y) }; return nil } }
    var scrolls: [(dx: Double, dy: Double, phase: ScrollPhase, momentum: MomentumPhase)] {
        events.compactMap { if case .scroll(let x, let y, let p, let m) = $0 { return (x, y, p, m) }; return nil }
    }
    var swipes: [(kind: SwipeKind, progress: Double, phase: GesturePhase)] {
        events.compactMap { if case .swipe(let k, let p, let ph) = $0 { return (k, p, ph) }; return nil }
    }
}

func leftClick(_ n: Int) -> [GestureEvent] {
    [.button(.left, down: true, clickCount: n), .button(.left, down: false, clickCount: n)]
}
let rightClick: [GestureEvent] = [.button(.right, down: true, clickCount: 1), .button(.right, down: false, clickCount: 1)]

@Suite("Gestures: taps and clicks")
struct TapTests {
    @Test func tapClicks() {
        let s = Script()
        s.down(1, 200, 400)
        s.advance(0.08)
        s.up(1)
        #expect(s.events == leftClick(1))
        #expect(s.haptics == [.click])
        #expect(!s.r.isLeftButtonDown)
    }

    @Test func tapClicksEvenWithMacTapToClickOff() {
        let s = Script { $0.tapToClick = false }
        s.down(1, 200, 400); s.advance(0.05); s.up(1)
        #expect(s.events == leftClick(1))
    }

    @Test func doubleAndTripleTap() {
        let s = Script()
        for _ in 0..<3 {
            s.down(1, 200, 400); s.advance(0.06); s.up(1); s.wait(0.12)
        }
        #expect(s.buttons == leftClick(1) + leftClick(2) + leftClick(3))
    }

    @Test func tapsFarApartAreSingleClicks() {
        let s = Script()
        s.down(1, 100, 100); s.advance(0.05); s.up(1); s.wait(0.1)
        s.down(1, 300, 700); s.advance(0.05); s.up(1)
        #expect(s.buttons == leftClick(1) + leftClick(1))
    }

    @Test func slowTapIsNotAClick() {
        let s = Script()
        s.down(1, 200, 400); s.rest(0.38); s.up(1)
        #expect(s.buttons.isEmpty)
    }

    @Test func tinyWiggleStillClicks() {
        let s = Script()
        s.down(1, 200, 400)
        s.move([1], dx: 1.5, dy: 1, steps: 4)
        s.up(1)
        #expect(s.buttons == leftClick(1))
    }

    @Test func twoFingerTapRightClicksImmediatelyWithoutSmartZoom() {
        let s = Script { $0.smartZoom = false }
        s.down([1: (150, 400), 2: (230, 400)]); s.advance(0.07); s.up([1, 2])
        #expect(s.events == rightClick)
    }

    @Test func twoFingerTapWaitsForSmartZoomGap() {
        let s = Script()
        s.down([1: (150, 400), 2: (230, 400)]); s.advance(0.07); s.up([1, 2])
        #expect(s.buttons.isEmpty)
        #expect(s.r.needsTick)
        s.wait(0.3)
        #expect(s.buttons == rightClick)
        #expect(!s.r.needsTick)
    }

    @Test func staggeredTwoFingerTap() {
        let s = Script { $0.smartZoom = false }
        s.down(1, 150, 400); s.advance(0.02)
        s.down(2, 230, 400); s.advance(0.06)
        s.up(1); s.advance(0.03); s.up(2)
        #expect(s.events == rightClick)
    }

    @Test func twoFingerDoubleTapIsSmartMagnify() {
        let s = Script()
        s.down([1: (150, 400), 2: (230, 400)]); s.advance(0.06); s.up([1, 2])
        s.wait(0.1)
        s.down([1: (152, 402), 2: (232, 401)]); s.advance(0.06); s.up([1, 2])
        s.wait(0.5)
        #expect(s.events == [.smartMagnify])
    }

    @Test func cornerSecondaryClick() {
        let s = Script { $0.secondaryClick = .bottomRight }
        s.down(1, 360, 820); s.advance(0.05); s.up(1); s.wait(0.6)
        #expect(s.events == rightClick)
        _ = s.take()
        s.down(1, 30, 820); s.advance(0.05); s.up(1)
        #expect(s.events == leftClick(1))
        let l = Script { $0.secondaryClick = .bottomLeft }
        l.down(1, 30, 820); l.advance(0.05); l.up(1)
        #expect(l.events == rightClick)
    }

    @Test func secondaryOffMeansTwoFingerTapDoesNothing() {
        let s = Script { $0.secondaryClick = .off; $0.smartZoom = false }
        s.down([1: (150, 400), 2: (230, 400)]); s.advance(0.06); s.up([1, 2]); s.wait(0.5)
        #expect(s.events.isEmpty)
    }

    @Test func threeFingerTapLooksUp() {
        let s = Script { $0.lookUp = .threeFingerTap }
        s.down([1: (100, 400), 2: (180, 400), 3: (260, 400)]); s.advance(0.08); s.up([1, 2, 3])
        #expect(s.events == [.lookUp])
        let off = Script()
        off.down([1: (100, 400), 2: (180, 400), 3: (260, 400)]); off.advance(0.08); off.up([1, 2, 3])
        #expect(off.events.isEmpty)
    }
}

@Suite("Gestures: pointer, drag, force click")
struct PointerTests {
    @Test func pointerMovesWithoutClicking() {
        let s = Script()
        s.down(1, 100, 400)
        s.move([1], dx: 5, dy: -2, steps: 20)
        s.up(1)
        #expect(s.buttons.isEmpty)
        let total = s.moves.reduce(0) { $0 + $1.0 }
        let totalY = s.moves.reduce(0) { $0 + $1.1 }
        #expect(total > 100)
        #expect(totalY < 0)
        #expect(s.drags.isEmpty)
    }

    @Test func pointerFollowsTheMacCurveInPhysicalUnits() {
        // 3.2 pt per frame; frames under one 120 Hz report count as one: 384 pt/s = 2.5 in/s.
        let s = Script { $0.trackingSpeed = 0.875 }
        s.down(1, 0, 400)
        s.move([1], dx: 3.2, dy: 0, steps: 120)
        let total = s.moves.reduce(0) { $0 + $1.0 }
        let inches = 3.2 * 120 / GestureTuning.phonePointsPerInch
        let expected = inches * MacAcceleration.gain(inchesPerSecond: 3.2 * 120 / GestureTuning.phonePointsPerInch,
                                                     curve: MacAcceleration.pointerCurve(trackingSpeed: 0.875))
        // The first move carries the slop distance at an unsettled speed; the rest is exact.
        #expect(abs(total - expected) / expected < 0.03)
    }

    @Test func accelerationAndTrackingSpeed() {
        func travel(speed: Double, tracking: Double) -> Double {
            let s = Script { $0.trackingSpeed = tracking }
            s.down(1, 10, 400)
            let steps = Int(200 / (speed * 0.008))
            s.move([1], dx: 200 / Double(steps), dy: 0, steps: steps)
            return s.moves.reduce(0) { $0 + $1.0 }
        }
        #expect(travel(speed: 1500, tracking: 1) > travel(speed: 100, tracking: 1) * 1.5)
        #expect(travel(speed: 600, tracking: 3) > travel(speed: 600, tracking: 1) * 1.5)
        #expect(travel(speed: 600, tracking: 0) < travel(speed: 600, tracking: 1))
    }

    @Test func tapThenTouchAndMoveDrags() {
        let s = Script()
        s.down(1, 200, 400); s.advance(0.06); s.up(1)
        s.advance(0.1)
        s.down(1, 205, 402)
        s.move([1], dx: 6, dy: 0, steps: 10)
        #expect(s.r.isLeftButtonDown)
        s.up(1)
        #expect(s.buttons == leftClick(1) + leftClick(1))
        #expect(!s.drags.isEmpty)
        #expect(s.moves.isEmpty)
        #expect(!s.r.isLeftButtonDown)
    }

    @Test func touchAfterTapDragWindowJustMoves() {
        let s = Script()
        s.down(1, 200, 400); s.advance(0.06); s.up(1)
        s.wait(0.4)
        s.down(1, 205, 402)
        s.move([1], dx: 6, dy: 0, steps: 10)
        s.up(1)
        #expect(s.buttons == leftClick(1))
        #expect(s.drags.isEmpty)
        #expect(!s.moves.isEmpty)
    }

    @Test func pressAndHoldForceClicks() {
        let s = Script()
        s.down(1, 200, 400)
        s.rest(0.3)
        #expect(s.events.isEmpty)
        s.rest(0.2)
        #expect(s.events == [.button(.left, down: true, clickCount: 1), .forceClick(stage: 1)])
        s.rest(0.3)
        #expect(s.events.last == .forceClick(stage: 2))
        #expect(s.haptics == [.click, .forceClick])
        s.up(1)
        #expect(s.events.last == .button(.left, down: false, clickCount: 1))
        #expect(!s.r.isLeftButtonDown)
    }

    @Test func holdThenMoveDrags() {
        let s = Script()
        s.down(1, 200, 400)
        s.rest(0.5)
        s.move([1], dx: 0, dy: 8, steps: 10)
        s.up(1)
        #expect(!s.drags.isEmpty)
        #expect(s.drags.reduce(0) { $0 + $1.1 } > 40)
        #expect(!s.events.contains(.forceClick(stage: 2)))
        #expect(s.buttons == [.button(.left, down: true, clickCount: 1), .button(.left, down: false, clickCount: 1)])
    }

    @Test func holdWorksAcrossDifferentClocks() {
        let s = Script()
        s.localOffset = 86_400 * 3      // Mac uptime far from phone uptime
        s.down(1, 200, 400)
        s.rest(0.3)
        #expect(s.events.isEmpty)
        s.rest(0.2)
        #expect(s.events.contains(.forceClick(stage: 1)))
        s.up(1)
        #expect(!s.r.isLeftButtonDown)
    }

    @Test func phoneSideHoldWithoutResends() {
        let s = Script()
        s.r.staleTouchTimeout = nil     // phone: UIKit sends nothing for a resting finger
        s.down(1, 200, 400)
        s.wait(0.5)                     // ticks only, no frames
        #expect(s.events.contains(.forceClick(stage: 1)))
        s.wait(0.3)
        #expect(s.events.contains(.forceClick(stage: 2)))
        s.up(1)
        #expect(!s.r.isLeftButtonDown)
    }

    @Test func threeFingerDrag() {
        let s = Script { $0.threeFingerDrag = true }
        s.down([1: (100, 400), 2: (180, 400), 3: (260, 400)])
        s.move([1, 2, 3], dx: 5, dy: 3, steps: 10)
        #expect(s.r.isLeftButtonDown)
        #expect(!s.drags.isEmpty)
        #expect(s.swipes.isEmpty)
        s.up(2)                          // lifting any finger ends the drag at once
        #expect(!s.r.isLeftButtonDown)
        s.move([1, 3], dx: 5, dy: 0, steps: 5)
        s.up([1, 3])
        #expect(s.buttons == [.button(.left, down: true, clickCount: 1), .button(.left, down: false, clickCount: 1)])
    }
}

@Suite("Gestures: scroll and momentum")
struct ScrollTests {
    @Test func twoFingerScrollPhasesNatural() {
        let s = Script()
        s.down([1: (150, 400), 2: (230, 400)])
        s.move([1, 2], dx: 0, dy: 10, steps: 10)
        s.rest(0.15)
        s.up([1, 2])
        let sc = s.scrolls
        #expect(sc.first?.phase == .began)
        #expect(sc.first.map { $0.dy > 0 } == true)            // fingers down -> content down (natural)
        #expect(sc.dropFirst().dropLast().allSatisfy { $0.phase == .changed && $0.momentum == .none })
        #expect(sc.last?.phase == .ended)
        // 10 pt per 8 ms throughout; steps shorter than one 120 Hz report count as one report,
        // so every step sees 1200 pt/s on the Mac's scroll curve.
        let speed = 10 * 120 / GestureTuning.phonePointsPerInch
        let perPoint = MacAcceleration.gain(inchesPerSecond: speed, curve: MacAcceleration.scrollCurve(scrollSpeed: 0.3125))
            * GestureTuning.scrollCalibration / GestureTuning.phonePointsPerInch
        #expect(abs(sc.reduce(0) { $0 + $1.dy } - 100 * perPoint) < 0.01)
        s.wait(0.3)
        #expect(!s.scrolls.contains { $0.momentum != .none })  // rested before lifting: no momentum
        #expect(s.buttons.isEmpty && s.moves.isEmpty)
    }

    @Test func traditionalScrollingInverts() {
        let s = Script { $0.naturalScrolling = false }
        s.down([1: (150, 400), 2: (230, 400)])
        s.move([1, 2], dx: 4, dy: 10, steps: 5)
        #expect(s.scrolls.allSatisfy { $0.dy < 0 && $0.dx < 0 })
    }

    @Test func flickProducesDecayingMomentum() {
        let s = Script()
        s.down([1: (150, 300), 2: (230, 300)])
        s.move([1, 2], dx: 0, dy: 12, steps: 10)
        s.advance(0.008)
        s.up([1, 2])
        _ = s.take()
        s.wait(6)
        let m = s.scrolls
        #expect(m.first?.momentum == .began)
        #expect(m.last?.momentum == .ended)
        #expect(m.allSatisfy { $0.phase == .none })
        let dys = m.dropLast().map(\.dy)
        #expect(dys.count > 20)
        #expect(zip(dys, dys.dropFirst()).allSatisfy { $0 >= $1 - 1e-9 })
        #expect(dys.allSatisfy { $0 > 0 })
        #expect(!s.r.needsTick)
    }

    @Test func momentumOffMeansNone() {
        let s = Script { $0.scrollMomentum = false }
        s.down([1: (150, 300), 2: (230, 300)])
        s.move([1, 2], dx: 0, dy: 12, steps: 10)
        s.up([1, 2])
        s.wait(0.5)
        #expect(!s.scrolls.contains { $0.momentum != .none })
    }

    @Test func newTouchStopsMomentum() {
        let s = Script()
        s.down([1: (150, 300), 2: (230, 300)])
        s.move([1, 2], dx: 0, dy: 12, steps: 10)
        s.up([1, 2])
        s.wait(0.1)
        _ = s.take()
        s.down(1, 200, 400)
        #expect(s.scrolls.map(\.momentum) == [.ended])
        s.wait(0.3)
        #expect(s.scrolls.count == 1)
    }

    @Test func staggeredLiftStillGivesMomentum() {
        let s = Script()
        s.down([1: (150, 300), 2: (230, 300)])
        s.move([1, 2], dx: 0, dy: 12, steps: 10)
        s.up(2)
        s.advance(0.04)
        s.up(1)
        s.wait(0.3)
        #expect(s.scrolls.contains { $0.momentum == .began })
        #expect(s.moves.isEmpty)
    }

    @Test func remainingFingerAfterScrollDoesNotMovePointer() {
        let s = Script()
        s.down([1: (150, 300), 2: (230, 300)])
        s.move([1, 2], dx: 0, dy: 12, steps: 10)
        s.up(2)
        s.rest(0.3)
        s.move([1], dx: 5, dy: 0, steps: 10)
        s.up(1)
        #expect(s.moves.isEmpty)
        #expect(s.scrolls.filter { $0.phase == .ended }.count == 1)
        #expect(!s.scrolls.contains { $0.momentum != .none })
    }

    @Test func fingerAddedMidScrollEndsScrollAndStartsSwipe() {
        let s = Script()
        s.down([1: (150, 400), 2: (230, 400)])
        s.move([1, 2], dx: 0, dy: 8, steps: 5)
        s.down(3, 300, 440)
        let sc = s.scrolls
        #expect(sc.last?.phase == .ended)
        #expect(sc.filter { $0.phase == .ended }.count == 1)
        s.move([1, 2, 3], dx: -10, dy: 0, steps: 8)
        s.up([1, 2, 3])
        #expect(s.swipes.first?.kind == .spaces)
        #expect(s.swipes.last?.phase == .ended)
        #expect(s.scrolls.count == sc.count)                    // no scroll after the third finger
        #expect(!s.scrolls.contains { $0.momentum != .none })
    }

    @Test func cancelDuringScroll() {
        let s = Script()
        s.down([1: (150, 400), 2: (230, 400)])
        s.move([1, 2], dx: 0, dy: 8, steps: 5)
        s.send([1: .cancelled, 2: .cancelled], removing: [1, 2])
        #expect(s.scrolls.last?.phase == .cancelled)
        s.wait(0.5)
        #expect(!s.scrolls.contains { $0.momentum != .none })
    }
}

@Suite("Gestures: pinch, rotate, swipes")
struct MultiFingerTests {
    @Test func pinchOutMagnifies() {
        let s = Script()
        s.down([1: (150, 400), 2: (250, 400)])
        s.moveEach([1: (-5, 0), 2: (5, 0)], steps: 10)
        s.up([1, 2])
        let mags = s.events.compactMap { e -> (Double, GesturePhase)? in
            if case .magnify(let d, let p) = e { return (d, p) }; return nil
        }
        #expect(mags.first?.1 == .began)
        #expect(mags.last?.1 == .ended)
        let scale = mags.reduce(1.0) { $0 * (1 + $1.0) }
        #expect(abs(scale - 2.0) < 0.01)
        #expect(s.scrolls.isEmpty)
        #expect(s.buttons.isEmpty)
    }

    @Test func pinchInShrinks() {
        let s = Script()
        s.down([1: (100, 400), 2: (300, 400)])
        s.moveEach([1: (5, 0), 2: (-5, 0)], steps: 10)
        let total = s.events.reduce(0.0) { if case .magnify(let d, _) = $1 { return $0 + d }; return $0 }
        #expect(total < -0.3)
    }

    @Test func rotateCounterclockwiseIsPositive() {
        let s = Script()
        let c = (200.0, 400.0), r = 50.0
        func pos(_ a: Double) -> [UInt8: (Double, Double)] {
            [1: (c.0 - r * cos(a), c.1 + r * sin(a)), 2: (c.0 + r * cos(a), c.1 - r * sin(a))]
        }
        s.down(pos(0))
        for i in 1...20 {
            s.advance(0.008)
            for (id, p) in pos(Double(i) * 2 * .pi / 180) { s.fingers[id] = p }
            s.send([1: .moved, 2: .moved])
        }
        s.up([1, 2])
        let rots = s.events.compactMap { e -> (Double, GesturePhase)? in
            if case .rotate(let d, let p) = e { return (d, p) }; return nil
        }
        #expect(rots.first?.1 == .began)
        #expect(rots.last?.1 == .ended)
        #expect(abs(rots.reduce(0) { $0 + $1.0 } - 40) < 0.5)
        #expect(s.scrolls.isEmpty)
    }

    @Test func pinchAndRotateRespectSettings() {
        let s = Script { $0.pinchToZoom = false; $0.rotate = false }
        s.down([1: (150, 400), 2: (250, 400)])
        s.moveEach([1: (-5, 0), 2: (5, 0)], steps: 10)
        #expect(!s.events.contains { if case .magnify = $0 { return true }; return false })
    }

    @Test func threeFingerSwipeLeftFollowsFingersForSpaces() {
        let s = Script()
        s.down([1: (100, 400), 2: (180, 400), 3: (260, 400)])
        s.move([1, 2, 3], dx: -10, dy: 1, steps: 10)
        s.up([1, 2, 3])
        let sw = s.swipes
        #expect(sw.allSatisfy { $0.kind == .spaces })
        #expect(sw.first?.phase == .began)
        #expect(sw.last?.phase == .ended)
        let progress = sw.map(\.progress)
        #expect(zip(progress, progress.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(abs((progress.last ?? 0) - 100 / GestureTuning.swipeFullDistance) < 0.001)
        #expect(s.haptics.isEmpty)          // Spaces never buzz
        #expect(s.buttons.isEmpty && s.moves.isEmpty && s.scrolls.isEmpty)
    }

    @Test func swipeReversalGoesNegative() {
        let s = Script()
        s.down([1: (100, 400), 2: (180, 400), 3: (260, 400)])
        s.move([1, 2, 3], dx: -10, dy: 0, steps: 3)
        s.move([1, 2, 3], dx: 10, dy: 0, steps: 8)
        s.up([1, 2, 3])
        #expect((s.swipes.last?.progress ?? 0) < 0)
    }

    @Test func missionControlAndAppExpose() {
        let up = Script()
        up.down([1: (100, 500), 2: (180, 500), 3: (260, 500)])
        up.move([1, 2, 3], dx: 0, dy: -10, steps: 8)
        up.up([1, 2, 3])
        #expect(up.swipes.first?.kind == .missionControl)
        #expect((up.swipes.last?.progress ?? 0) > 0)

        let down = Script { $0.appExpose = .three }
        down.down([1: (100, 300), 2: (180, 300), 3: (260, 300)])
        down.move([1, 2, 3], dx: 0, dy: 10, steps: 8)
        down.up([1, 2, 3])
        #expect(down.swipes.first?.kind == .appExpose)
        #expect((down.swipes.last?.progress ?? 0) > 0)

        // App Exposé off: swiping down drives Mission Control backwards (closes it if open).
        let back = Script()
        back.down([1: (100, 300), 2: (180, 300), 3: (260, 300)])
        back.move([1, 2, 3], dx: 0, dy: 10, steps: 8)
        #expect(back.swipes.first?.kind == .missionControl)
        #expect((back.swipes.last?.progress ?? 0) < 0)
    }

    @Test func fingerCountClassification() {
        let s = Script { $0.swipeBetweenSpaces = .four; $0.missionControl = .four; $0.swipeBetweenPages = .off }
        s.down([1: (100, 400), 2: (180, 400), 3: (260, 400)])
        s.move([1, 2, 3], dx: -10, dy: 0, steps: 8)
        s.up([1, 2, 3])
        #expect(s.swipes.isEmpty)                              // three fingers are unassigned
        s.wait(0.5)
        s.down([1: (60, 400), 2: (140, 400), 3: (220, 400), 4: (300, 400)])
        s.move([1, 2, 3, 4], dx: -10, dy: 0, steps: 8)
        s.up([1, 2, 3, 4])
        #expect(s.swipes.first?.kind == .spaces)
    }

    @Test func axisLocksAfterTwelvePoints() {
        let s = Script()
        s.down([1: (100, 400), 2: (180, 400), 3: (260, 400)])
        s.move([1, 2, 3], dx: -2, dy: 0, steps: 5)              // 10 pt: still undecided
        #expect(s.swipes.isEmpty)
        s.move([1, 2, 3], dx: -1, dy: -8, steps: 6)             // now mostly vertical, but the lock already...
        #expect(s.swipes.first != nil)
    }

    @Test func threeFingerPageSwipeNavigates() {
        let s = Script { $0.swipeBetweenPages = .threeFinger; $0.swipeBetweenSpaces = .four }
        s.down([1: (100, 400), 2: (180, 400), 3: (260, 400)])
        s.move([1, 2, 3], dx: 10, dy: 0, steps: 10)
        s.up([1, 2, 3])
        #expect(s.events == [.navigate(back: true)])
        let fwd = Script { $0.swipeBetweenPages = .twoOrThree; $0.swipeBetweenSpaces = .four }
        fwd.down([1: (100, 400), 2: (180, 400), 3: (260, 400)])
        fwd.move([1, 2, 3], dx: -10, dy: 0, steps: 10)
        #expect(fwd.events == [.navigate(back: false)])
    }

    @Test func launchpadPinchAndShowDesktopSpread() {
        let pinch = Script()
        pinch.down([1: (120, 400), 2: (280, 400), 3: (200, 320), 4: (200, 480)])
        pinch.moveEach([1: (5, 0), 2: (-5, 0), 3: (0, 5), 4: (0, -5)], steps: 10)
        pinch.up([1, 2, 3, 4])
        #expect(pinch.swipes.first?.kind == .launchpad)
        #expect(pinch.swipes.last?.phase == .ended)
        #expect(abs((pinch.swipes.last?.progress ?? 0) - 50.0 / GestureTuning.spreadFullDistance) < 0.01)

        let spread = Script()
        spread.down([1: (170, 400), 2: (230, 400), 3: (200, 370), 4: (200, 430)])
        spread.moveEach([1: (-5, 0), 2: (5, 0), 3: (0, -5), 4: (0, 5)], steps: 10)
        spread.up([1, 2, 3, 4])
        #expect(spread.swipes.first?.kind == .showDesktop)
        #expect((spread.swipes.last?.progress ?? 0) > 0.5)

        let off = Script { $0.launchpadPinch = false }
        off.down([1: (120, 400), 2: (280, 400), 3: (200, 320), 4: (200, 480)])
        off.moveEach([1: (5, 0), 2: (-5, 0), 3: (0, 5), 4: (0, -5)], steps: 10)
        #expect(off.swipes.isEmpty)
    }

    @Test func notificationCenterFromRightEdge() {
        let s = Script()
        s.down([1: (380, 380), 2: (382, 440)])
        s.move([1, 2], dx: -10, dy: 0, steps: 8)
        s.up([1, 2])
        #expect(s.events == [.notificationCenter])
        // Same motion away from the edge is a scroll.
        let mid = Script()
        mid.down([1: (200, 380), 2: (202, 440)])
        mid.move([1, 2], dx: -10, dy: 0, steps: 8)
        #expect(mid.events.first.map { if case .scroll = $0 { return true }; return false } == true)
        // Turned off: edge swipe scrolls.
        let off = Script { $0.notificationCenterEdge = false }
        off.down([1: (380, 380), 2: (382, 440)])
        off.move([1, 2], dx: -10, dy: 0, steps: 8)
        #expect(!off.events.contains(.notificationCenter))
    }

    @Test func fingerAddedMidSwipeKeepsSwipe() {
        let s = Script()
        s.down([1: (100, 400), 2: (180, 400), 3: (260, 400)])
        s.move([1, 2, 3], dx: -10, dy: 0, steps: 4)
        s.down(4, 300, 450)
        s.move([1, 2, 3, 4], dx: -10, dy: 0, steps: 4)
        s.up([1, 2, 3, 4])
        let sw = s.swipes
        #expect(sw.allSatisfy { $0.kind == .spaces })
        #expect(sw.filter { $0.phase == .began }.count == 1)
        #expect(sw.filter { $0.phase == .ended }.count == 1)
        #expect(abs((sw.last?.progress ?? 0) - 80 / GestureTuning.swipeFullDistance) < 0.001)
    }
}

@Suite("Gestures: never a stuck button")
struct StuckButtonTests {
    func startDrag() -> Script {
        let s = Script()
        s.down(1, 200, 400); s.advance(0.05); s.up(1); s.advance(0.08)
        s.down(1, 200, 400)
        s.move([1], dx: 6, dy: 0, steps: 5)
        #expect(s.r.isLeftButtonDown)
        return s
    }

    @Test func cancelledTouchReleases() {
        let s = startDrag()
        s.send([1: .cancelled], removing: [1])
        #expect(!s.r.isLeftButtonDown)
        #expect(s.events.last == .button(.left, down: false, clickCount: 1))
    }

    @Test func silentLinkReleasesAfterTimeout() {
        let s = startDrag()
        s.wait(0.3)
        #expect(s.r.isLeftButtonDown)
        s.wait(0.4)
        #expect(!s.r.isLeftButtonDown)
        #expect(s.events.last == .button(.left, down: false, clickCount: 1))
    }

    @Test func lostEndedPacketHealsOnNextSnapshot() {
        let s = startDrag()
        s.fingers = [:]
        s.advance(0.02)
        s.send([:])                      // empty snapshot: the "ended" frame was lost
        #expect(!s.r.isLeftButtonDown)
    }

    @Test func cancelAllReleasesEverything() {
        let s = startDrag()
        let ev = s.r.cancelAll()
        #expect(ev == [.button(.left, down: false, clickCount: 1)])
        #expect(!s.r.isLeftButtonDown)
        #expect(!s.r.needsTick)
        let h = Script()
        h.down(1, 200, 400); h.rest(0.6)
        #expect(h.r.isLeftButtonDown)
        #expect(h.r.cancelAll().contains(.button(.left, down: false, clickCount: 1)))
    }

    @Test func extraFingerDuringDragKeepsButtonUntilAllLift() {
        let s = startDrag()
        s.down(2, 260, 420)
        s.move([1, 2], dx: 4, dy: 0, steps: 3)
        #expect(s.r.isLeftButtonDown)
        s.up(1)
        #expect(s.r.isLeftButtonDown)
        s.move([2], dx: 4, dy: 0, steps: 3)
        s.up(2)
        #expect(!s.r.isLeftButtonDown)
        let downs = s.buttons.filter { if case .button(.left, true, _) = $0 { return true }; return false }
        let ups = s.buttons.filter { if case .button(.left, false, _) = $0 { return true }; return false }
        #expect(downs.count == ups.count)
    }

    @Test func latePacketsAreDropped() {
        let s = Script()
        s.down(1, 200, 400)
        s.move([1], dx: 10, dy: 0, steps: 3)
        let late = TouchFrame(seq: 0, timestamp: s.t - 0.01, touches: [Touch(id: 1, phase: .moved, x: 0, y: 0)], surface: s.surface)
        #expect(s.r.process(late, receivedAt: s.t).isEmpty)
        #expect(s.r.fingerCount == 1)
    }

    /// The client stamps a resent resting snapshot with the time it sends it, while the app's
    /// frames carry the touch's own (earlier) time. A lift delivered just after a resend is
    /// therefore older than the last frame. Dropping it as a late packet lost the tap.
    @Test func liftStampedBeforeAResendStillCounts() {
        let s = Script { $0.tapToClick = true }
        s.down(1, 200, 400)
        s.advance(0.03)
        s.send([:])                     // resend at the client's clock
        let lift = TouchFrame(seq: 0, timestamp: s.t - 0.004, touches: [Touch(id: 1, phase: .ended, x: 200, y: 400)],
                              surface: s.surface)
        s.events += s.r.process(lift, receivedAt: s.t + 0.001)
        #expect(s.r.fingerCount == 0)
        s.wait(0.6)
        #expect(s.buttons == leftClick(1))
        #expect(!s.events.contains { if case .forceClick = $0 { return true }; return false })
    }

    /// A late lift for a finger that is already gone changes nothing (no ghost fingers).
    @Test func lateLiftOfAGoneFingerIsIgnored() {
        let s = Script { $0.tapToClick = true }
        s.down([1: (100, 400), 2: (200, 400)])
        s.advance(0.03)
        s.up(2)
        let late = TouchFrame(seq: 0, timestamp: s.t - 0.004,
                              touches: [Touch(id: 1, phase: .stationary, x: 100, y: 400), Touch(id: 2, phase: .ended, x: 200, y: 400)],
                              surface: s.surface)
        #expect(s.r.process(late, receivedAt: s.t).isEmpty)
        #expect(s.r.fingerCount == 1)
    }

    /// The "ended" packet was lost; the empty snapshot the client sends after the last lift
    /// still lifts the finger, and the tap clicks.
    @Test func emptySnapshotAfterALostLiftClicks() {
        let s = Script { $0.tapToClick = true }
        s.down(1, 200, 400)
        s.rest(0.06)
        s.fingers = [:]
        s.send([:])
        #expect(s.r.fingerCount == 0)
        #expect(s.buttons == leftClick(1))
    }

    @Test func phoneClockRestartCancels() {
        let s = startDrag()
        let fresh = TouchFrame(seq: 0, timestamp: 5, touches: [], surface: s.surface)
        let ev = s.r.process(fresh, receivedAt: s.t)
        #expect(ev.contains(.button(.left, down: false, clickCount: 1)))
        #expect(!s.r.isLeftButtonDown)
    }

    @Test func randomSequencesNeverLeaveButtonsDown() {
        var rng = SeededRandom(seed: 0x6C61_7373)
        for round in 0..<40 {
            let s = Script {
                $0.threeFingerDrag = round % 2 == 0
                $0.smartZoom = round % 3 != 0
                $0.lookUp = round % 4 == 0 ? .threeFingerTap : .forceClick
                $0.secondaryClick = round % 5 == 0 ? .bottomLeft : .twoFinger
            }
            var nextID: UInt8 = 1
            for _ in 0..<400 {
                let roll = Int.random(in: 0..<100, using: &rng)
                switch roll {
                case 0..<18 where s.fingers.count < 5:
                    let x = Double.random(in: 0...390, using: &rng), y = Double.random(in: 0...844, using: &rng)
                    s.down(nextID, x, y)
                    nextID = nextID == 250 ? 1 : nextID + 1
                case 18..<30 where !s.fingers.isEmpty:
                    s.up(s.fingers.keys.randomElement(using: &rng)!)
                case 30..<70 where !s.fingers.isEmpty:
                    let ids = Array(s.fingers.keys)
                    let dx = Double.random(in: -15...15, using: &rng), dy = Double.random(in: -15...15, using: &rng)
                    s.move(ids, dx: dx, dy: dy, steps: Int.random(in: 1...6, using: &rng))
                case 70..<85:
                    s.rest(Double.random(in: 0.01...0.6, using: &rng))
                case 85..<90 where !s.fingers.isEmpty:
                    let ids = Array(s.fingers.keys)
                    s.send(Dictionary(uniqueKeysWithValues: ids.map { ($0, TouchPhase.cancelled) }), removing: Set(ids))
                case 90..<93:
                    s.fingers = [:]
                    s.wait(Double.random(in: 0.1...1.0, using: &rng))   // link goes silent
                case 93..<95:
                    s.events += s.r.cancelAll()
                    s.fingers = [:]
                default:
                    s.wait(0.05)
                }
                if s.fingers.isEmpty && s.r.fingerCount == 0 {
                    #expect(!s.r.isLeftButtonDown, "round \(round)")
                }
            }
            s.fingers.keys.sorted().forEach { s.up($0) }
            s.wait(8)       // momentum coasts with a 0.5 s time constant
            #expect(!s.r.isLeftButtonDown)
            #expect(!s.r.needsTick, "round \(round)")
            // Button events must alternate down/up per button and end released.
            var down: [MouseButton: Bool] = [:]
            for e in s.events {
                guard case .button(let b, let isDown, _) = e else { continue }
                #expect(down[b, default: false] != isDown, "round \(round): repeated \(b) \(isDown)")
                down[b] = isDown
            }
            #expect(down.values.allSatisfy { !$0 })
            // Scroll gestures start before they change and momentum starts before it ends.
            var scrolling = false
            for sc in s.scrolls where sc.momentum == .none {
                switch sc.phase {
                case .began: scrolling = true
                case .changed: #expect(scrolling, "round \(round): changed without began")
                case .ended, .cancelled: #expect(scrolling); scrolling = false
                case .none: break
                }
            }
            #expect(!scrolling)
        }
    }
}

/// Deterministic generator so the fuzz test is reproducible.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
