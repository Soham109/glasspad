import Foundation
import CoreGraphics

/// Turns touch frames into trackpad gestures.
///
/// Runs on the Mac (source of truth for events) and on the phone (only for instant haptics).
///
/// Timing: all internal timing uses the frame clock (`TouchFrame.timestamp`). `tick(now:)` and
/// `process(_:receivedAt:)` take the caller's local clock (`clock`, default `systemUptime`); the
/// recognizer learns the offset between the two clocks from frame arrivals, so the Mac can pass
/// its own uptime even though frames carry the phone's.
///
/// Invariant: whenever no finger is down, the left button is up. Lifts, cancels, stale links
/// (`staleTouchTimeout`) and `cancelAll()` all release it.
public final class GestureRecognizer {
    public var settings: TrackpadSettings
    /// Fired for clicks (tap, two-finger click, corner click, three-finger Look Up tap), force
    /// click stages and drag lock (a tap-drag picking something up). Nothing else buzzes: no
    /// Spaces, Mission Control, swipes, scroll, page swipes or edge swipes.
    public var onHaptic: ((HapticKind) -> Void)?
    /// Width of the main display in Mac points. Kept for callers; pointer gain follows the Mac's
    /// acceleration curve in physical units and does not depend on it.
    public var displayWidth: Double = GestureTuning.defaultDisplayWidth
    /// Phone screen points per inch (`GestureTuning.phonePointsPerInch` for iPhone Pro screens).
    public var phonePointsPerInch: Double = GestureTuning.phonePointsPerInch
    /// With fingers down and no frame for this long, cancel everything. Set nil on the phone,
    /// where UIKit sends no frames for resting fingers.
    public var staleTouchTimeout: TimeInterval? = GestureTuning.staleTouchTimeout
    /// The caller's local clock, used by `process(_:)` to stamp arrivals.
    public var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    /// True while `tick(now:)` has work: fingers down, momentum, or a pending click. Call it about
    /// every 8 ms while true.
    public var needsTick: Bool { !touches.isEmpty || momentum != nil || pendingTwoTap != nil }
    /// True while the recognizer holds the left button down.
    public private(set) var isLeftButtonDown = false
    /// Number of fingers currently tracked.
    public var fingerCount: Int { touches.count }

    public init(settings: TrackpadSettings) {
        self.settings = settings
    }

    // MARK: Types

    typealias V = SIMD2<Double>

    struct Tracked {
        var origin: V      // where the finger landed
        var start: V       // rebased whenever the sub-gesture restarts
        var prev: V
        var cur: V
        var downTime: TimeInterval
    }

    struct Session {
        var startTime: TimeInterval
        var maxFingers: Int
        var maxDisplacement: Double = 0
        var tapCandidate = true
        var tapDragArmed: Bool
        var firstOrigin: V
        var startedAtRightEdge = false
    }

    enum DragSource { case tapDrag, hold, threeFinger }

    enum SwipeMetric {
        case x(Double), y(Double), spread(Double)
    }

    enum State {
        case idle
        case possible
        case pointing
        case dragging(DragSource)
        case holding(stage: Int, since: TimeInterval)
        case scrolling
        case scrollLifting(since: TimeInterval)
        case pinchRotate
        case swiping(SwipeKind, SwipeMetric)
        case pageSwipe(fired: Bool)
        case consumed
    }

    struct Momentum {
        var v: V
        var last: TimeInterval
        var began: Bool
    }

    // MARK: State

    private var touches: [UInt8: Tracked] = [:]
    private var state: State = .idle
    private var session: Session?
    private var surface = CGSize(width: 390, height: 844)
    private var lastFrameTime: TimeInterval?
    private var clockOffset: Double?
    private var clockOffsetSetAt: TimeInterval = 0
    /// Finger speed in phone points per second over the last `speedWindow`.
    private var fingerSpeed: Double = 0
    private var curves: (tracking: Double, scroll: Double, pointer: ParametricAcceleration, scroll2: ParametricAcceleration)?

    private var scrollSamples: [(t: TimeInterval, d: V)] = []
    private var scrollStartTime: TimeInterval = 0
    private var liftVelocity: V = .zero
    private var momentum: Momentum?

    private var pinchActive = false
    private var rotateActive = false
    private var baseDistance: Double = 1
    private var baseAngle: Double = 0
    private var lastDistance: Double = 1
    private var lastAngle: Double = 0

    private var swipeProgress: Double = 0
    private var pageTravel: Double = 0

    private var lastClick: (t: TimeInterval, p: V, count: Int)?
    private var lastTapEnd: (t: TimeInterval, p: V)?
    private var pendingTwoTap: (t: TimeInterval, fireRight: Bool)?
    private var leftClickCount = 1

    // MARK: Public entry points

    public func process(_ frame: TouchFrame) -> [GestureEvent] {
        process(frame, receivedAt: clock())
    }

    /// Feeds one frame. `receivedAt` is the caller's local clock at arrival.
    public func process(_ frame: TouchFrame, receivedAt local: TimeInterval) -> [GestureEvent] {
        var ev: [GestureEvent] = []
        let t = frame.timestamp
        if let lt = lastFrameTime, t < lt {
            if lt - t > GestureTuning.clockJumpTolerance {
                ev += cancelAll()        // the phone's clock restarted
            } else {
                return []                // late, reordered packet: drop
            }
        }
        updateOffset(frameTime: t, local: local)
        ev += checkTimers(at: t)
        let dt = lastFrameTime.map { t - $0 } ?? 0
        lastFrameTime = t
        if frame.surface.width > 0, frame.surface.height > 0 { surface = frame.surface }

        if frame.touches.contains(where: { $0.phase == .cancelled }) {
            ev += cancelSession()
            touches = [:]
            for tch in frame.touches where tch.phase.isActive {
                let p = V(tch.x, tch.y)
                touches[tch.id] = Tracked(origin: p, start: p, prev: p, cur: p, downTime: t)
            }
            if !touches.isEmpty {
                session = Session(startTime: t, maxFingers: touches.count, tapCandidate: false,
                                  tapDragArmed: false, firstOrigin: .zero)
                state = .consumed
            }
            return ev + enforceInvariant()
        }

        // Stage 1: motion of fingers we already track (including their final position on lift).
        for id in touches.keys { touches[id]!.prev = touches[id]!.cur }
        var sum = V.zero
        var moved = 0
        for tch in frame.touches {
            guard var tr = touches[tch.id] else { continue }
            tr.cur = V(tch.x, tch.y)
            sum += tr.cur - tr.prev
            moved += 1
            touches[tch.id] = tr
            if session != nil {
                session!.maxDisplacement = max(session!.maxDisplacement, length(tr.cur - tr.origin))
            }
        }
        if moved > 0 {
            let d = sum / Double(moved)
            updateSpeed(d, t: t, dt: dt)
            ev += handleMotion(d, t: t)
        }

        // Stage 2: lifts (ended, or missing from the snapshot).
        let present = Set(frame.touches.filter { $0.phase.isActive }.map(\.id))
        let lifted = touches.keys.filter { !present.contains($0) }
        if !lifted.isEmpty {
            for id in lifted { touches.removeValue(forKey: id) }
            ev += handleLift(t: t)
        }

        // Stage 3: new fingers.
        let added = frame.touches.filter { $0.phase.isActive && touches[$0.id] == nil }
        if !added.isEmpty {
            ev += stopMomentum()
            let wasEmpty = touches.isEmpty
            for tch in added {
                let p = V(tch.x, tch.y)
                touches[tch.id] = Tracked(origin: p, start: p, prev: p, cur: p, downTime: t)
            }
            ev += handleAdd(wasEmpty: wasEmpty, firstOrigin: V(added[0].x, added[0].y), t: t)
        }
        ev += checkTimers(at: t)
        return ev + enforceInvariant()
    }

    /// Drives momentum, hold timers, deferred clicks and the stale-link guard.
    /// `now` is the caller's local clock (same as `clock`).
    public func tick(now: TimeInterval) -> [GestureEvent] {
        guard let offset = clockOffset else { return [] }
        let t = now - offset
        var ev = checkTimers(at: t)
        if !touches.isEmpty, let lt = lastFrameTime, let limit = staleTouchTimeout, t - lt > limit {
            ev += cancelSession()
            touches = [:]
        }
        ev += momentumStep(at: t)
        return ev + enforceInvariant()
    }

    /// Cancels everything in flight (call on disconnect): releases buttons, cancels scroll,
    /// pinch and swipes, stops momentum, forgets fingers and the clock mapping.
    public func cancelAll() -> [GestureEvent] {
        var ev = cancelSession()
        ev += stopMomentum()
        touches = [:]
        pendingTwoTap = nil
        lastFrameTime = nil
        clockOffset = nil
        return ev + enforceInvariant()
    }

    // MARK: Clock

    /// Learns `local - frameTime` as the smallest delay seen (the fastest packet). The estimate
    /// may also creep up slowly (`clockOffsetCreep`), so clocks drifting apart over a long
    /// session never leave it stale.
    private func updateOffset(frameTime t: TimeInterval, local: TimeInterval) {
        let o = local - t
        if let cur = clockOffset {
            let allowed = cur + max(local - clockOffsetSetAt, 0) * GestureTuning.clockOffsetCreep
            if o < allowed || o - cur > GestureTuning.clockJumpTolerance {
                clockOffset = o
                clockOffsetSetAt = local
            } else {
                clockOffset = allowed
                clockOffsetSetAt = local
            }
        } else {
            clockOffset = o
            clockOffsetSetAt = local
        }
    }

    /// The learned phone-to-local clock offset (`local - frameTime` of the fastest frame), nil
    /// before the first frame. The Mac's output scheduler uses it too.
    public var learnedClockOffset: Double? { clockOffset }

    // MARK: Motion

    private func handleMotion(_ d: V, t: TimeInterval) -> [GestureEvent] {
        switch state {
        case .idle, .consumed, .scrollLifting:
            return []
        case .possible:
            return classify(t: t)
        case .pointing:
            return [.move(dx: accel(d).x, dy: accel(d).y)]
        case .dragging:
            let a = accel(d)
            return [.drag(dx: a.x, dy: a.y)]
        case .holding:
            let moved = touches.values.contains { length($0.cur - $0.start) > GestureTuning.dragStartSlop }
            guard moved else { return [] }
            state = .dragging(.hold)
            let a = accel(translation())
            return [.drag(dx: a.x, dy: a.y)]
        case .scrolling:
            let s = scrollVector(d)
            scrollSamples.append((t, s))
            scrollSamples.removeAll { $0.t < t - 0.5 }
            return [.scroll(dx: s.x, dy: s.y, phase: .changed, momentum: .none)]
        case .pinchRotate:
            return pinchRotateStep()
        case .swiping(let kind, let metric):
            let step = swipeStep(metric, d: d)
            guard step != 0 else { return [] }
            swipeProgress += step
            return [.swipe(kind, progress: swipeProgress, phase: .changed)]
        case .pageSwipe(let fired):
            pageTravel += d.x
            return fired ? [] : maybeNavigate()
        }
    }

    private func classify(t: TimeInterval) -> [GestureEvent] {
        let n = touches.count
        let T = translation()
        if n == 1 {
            guard length(T) > GestureTuning.pointerStartSlop else { return [] }
            if session?.tapDragArmed == true {
                setNotTap()
                state = .dragging(.tapDrag)
                haptic(.dragLock)
                var ev = pressLeft(1)
                let a = accel(T)
                ev.append(.drag(dx: a.x, dy: a.y))
                return ev
            }
            state = .pointing
            let a = accel(T)
            return [.move(dx: a.x, dy: a.y)]
        }
        if n == 2 { return classifyTwo(T: T, t: t) }
        if n == 3 && settings.threeFingerDrag {
            guard length(T) > GestureTuning.dragStartSlop else { return [] }
            setNotTap()
            state = .dragging(.threeFinger)
            var ev = pressLeft(1)
            let a = accel(T)
            ev.append(.drag(dx: a.x, dy: a.y))
            return ev
        }
        return classifySwipe(n: n, T: T)
    }

    private func classifyTwo(T: V, t: TimeInterval) -> [GestureEvent] {
        let (p0, p1) = twoStarts()
        let (c0, c1) = twoCurrent()
        let d0 = max(length(p1 - p0), 1), d = max(length(c1 - c0), 1)
        let a0 = atan2(p1.y - p0.y, p1.x - p0.x), a = atan2(c1.y - c0.y, c1.x - c0.x)
        let D = d - d0
        let arc = abs(angleDelta(a, a0)) * d / 2
        let tl = length(T)

        if settings.notificationCenterEdge, session?.startedAtRightEdge == true, -T.x > abs(T.y) {
            if -T.x >= GestureTuning.notificationCenterDistance {
                setNotTap()
                state = .consumed
                return [.notificationCenter]
            }
            if abs(D) < GestureTuning.pinchStartDistance { return [] }   // wait: may still be the edge swipe
        }
        if abs(D) >= GestureTuning.pinchStartDistance, abs(D) >= tl, settings.pinchToZoom || settings.rotate {
            return beginPinch(d0: d0, a0: a0)
        }
        if arc >= GestureTuning.rotateStartArc, arc >= tl, settings.rotate {
            return beginPinch(d0: d0, a0: a0)
        }
        if tl >= GestureTuning.scrollStartDistance {
            setNotTap()
            state = .scrolling
            scrollStartTime = t
            let s = scrollVector(T)
            scrollSamples = [(t, s)]
            return [.scroll(dx: s.x, dy: s.y, phase: .began, momentum: .none)]
        }
        return []
    }

    private func beginPinch(d0: Double, a0: Double) -> [GestureEvent] {
        setNotTap()
        state = .pinchRotate
        pinchActive = false
        rotateActive = false
        baseDistance = d0
        baseAngle = a0
        lastDistance = d0
        lastAngle = a0
        return pinchRotateStep()
    }

    private func pinchRotateStep() -> [GestureEvent] {
        guard touches.count == 2 else { return [] }
        let (c0, c1) = twoCurrent()
        let d = max(length(c1 - c0), 1)
        let a = atan2(c1.y - c0.y, c1.x - c0.x)
        var ev: [GestureEvent] = []
        if settings.pinchToZoom {
            if !pinchActive {
                if abs(d - baseDistance) >= GestureTuning.pinchStartDistance {
                    pinchActive = true
                    ev.append(.magnify(delta: d / baseDistance - 1, phase: .began))
                }
            } else if d != lastDistance {
                ev.append(.magnify(delta: d / lastDistance - 1, phase: .changed))
            }
        }
        if settings.rotate {
            if !rotateActive {
                let total = angleDelta(a, baseAngle)
                if abs(total) * d / 2 >= GestureTuning.rotateStartArc {
                    rotateActive = true
                    ev.append(.rotate(degrees: -total * 180 / .pi, phase: .began))
                }
            } else {
                let step = angleDelta(a, lastAngle)
                if step != 0 { ev.append(.rotate(degrees: -step * 180 / .pi, phase: .changed)) }
            }
        }
        lastDistance = d
        lastAngle = a
        return ev
    }

    private func endPinch(cancelled: Bool) -> [GestureEvent] {
        var ev: [GestureEvent] = []
        let phase: GesturePhase = cancelled ? .cancelled : .ended
        if pinchActive { ev.append(.magnify(delta: 0, phase: phase)) }
        if rotateActive { ev.append(.rotate(degrees: 0, phase: phase)) }
        pinchActive = false
        rotateActive = false
        return ev
    }

    private func classifySwipe(n: Int, T: V) -> [GestureEvent] {
        let R = spread(of: \.cur) - spread(of: \.start)
        let tl = length(T)
        if n >= GestureTuning.spreadMinFingers, abs(R) >= GestureTuning.spreadStartDistance, abs(R) > tl {
            setNotTap()
            let full = GestureTuning.spreadFullDistance
            if R < 0, settings.launchpadPinch { return beginSwipe(.launchpad, .spread(-1 / full), initial: -R / full) }
            if R > 0, settings.showDesktopSpread { return beginSwipe(.showDesktop, .spread(1 / full), initial: R / full) }
            state = .consumed
            return []
        }
        guard tl >= GestureTuning.axisLockDistance else { return [] }
        setNotTap()
        let full = GestureTuning.swipeFullDistance
        if abs(T.x) >= abs(T.y) {
            if settings.swipeBetweenSpaces.matches(n) {
                return beginSwipe(.spaces, .x(-1 / full), initial: -T.x / full)
            }
            let pages = settings.swipeBetweenPages
            if n == 3, pages == .threeFinger || pages == .twoOrThree {
                state = .pageSwipe(fired: false)
                pageTravel = T.x
                return maybeNavigate()
            }
        } else {
            let up = T.y < 0
            let mc = settings.missionControl.matches(n), ax = settings.appExpose.matches(n)
            if up && mc || !up && !ax && mc {
                return beginSwipe(.missionControl, .y(-1 / full), initial: -T.y / full)
            }
            if ax {
                return beginSwipe(.appExpose, .y(1 / full), initial: T.y / full)
            }
        }
        state = .consumed
        return []
    }

    private func beginSwipe(_ kind: SwipeKind, _ metric: SwipeMetric, initial: Double) -> [GestureEvent] {
        state = .swiping(kind, metric)
        swipeProgress = initial
        return [.swipe(kind, progress: initial, phase: .began)]
    }

    private func swipeStep(_ metric: SwipeMetric, d: V) -> Double {
        switch metric {
        case .x(let k): return d.x * k
        case .y(let k): return d.y * k
        case .spread(let k): return (spread(of: \.cur) - spread(of: \.prev)) * k
        }
    }

    private func endSwipe(_ kind: SwipeKind, cancelled: Bool) -> [GestureEvent] {
        return [.swipe(kind, progress: swipeProgress, phase: cancelled ? .cancelled : .ended)]
    }

    private func maybeNavigate() -> [GestureEvent] {
        guard abs(pageTravel) >= GestureTuning.navigateDistance else { return [] }
        state = .pageSwipe(fired: true)
        return [.navigate(back: pageTravel > 0)]
    }

    // MARK: Lifts and additions

    private func handleLift(t: TimeInterval) -> [GestureEvent] {
        let r = touches.count
        var ev: [GestureEvent] = []
        switch state {
        case .idle:
            break
        case .possible:
            if r > 0, (session?.maxFingers ?? 0) >= 2 { state = .consumed }
        case .pointing, .consumed, .pageSwipe:
            break
        case .dragging(let src):
            if src == .threeFinger && r < 3 {
                ev += releaseLeft()
                state = .consumed
            }
        case .holding:
            break
        case .scrolling:
            liftVelocity = releaseVelocity(at: t)
            if r > 0 { state = .scrollLifting(since: t) } else { ev += endScroll(momentum: true, t: t) }
        case .scrollLifting:
            if r == 0 { ev += endScroll(momentum: true, t: t) }
        case .pinchRotate:
            ev += endPinch(cancelled: false)
            state = .consumed
        case .swiping(let kind, _):
            if r == 0 { ev += endSwipe(kind, cancelled: false) }
        }
        if r == 0 {
            ev += releaseLeft()
            ev += evaluateTap(t: t)
            session = nil
            state = .idle
        }
        return ev
    }

    private func handleAdd(wasEmpty: Bool, firstOrigin: V, t: TimeInterval) -> [GestureEvent] {
        let n = touches.count
        if wasEmpty {
            var armed = false
            if n == 1, let tap = lastTapEnd, t - tap.t <= GestureTuning.tapDragWindow,
               length(firstOrigin - tap.p) <= GestureTuning.tapDragRadius {
                armed = true
            }
            session = Session(startTime: t, maxFingers: n, tapDragArmed: armed, firstOrigin: firstOrigin)
            fingerSpeed = 0
            state = .possible
            rebase()
            return []
        }
        if let m = session?.maxFingers { session?.maxFingers = max(m, n) }
        var ev: [GestureEvent] = []
        switch state {
        case .possible, .pointing:
            session?.tapDragArmed = false
            state = .possible
            rebase()
        case .scrolling, .scrollLifting:
            ev.append(.scroll(dx: 0, dy: 0, phase: .ended, momentum: .none))
            state = .possible
            rebase()
        case .pinchRotate:
            ev += endPinch(cancelled: false)
            state = .possible
            rebase()
        case .consumed:
            setNotTap()
            state = .possible
            rebase()
        case .idle:
            state = .possible
            rebase()
        case .dragging, .holding, .swiping, .pageSwipe:
            break   // keep going; averaged deltas absorb the new finger
        }
        return ev
    }

    private func rebase() {
        for id in touches.keys { touches[id]!.start = touches[id]!.cur }
        if touches.count == 2, case .possible = state {
            let c = centroid(of: \.cur)
            session?.startedAtRightEdge = c.x >= Double(surface.width) - GestureTuning.rightEdgeZone
        }
    }

    // MARK: Taps

    private func evaluateTap(t: TimeInterval) -> [GestureEvent] {
        guard let s = session, s.tapCandidate,
              t - s.startTime <= GestureTuning.tapMaxDuration,
              s.maxDisplacement <= GestureTuning.tapSlop
        else { return flushPendingTwoTap() }
        switch s.maxFingers {
        case 1:
            var ev = flushPendingTwoTap()
            if inSecondaryCorner(s.firstOrigin) {
                ev += [.button(.right, down: true, clickCount: 1), .button(.right, down: false, clickCount: 1)]
                haptic(.click)
                return ev
            }
            var count = 1
            if let last = lastClick, t - last.t <= GestureTuning.doubleClickInterval,
               length(s.firstOrigin - last.p) <= GestureTuning.doubleClickRadius {
                count = min(last.count + 1, GestureTuning.maxClickCount)
            }
            lastClick = (t, s.firstOrigin, count)
            lastTapEnd = (t, s.firstOrigin)
            haptic(.click)
            return ev + [.button(.left, down: true, clickCount: count), .button(.left, down: false, clickCount: count)]
        case 2:
            if let pend = pendingTwoTap, s.startTime - pend.t <= GestureTuning.smartZoomGap {
                pendingTwoTap = nil
                return settings.smartZoom ? [.smartMagnify] : []
            }
            var ev = flushPendingTwoTap()
            if settings.smartZoom {
                pendingTwoTap = (t, settings.secondaryClick == .twoFinger)
            } else if settings.secondaryClick == .twoFinger {
                haptic(.click)
                ev += [.button(.right, down: true, clickCount: 1), .button(.right, down: false, clickCount: 1)]
            }
            return ev
        case 3:
            let ev = flushPendingTwoTap()
            if settings.lookUp == .threeFingerTap {
                haptic(.click)
                return ev + [.lookUp]
            }
            return ev
        default:
            return flushPendingTwoTap()
        }
    }

    private func inSecondaryCorner(_ p: V) -> Bool {
        let w = Double(surface.width), h = Double(surface.height)
        guard p.y >= h * (1 - GestureTuning.cornerHeightFraction) else { return false }
        switch settings.secondaryClick {
        case .bottomRight: return p.x >= w * (1 - GestureTuning.cornerWidthFraction)
        case .bottomLeft: return p.x <= w * GestureTuning.cornerWidthFraction
        case .twoFinger, .off: return false
        }
    }

    private func flushPendingTwoTap() -> [GestureEvent] {
        guard let pend = pendingTwoTap else { return [] }
        pendingTwoTap = nil
        guard pend.fireRight else { return [] }
        haptic(.click)
        return [.button(.right, down: true, clickCount: 1), .button(.right, down: false, clickCount: 1)]
    }

    private var pendingFlushQueue: [GestureEvent] = []

    private func setNotTap() {
        session?.tapCandidate = false
        session?.tapDragArmed = false
        pendingFlushQueue += flushPendingTwoTap()
    }

    // MARK: Timers

    private func checkTimers(at t: TimeInterval) -> [GestureEvent] {
        var ev: [GestureEvent] = []
        if let pend = pendingTwoTap {
            if let s = session {
                if s.startTime - pend.t > GestureTuning.smartZoomGap || s.maxFingers > 2
                    || t - s.startTime > GestureTuning.tapMaxDuration {
                    ev += flushPendingTwoTap()
                }
            } else if t - pend.t > GestureTuning.smartZoomGap {
                ev += flushPendingTwoTap()
            }
        }
        switch state {
        case .possible:
            if touches.count == 1, let s = session, s.maxFingers == 1, let tr = touches.values.first,
               length(tr.cur - tr.origin) <= GestureTuning.holdSlop,
               t - tr.downTime >= GestureTuning.forceClickStage1Delay {
                setNotTap()
                ev += pressLeft(1)
                ev.append(.forceClick(stage: 1))
                haptic(.click)
                state = .holding(stage: 1, since: t)
                rebase()
            }
        case .holding(let stage, let since):
            if stage == 1, t - since >= GestureTuning.forceClickStage2Delay {
                ev.append(.forceClick(stage: 2))
                haptic(.forceClick)
                state = .holding(stage: 2, since: since)
            }
        case .scrollLifting(let since):
            if t - since > GestureTuning.scrollLiftGrace {
                ev += endScroll(momentum: false, t: t)
                state = .consumed
            }
        default:
            break
        }
        return ev
    }

    // MARK: Scroll and momentum

    /// Phone points of two-finger travel to scroll pixels: the Mac's scroll curve for its
    /// scrolling speed, at the current finger speed, times the phone's scroll speed setting.
    private func scrollVector(_ d: V) -> V {
        d * scrollGain() * (settings.naturalScrolling ? 1 : -1)
    }

    /// Scroll pixels per phone point at the current finger speed.
    func scrollGain() -> Double {
        let inchesPerSecond = fingerSpeed / max(phonePointsPerInch, 1)
        let perInch = MacAcceleration.gain(inchesPerSecond: inchesPerSecond, curve: currentCurves().scroll)
        let tuning = settings.tuning.clamped
        return perInch * GestureTuning.scrollCalibration * tuning.scrollSpeed / max(phonePointsPerInch, 1)
    }

    private func releaseVelocity(at t: TimeInterval) -> V {
        let window = GestureTuning.momentumSampleWindow
        let recent = scrollSamples.filter { $0.t > t - window && $0.t <= t }
        guard let lastMoving = recent.last(where: { length($0.d) > 0.01 }),
              t - lastMoving.t <= GestureTuning.momentumStillCutoff else { return .zero }
        let span = max(min(window, t - scrollStartTime), 0.016)
        return recent.reduce(V.zero) { $0 + $1.d } / span
    }

    private func endScroll(momentum withMomentum: Bool, t: TimeInterval) -> [GestureEvent] {
        let ev: [GestureEvent] = [.scroll(dx: 0, dy: 0, phase: .ended, momentum: .none)]
        scrollSamples = []
        if withMomentum, settings.scrollMomentum, settings.tuning.clamped.momentumStrength > 0.01,
           length(liftVelocity) >= GestureTuning.momentumMinSpeed {
            momentum = Momentum(v: liftVelocity, last: t, began: false)
        }
        return ev
    }

    private func momentumStep(at t: TimeInterval) -> [GestureEvent] {
        guard var m = momentum else { return [] }
        let dt = min(t - m.last, GestureTuning.momentumMaxStep)
        guard dt > 0 else { return [] }
        let k = Self.momentumRate(strength: settings.tuning.clamped.momentumStrength)
        let decay = exp(-k * dt)
        let disp = m.v * ((1 - decay) / k)
        m.v *= decay
        m.last = t
        var ev: [GestureEvent] = [.scroll(dx: disp.x, dy: disp.y, phase: .none, momentum: m.began ? .changed : .began)]
        m.began = true
        if length(m.v) < GestureTuning.momentumStopSpeed {
            ev.append(.scroll(dx: 0, dy: 0, phase: .none, momentum: .ended))
            momentum = nil
        } else {
            momentum = m
        }
        return ev
    }

    /// Exponential momentum decay rate (1/s) for a momentum strength (1 = the platform's).
    static func momentumRate(strength: Double) -> Double {
        let perMs = pow(GestureTuning.momentumDecayPerMillisecond, 1 / max(strength, 0.01))
        return -log(perMs) * 1000
    }

    private func stopMomentum() -> [GestureEvent] {
        guard let m = momentum else { return [] }
        momentum = nil
        return m.began ? [.scroll(dx: 0, dy: 0, phase: .none, momentum: .ended)] : []
    }

    // MARK: Cancel and safety

    private func cancelSession() -> [GestureEvent] {
        var ev = pendingFlushQueue
        pendingFlushQueue = []
        switch state {
        case .scrolling, .scrollLifting:
            ev.append(.scroll(dx: 0, dy: 0, phase: .cancelled, momentum: .none))
            scrollSamples = []
        case .pinchRotate:
            ev += endPinch(cancelled: true)
        case .swiping(let kind, _):
            ev += endSwipe(kind, cancelled: true)
        default:
            break
        }
        ev += releaseLeft()
        session = nil
        state = .idle
        pendingTwoTap = nil
        return ev
    }

    /// Appends deferred events and guarantees no button outlives the fingers.
    private func enforceInvariant() -> [GestureEvent] {
        var ev = pendingFlushQueue
        pendingFlushQueue = []
        if touches.isEmpty {
            ev += releaseLeft()
            if case .idle = state {} else { state = .idle; session = nil }
        }
        return ev
    }

    private func pressLeft(_ count: Int) -> [GestureEvent] {
        guard !isLeftButtonDown else { return [] }
        isLeftButtonDown = true
        leftClickCount = count
        return [.button(.left, down: true, clickCount: count)]
    }

    private func releaseLeft() -> [GestureEvent] {
        guard isLeftButtonDown else { return [] }
        isLeftButtonDown = false
        return [.button(.left, down: false, clickCount: leftClickCount)]
    }

    private func haptic(_ k: HapticKind) { onHaptic?(k) }

    // MARK: Pointer acceleration

    /// Finger speed the way the Mac's HID system measures it per trackpad report: this frame's
    /// travel over its time step, with the step never shorter than one report period
    /// (`speedWindow`, 1/120 s). The phone sends one frame per touch callback (120 Hz), so this
    /// matches what the real trackpad's 120 Hz reports give the curve.
    private func updateSpeed(_ d: V, t: TimeInterval, dt: TimeInterval) {
        let step = min(max(dt, GestureTuning.speedWindow), GestureTuning.maxFrameInterval)
        fingerSpeed = length(d) / step
    }

    private func currentCurves() -> (pointer: ParametricAcceleration, scroll: ParametricAcceleration) {
        let tracking = min(max(settings.trackingSpeed, 0), 3), scroll = min(max(settings.scrollSpeed, 0), 3)
        if let c = curves, c.tracking == tracking, c.scroll == scroll { return (c.pointer, c.scroll2) }
        let p = MacAcceleration.pointerCurve(trackingSpeed: tracking), sc = MacAcceleration.scrollCurve(scrollSpeed: scroll)
        curves = (tracking, scroll, p, sc)
        return (p, sc)
    }

    /// Mac points per phone point at a finger speed (phone points per second), for the current
    /// settings: the Mac's trackpad curve in physical units, then the phone's pointer speed.
    func pointerGain(speed: Double) -> Double {
        Self.pointerGain(speed: speed, tuning: settings.tuning, curve: currentCurves().pointer,
                         phonePointsPerInch: phonePointsPerInch)
    }

    /// Mac points per phone point at a finger speed (phone points per second): the Mac's
    /// trackpad curve for `settings.trackingSpeed` in physical units, then the phone's tuning.
    /// Public so the phone's settings preview can show the exact same mapping.
    public static func pointerGain(speed: Double, settings: TrackpadSettings,
                                   phonePointsPerInch: Double = GestureTuning.phonePointsPerInch) -> Double {
        pointerGain(speed: speed, tuning: settings.tuning, curve: MacAcceleration.pointerCurve(trackingSpeed: settings.trackingSpeed),
                    phonePointsPerInch: phonePointsPerInch)
    }

    static func pointerGain(speed: Double, tuning raw: TrackpadTuning, curve: ParametricAcceleration,
                            phonePointsPerInch: Double) -> Double {
        let ppi = max(phonePointsPerInch, 1)
        let tuning = raw.clamped
        let perInch: Double
        switch tuning.acceleration {
        case .mac: perInch = MacAcceleration.gain(inchesPerSecond: speed / ppi, curve: curve)
        case .linear: perInch = MacAcceleration.gain(inchesPerSecond: GestureTuning.linearReferenceSpeed, curve: curve)
        case .off: perInch = MacAcceleration.screenResolution
        }
        return perInch * tuning.pointerSpeed / ppi
    }

    /// Phone points to accelerated Mac points at the current finger speed.
    private func accel(_ d: V) -> V {
        d * pointerGain(speed: fingerSpeed)
    }

    // MARK: Geometry

    private func length(_ v: V) -> Double { (v * v).sum().squareRoot() }

    private func translation() -> V {
        guard !touches.isEmpty else { return .zero }
        return touches.values.reduce(V.zero) { $0 + ($1.cur - $1.start) } / Double(touches.count)
    }

    private func centroid(of kp: KeyPath<Tracked, V>) -> V {
        guard !touches.isEmpty else { return .zero }
        return touches.values.reduce(V.zero) { $0 + $1[keyPath: kp] } / Double(touches.count)
    }

    private func spread(of kp: KeyPath<Tracked, V>) -> Double {
        guard !touches.isEmpty else { return 0 }
        let c = centroid(of: kp)
        return touches.values.reduce(0) { $0 + length($1[keyPath: kp] - c) } / Double(touches.count)
    }

    private func sortedTwo() -> (Tracked, Tracked) {
        let s = touches.sorted { $0.key < $1.key }.map(\.value)
        return (s[0], s[1])
    }

    private func twoStarts() -> (V, V) { let (a, b) = sortedTwo(); return (a.start, b.start) }
    private func twoCurrent() -> (V, V) { let (a, b) = sortedTwo(); return (a.cur, b.cur) }

    private func angleDelta(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d > .pi { d -= 2 * .pi }
        while d <= -.pi { d += 2 * .pi }
        return d
    }
}
