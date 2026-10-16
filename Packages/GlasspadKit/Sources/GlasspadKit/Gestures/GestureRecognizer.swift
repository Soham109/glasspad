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
/// (`staleTouchTimeout`, or `staleDragTimeout` while the button is held) and `cancelAll()` all
/// release it.
///
/// Wi-Fi stalls: with the button down, a silent link freezes the drag (button held, no motion)
/// and the same fingers pick it up again when their frames return. Without the button, the
/// session is cancelled after `staleTouchTimeout`; fingers that come back afterwards (same IDs,
/// not a fresh touch-down) are re-adopted as pointing fingers that can never end as a tap.
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
    /// With the left button held, how long a silent link may freeze the drag before it is
    /// released anyway (see `GestureTuning.staleDragTimeout`). Never shorter than
    /// `staleTouchTimeout`.
    public var staleDragTimeout: TimeInterval = GestureTuning.staleDragTimeout
    /// True while a drag is frozen by a silent link (button held, waiting for frames).
    public private(set) var isStalled = false
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
        /// Contact radius samples over the last `contactRadiusWindow`.
        var radii: [(t: TimeInterval, r: Double)] = []
        /// Rest detection: the finger has stayed within `restRadiusMillimetres` of `restRef`
        /// since `restRefTime`.
        var restRef: V
        var restRefTime: TimeInterval
        /// Set when this frame finds the finger resting (still for `restArmTime`): the rest position.
        var restingAt: V?

        init(at p: V, t: TimeInterval) {
            origin = p; start = p; prev = p; cur = p; downTime = t
            restRef = p; restRefTime = t
        }

        /// True when the contact radius has dropped well below its recent peak: the pad is
        /// rolling onto its tip, which is what a finger does in the last tens of ms before lift.
        var contactShrinking: Bool {
            guard let r = radii.last?.r, r > 0, let peak = radii.map(\.r).max(), peak > 0 else { return false }
            return peak - r >= max(peak * GestureTuning.liftRadiusDropFraction,
                                   GestureTuning.points(mm: GestureTuning.liftRadiusMinDropMillimetres))
        }
    }

    /// Pointer motion held back instead of posted: at touch-down while the touch can still be a
    /// tap, and while a contact peels off the glass. Released smoothly or discarded on lift.
    struct Hold {
        enum Reason { case touchDown, roll }
        var reason: Reason
        var anchor: V
        var held: V = .zero
        /// Where and when the contact started peeling off, if it has.
        var rollFrom: V?
        var rollSince: TimeInterval = 0
    }

    /// Held motion (Mac points) being fed out over `heldMotionReleaseTime`.
    struct Backlog {
        var total: V
        var released: V = .zero
        var start: TimeInterval
    }

    /// Motion posted since the finger left a rest, taken back if it then lifts at once.
    struct RestRetract {
        var anchor: V
        var start: TimeInterval
        var emitted: V = .zero
    }

    struct Session {
        var startTime: TimeInterval
        var maxFingers: Int
        var maxDisplacement: Double = 0
        var tapCandidate = true
        var tapDragArmed: Bool
        var firstOrigin: V
        var startedAtRightEdge = false
        /// Pointer motion (Mac points) posted in this session, taken back if it ends as a tap.
        var emitted: V = .zero
        /// One finger was moving the pointer when more fingers landed: if they lift again
        /// without starting a gesture, the remaining finger goes back to pointing.
        var resumePointing = false
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

    private var hold: Hold?
    private var backlog: Backlog?
    private var restRetract: RestRetract?
    /// One-finger speeds (phone points per second) over the last `rollSpeedWindow`.
    private var speedHistory: [(t: TimeInterval, v: Double)] = []
    /// This frame looks like a lift-off roll: contact shrinking plus a speed spike.
    private var rollSignal = false
    private var lastSpeedSampleTime: TimeInterval?
    /// A roll hold was let go (no lift came): no new one until the contact stops shrinking.
    private var rollSpent = false

    /// Fingers dropped by the stale guard; if they come back on the next frame (not as a
    /// fresh touch-down) they are re-adopted instead of starting a session that could tap.
    private var staleIDs: Set<UInt8> = []

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
                // Late, reordered packet: drop it, except a lift. The client stamps a resent
                // resting snapshot with its send time, so a lift delivered just after one is
                // older than it; dropping that lift lost the tap (or held a drag until the
                // stale guard). Apply only the lift, at the last frame's time.
                let lifts = frame.touches.filter { !$0.phase.isActive && touches[$0.id] != nil }
                guard !lifts.isEmpty else { return [] }
                let lifted = Set(lifts.map(\.id))
                let staying = touches.filter { !lifted.contains($0.key) }.map { id, tr in
                    Touch(id: id, phase: .stationary, x: tr.cur.x, y: tr.cur.y, majorRadius: tr.radii.last?.r ?? 0)
                }
                return process(TouchFrame(seq: frame.seq, timestamp: lt, touches: lifts + staying, surface: frame.surface),
                               receivedAt: local)
            }
        }
        updateOffset(frameTime: t, local: local)
        // Whatever this frame brings, the stall memory is only good for the frame right after it.
        let returningIDs = staleIDs
        staleIDs = []
        if isStalled {
            // Frames are back after a frozen drag. The finger may have moved while nothing got
            // through; that travel is dropped (the pointer stays where it froze) rather than
            // posted as one jump. Motion from here on is live again.
            isStalled = false
            for tch in frame.touches where touches[tch.id] != nil {
                let p = V(tch.x, tch.y)
                touches[tch.id]?.cur = p
                touches[tch.id]?.restRef = p
                touches[tch.id]?.restRefTime = t
            }
            speedHistory = []
            lastSpeedSampleTime = nil
        }
        ev += checkTimers(at: t)
        let dt = lastFrameTime.map { t - $0 } ?? 0
        lastFrameTime = t
        if frame.surface.width > 0, frame.surface.height > 0 { surface = frame.surface }

        if frame.touches.contains(where: { $0.phase == .cancelled }) {
            ev += cancelSession()
            touches = [:]
            for tch in frame.touches where tch.phase.isActive {
                let p = V(tch.x, tch.y)
                touches[tch.id] = Tracked(at: p, t: t)
            }
            if !touches.isEmpty {
                session = Session(startTime: t, maxFingers: touches.count, tapCandidate: false,
                                  tapDragArmed: false, firstOrigin: .zero)
                state = .consumed
            }
            return ev + enforceInvariant()
        }

        // Stage 1: motion of fingers we already track (including their final position on lift).
        for id in touches.keys { touches[id]!.prev = touches[id]!.cur; touches[id]!.restingAt = nil }
        var all: [V] = [], staying: [V] = [], steering: [V] = []
        let restRadius = GestureTuning.points(mm: GestureTuning.restRadiusMillimetres)
        for tch in frame.touches {
            guard var tr = touches[tch.id] else { continue }
            tr.cur = V(tch.x, tch.y)
            let d = tr.cur - tr.prev
            all.append(d)
            if tch.phase.isActive { staying.append(d) }
            if t - tr.restRefTime >= GestureTuning.restArmTime { tr.restingAt = tr.restRef }
            if length(tr.cur - tr.restRef) > restRadius {
                tr.restRef = tr.cur
                tr.restRefTime = t
            }
            if tch.majorRadius > 0 {
                tr.radii.append((t, tch.majorRadius))
                tr.radii.removeAll { $0.t < t - GestureTuning.contactRadiusWindow }
            }
            touches[tch.id] = tr
            // Fingers that may steer the pointer when several are down: not one still landing
            // (inside its own touch-down hold) and not one peeling off.
            let settled = t - tr.downTime > GestureTuning.tapMaxDuration
                || length(tr.cur - tr.origin) > GestureTuning.points(mm: GestureTuning.touchDownHoldMillimetres)
            if tch.phase.isActive, settled, !tr.contactShrinking { steering.append(d) }
            if session != nil {
                session!.maxDisplacement = max(session!.maxDisplacement, length(tr.cur - tr.origin))
            }
        }
        if !all.isEmpty {
            // A finger lifting while others stay contributes nothing: its last position is the
            // pad rolling off, and averaging it in would shift the centroid.
            let use = staying.isEmpty ? all : staying
            let d = use.reduce(V.zero, +) / Double(use.count)
            // Pointer motion with several fingers follows the steering finger that moves most (a
            // resting thumb does not halve it, a landing or lifting finger's noise never moves
            // it), and switching between fingers never jumps: only per-finger deltas are used.
            let pd = use.count == 1 ? use[0] : (steering.max { length($0) < length($1) } ?? .zero)
            updateSpeed(drivesPointer ? pd : d, t: t, dt: dt)
            updateRollSignal(t: t)
            ev += handleMotion(d, pointer: pd, t: t)
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
                var tr = Tracked(at: p, t: t)
                if tch.majorRadius > 0 { tr.radii = [(t, tch.majorRadius)] }
                touches[tch.id] = tr
            }
            // The same fingers the stale guard dropped, still mid-touch (not a touch-down): this
            // is the link coming back, not a new touch, so it must never end as a click.
            let returning = wasEmpty && added.allSatisfy { returningIDs.contains($0.id) && $0.phase != .began }
            if returning {
                ev += readopt(firstOrigin: V(added[0].x, added[0].y), t: t)
            } else {
                ev += handleAdd(wasEmpty: wasEmpty, firstOrigin: V(added[0].x, added[0].y), t: t)
            }
        }
        ev += checkTimers(at: t)
        return ev + enforceInvariant()
    }

    /// Drives momentum, hold timers, deferred clicks and the stale-link guard.
    /// `now` is the caller's local clock (same as `clock`).
    public func tick(now: TimeInterval) -> [GestureEvent] {
        guard let offset = clockOffset else { return [] }
        let t = now - offset
        if !touches.isEmpty, let lt = lastFrameTime, let limit = staleTouchTimeout, t - lt > limit {
            if isLeftButtonDown, t - lt <= max(limit, staleDragTimeout) {
                // Freeze: keep the button down, post nothing, run no timers (a held force click
                // must not advance a stage on fingers we cannot see).
                if !isStalled { GPLog.log("gestures: link silent mid-drag, freezing the drag") }
                isStalled = true
                return enforceInvariant()
            }
            var ev = cancelSession()
            staleIDs = Set(touches.keys)
            touches = [:]
            isStalled = false
            ev += momentumStep(at: t)
            return ev + enforceInvariant()
        }
        var ev = checkTimers(at: t)
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
        isStalled = false
        staleIDs = []
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

    /// The motion stream that would keep going if frames stopped arriving right now, or nil when
    /// nothing may be extrapolated: no fingers, a frozen drag, a tap or roll hold (precision),
    /// held motion still being fed out, a contact peeling off (a lift is coming), a force-click
    /// hold, a pinch, a swipe, or anything after a lift. The Mac's scheduler uses it to carry
    /// the pointer, a drag or a scroll across a Wi-Fi gap.
    public var continuingMotion: MotionStream? {
        guard !touches.isEmpty, !isStalled, hold == nil, backlog == nil, !rollSignal,
              !touches.values.contains(where: \.contactShrinking) else { return nil }
        switch state {
        case .pointing: return .move
        case .dragging: return isLeftButtonDown ? .drag : nil
        case .scrolling: return .scroll
        default: return nil
        }
    }

    // MARK: Motion

    /// True in the states where finger motion moves the pointer.
    private var drivesPointer: Bool {
        switch state {
        case .pointing, .holding: return true
        case .possible: return touches.count == 1
        case .dragging(let src): return src != .threeFinger
        default: return false
        }
    }

    private func handleMotion(_ d: V, pointer pd: V, t: TimeInterval) -> [GestureEvent] {
        switch state {
        case .idle, .consumed, .scrollLifting:
            return []
        case .possible:
            return classify(t: t)
        case .pointing:
            return pointerStep(pd, t: t, drag: false)
        case .dragging(let src):
            if src == .threeFinger {
                let a = accel(d)
                return [.drag(dx: a.x, dy: a.y)]
            }
            return pointerStep(pd, t: t, drag: true)
        case .holding:
            let moved = touches.values.contains { length($0.cur - $0.start) > GestureTuning.dragStartSlop }
            guard moved else { return [] }
            state = .dragging(.hold)
            // The button went down where the finger settled; the travel that started the drag
            // is fed out smoothly instead of in one jump.
            startBacklog(accel(translation()), t: t)
            return pointerStep(.zero, t: t, drag: true)
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
            // Touch-down hysteresis: nothing moves until the finger is clearly travelling.
            guard let tr = touches.values.first else { return [] }
            var h = hold ?? Hold(reason: .touchDown, anchor: tr.origin)
            h.held = tr.cur - h.anchor
            // While a tap is still possible a shrinking contact alone is enough (nothing has
            // been posted yet, so there is no flick to protect).
            if tr.contactShrinking, h.rollFrom == nil { h.rollFrom = tr.prev; h.rollSince = t }
            guard holdReleases(h, cur: tr.cur, t: t, downTime: tr.downTime) else { hold = h; return [] }
            hold = nil
            if h.rollFrom != nil { rollSpent = true }
            rollSignal = false
            startBacklog(accel(h.held), t: t)
            if session?.tapDragArmed == true {
                setNotTap()
                state = .dragging(.tapDrag)
                haptic(.dragLock)
                // The button goes down at the pointer's touch-down position, before any motion.
                return pressLeft(1) + pointerStep(.zero, t: t, drag: true)
            }
            state = .pointing
            return pointerStep(.zero, t: t, drag: false)
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

    // MARK: Pointer precision

    /// One frame of one-finger pointer motion (pointing or a drag): holds motion while the
    /// contact peels off, feeds out held motion, and keeps the records the lift needs.
    /// `d` is phone points of live finger motion.
    private func pointerStep(_ d: V, t: TimeInterval, drag: Bool) -> [GestureEvent] {
        var live = d
        var holding = false
        if touches.count == 1, let tr = touches.values.first {
            // Each frame that finds the finger at rest (re)starts the record of what is posted
            // after it, so a lift right after leaving the rest can take that motion back.
            if let restPos = tr.restingAt {
                if restRetract?.anchor == restPos { restRetract!.start = t } else { restRetract = RestRetract(anchor: restPos, start: t) }
            }
            if hold == nil, rollSignal { hold = Hold(reason: .roll, anchor: tr.prev, rollFrom: tr.prev, rollSince: t) }
            if var h = hold {
                h.held += d
                live = .zero
                if holdReleases(h, cur: tr.cur, t: t, downTime: tr.downTime) {
                    hold = nil
                    rollSpent = true
                    startBacklog(accel(h.held), t: t)
                } else {
                    hold = h
                    holding = true
                }
            }
            if let r = restRetract, t - r.start > GestureTuning.liftRetractWindow
                || length(tr.cur - r.anchor) > GestureTuning.points(mm: GestureTuning.liftRollHoldMillimetres) {
                restRetract = nil
            }
        }
        let out = accel(live) + backlogStep(t: t)
        if holding && out == .zero { return [] }
        noteEmitted(out)
        return [pointerEvent(out, drag: drag)]
    }

    /// Whether held motion should be let go: the finger is clearly travelling (or, for a roll
    /// hold, no lift came in time). While a tap is still possible, nothing is released by time.
    private func holdReleases(_ h: Hold, cur: V, t: TimeInterval, downTime: TimeInterval) -> Bool {
        let tapPending = h.reason == .touchDown && t - downTime <= GestureTuning.tapMaxDuration
        let base: Bool
        switch h.reason {
        case .touchDown:
            let limit = tapPending ? GestureTuning.points(mm: GestureTuning.touchDownHoldMillimetres)
                                   : GestureTuning.pointerStartSlop
            base = length(cur - h.anchor) > limit
        case .roll:
            base = true
        }
        guard base else { return false }
        guard let rf = h.rollFrom else { return true }
        if length(cur - rf) >= GestureTuning.points(mm: GestureTuning.liftRollHoldMillimetres) { return true }
        return !tapPending && t - h.rollSince >= GestureTuning.rollHoldMaxTime
    }

    /// Contact shrinking plus a speed spike on the only finger: the start of a lift-off roll.
    private func updateRollSignal(t: TimeInterval) {
        rollSignal = false
        guard touches.count == 1, let tr = touches.values.first else { speedHistory = []; return }
        // Against the slowest recent frame: a finger that slowed onto its target and then rolls
        // off is a spike; a flick lifted at speed is not.
        // A gap in frames means the finger was still (UIKit sends nothing for a still finger).
        if let last = speedHistory.last?.t ?? lastSpeedSampleTime, t - last > 2 * GestureTuning.speedWindow {
            speedHistory.append((t - GestureTuning.speedWindow, 0))
        }
        lastSpeedSampleTime = t
        let slowest = speedHistory.filter { $0.t >= t - GestureTuning.rollSpeedWindow && $0.t < t }.map(\.v).min() ?? 0
        let minSpeed = GestureTuning.points(mm: GestureTuning.rollMinSpeedMillimetresPerSecond)
        let spike = fingerSpeed >= minSpeed && fingerSpeed >= slowest * GestureTuning.rollSpikeRatio
        let shrinking = tr.contactShrinking
        if !shrinking { rollSpent = false }
        rollSignal = spike && shrinking && !rollSpent
        speedHistory.append((t, fingerSpeed))
        speedHistory.removeAll { $0.t < t - GestureTuning.rollSpeedWindow }
    }

    /// Starts feeding out `total` (Mac points). The first share goes out in this same frame, as
    /// if the release began one report period ago, so a released hold moves the pointer at once.
    private func startBacklog(_ total: V, t: TimeInterval) {
        guard total != .zero else { return }
        let start = t - GestureTuning.speedWindow
        if let b = backlog {
            backlog = Backlog(total: b.total - b.released + total, start: start)
        } else {
            backlog = Backlog(total: total, start: start)
        }
    }

    /// The share of the backlog due by `t` (Mac points).
    private func backlogStep(t: TimeInterval) -> V {
        guard var b = backlog else { return .zero }
        let f = min(max((t - b.start) / GestureTuning.heldMotionReleaseTime, 0), 1)
        let step = b.total * f - b.released
        b.released += step
        backlog = f >= 1 ? nil : b
        return step
    }

    private func noteEmitted(_ out: V) {
        session?.emitted += out
        restRetract?.emitted += out
    }

    private func pointerEvent(_ v: V, drag: Bool) -> GestureEvent {
        drag ? .drag(dx: v.x, dy: v.y) : .move(dx: v.x, dy: v.y)
    }

    /// Forgets held motion, the backlog and the rest record (fingers added, gesture changed).
    private func dropPointerState() {
        hold = nil
        backlog = nil
        restRetract = nil
    }

    /// The last finger left while moving the pointer. A tap puts the pointer back where the
    /// finger landed (the click lands there); a lift right after leaving rest takes back the
    /// roll; otherwise the backlog goes out. Held motion is always discarded.
    private func finishPointer(tapping: Bool) -> [GestureEvent] {
        defer { dropPointerState() }
        let drag: Bool
        switch state {
        case .pointing: drag = false
        case .dragging(let src) where src != .threeFinger: drag = true
        case .possible, .holding:
            if tapping, let e = session?.emitted, e != .zero { return [pointerEvent(-e, drag: false)] }
            return []
        default: return []
        }
        if tapping {
            guard let e = session?.emitted, e != .zero else { return [] }
            session?.emitted = .zero
            return [pointerEvent(-e, drag: drag)]
        }
        if let r = restRetract, r.emitted != .zero {
            return [pointerEvent(-r.emitted, drag: drag)]
        }
        if let b = backlog, b.total - b.released != .zero {
            let rest = b.total - b.released
            noteEmitted(rest)
            return [pointerEvent(rest, drag: drag)]
        }
        return []
    }

    /// Whether the session ending at `t` will be recognised as a tap (of any finger count).
    private func endsAsTap(t: TimeInterval) -> Bool {
        guard let s = session, s.tapCandidate else { return false }
        return t - s.startTime <= GestureTuning.tapMaxDuration && s.maxDisplacement <= GestureTuning.tapSlop
            && s.maxFingers <= 3
    }

    // MARK: Lifts and additions

    private func handleLift(t: TimeInterval) -> [GestureEvent] {
        let r = touches.count
        var ev: [GestureEvent] = []
        switch state {
        case .idle:
            break
        case .possible:
            if r == 1, session?.resumePointing == true {
                // The extra fingers came and went without a gesture: the remaining finger
                // points again, from where it is now (its motion was never averaged with theirs).
                state = .pointing
                dropPointerState()
                rebase()
            } else if r > 0, (session?.maxFingers ?? 0) >= 2 {
                state = .consumed
            }
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
            ev += finishPointer(tapping: endsAsTap(t: t))
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
            dropPointerState()
            speedHistory = []
            rollSpent = false
            if n == 1 { hold = Hold(reason: .touchDown, anchor: firstOrigin) }
            return []
        }
        if let m = session?.maxFingers { session?.maxFingers = max(m, n) }
        var ev: [GestureEvent] = []
        // A landing finger never moves the pointer: whatever was held back or still being fed
        // out belonged to the hand settling, not to a move.
        dropPointerState()
        switch state {
        case .possible, .pointing:
            if case .pointing = state { session?.resumePointing = true }
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

    /// Fingers dropped by the stale guard are back: track them again as one ongoing touch that
    /// can point (one finger) or does nothing (several), and can never end as a tap.
    private func readopt(firstOrigin: V, t: TimeInterval) -> [GestureEvent] {
        let n = touches.count
        session = Session(startTime: t, maxFingers: n, tapCandidate: false, tapDragArmed: false, firstOrigin: firstOrigin)
        state = n == 1 ? .pointing : .consumed
        fingerSpeed = 0
        speedHistory = []
        rollSpent = false
        dropPointerState()
        rebase()
        return []
    }

    private func rebase() {
        for id in touches.keys { touches[id]!.start = touches[id]!.cur }
        if case .holding = state { dropPointerState() }
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
        dropPointerState()
        isStalled = false
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
