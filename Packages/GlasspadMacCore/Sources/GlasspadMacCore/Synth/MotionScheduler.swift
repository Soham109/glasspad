import Foundation
import GlasspadKit

/// Display-synced output with an adaptive jitter buffer, gap prediction and smooth catch-up.
///
/// Without it, every Wi-Fi packet became a pointer event the moment it arrived, so radio jitter
/// (packets bunching up, then a gap) turned straight into pointer jitter, and a 120 Hz display
/// saw 0, 1 or 3 pointer updates per frame. Here every event the recognizer makes is placed on
/// the phone's own timeline (the touch sample time), shifted onto the Mac clock with the learned
/// offset plus a delay `D`, and released at display frames. Motion (pointer moves, drags,
/// scroll changes) that a sample reports is spread evenly over the sample interval that
/// follows it (the time until the next sample is expected), so each display frame gets an even
/// share even though the phone's 120 Hz sampling and the Mac's display refresh beat against
/// each other. Spreading forward, not back toward the previous sample, means a sample never has
/// to be waited for before its own time: only `D` covers network lateness.
/// Discrete events (buttons, gesture phases) keep their order relative to the motion around them.
///
/// Buffer: `D` follows the 90th percentile of how late frames arrive (arrival minus the
/// fastest-seen delay), capped at `maxDelay`. It moves slowly (`delayRiseRate`,
/// `delayFallRate`, seconds of delay per second), so the playhead only ever runs a few percent
/// slow or fast while it changes. On a clean link `D` is 1 to 3 ms; on a bursty one (macOS
/// hopping the radio to AWDL) it grows toward `maxDelay` and shrinks again once the link calms.
///
/// Gaps: when the playhead runs past the last frame by `predictAfter` while the recognizer says
/// a move, drag or scroll is continuing (`GestureRecognizer.continuingMotion`, never in a hold,
/// a tap, a click or after a lift), the stream is carried on along its recent velocity (a robust
/// estimate over the last `velocityWindow`) with exponential decay, for at most `maxPrediction`
/// and `maxPredictedTravel` (a soft cap). When frames come back, the difference between what really happened
/// and what was predicted is fed out over a few display frames (catch-up), never as a jump.
///
/// Bursts: motion that reaches the playhead more than a display frame late (frames that queued up
/// behind a gap, or the one snapshot that carries a whole gap's travel) goes out through the same
/// catch-up, so a burst becomes a short, smooth speed-up instead of one jump. Swipe progress
/// that arrives late eases to its new value the same way; swipes are never extrapolated.
///
/// Pure logic, no clocks of its own: the caller passes times. Not thread safe.
public final class MotionScheduler {
    public struct Config: Sendable {
        /// Late fraction the buffer absorbs (0.9 = wait for 90% of frames).
        public var lateQuantile: Double = 0.9
        /// Lateness samples kept (about 1 to 2 s of touch frames).
        public var historyLength: Int = 240
        /// Largest buffer delay `D`, for a bursty link.
        public var maxDelay: TimeInterval = 0.035
        /// How fast `D` may grow and shrink, in seconds of delay per second.
        public var delayRiseRate: Double = 0.04
        public var delayFallRate: Double = 0.01
        /// Longest sample interval that is spread (a gap longer than this is a pause, and the
        /// motion after it goes out at once, or through catch-up mid-move).
        public var maxSpread: TimeInterval = 0.025
        /// Fraction of the sample interval motion is spread over: 1 = fully even, 0 = each
        /// sample's motion goes out whole at its own time (half an interval less latency).
        public var spreadFraction: Double = 1

        /// Carry motion across gaps at all.
        public var predicts = true
        /// Silence after the last frame before prediction starts. The phone resends a resting
        /// finger every 20 ms, so a finger that really stopped is confirmed within a few ms of
        /// this and the overshoot stays tiny.
        public var predictAfter: TimeInterval = 0.015
        /// The predicted velocity holds for `predictionHold` (most gaps are shorter: an AWDL
        /// hop is tens of ms), then decays with time constant `predictionDecay`.
        public var predictionHold: TimeInterval = 0.03
        public var predictionDecay: TimeInterval = 0.08
        /// Longest prediction.
        public var maxPrediction: TimeInterval = 0.14
        /// Longest predicted travel: Mac points (move, drag) and scroll pixels.
        public var maxPredictedTravel: Double = 80
        public var maxPredictedScroll: Double = 160
        /// Prediction starts only above this speed and stops when the decayed speed falls below
        /// `stopPredictSpeed` (units per second).
        public var minPredictSpeed: Double = 40
        public var stopPredictSpeed: Double = 15
        /// Velocity estimate windows: the long one is the estimate, the short one only ever
        /// lowers it (a finger slowing down to stop is not carried on at its old speed).
        public var velocityWindow: TimeInterval = 0.04
        public var velocityShortWindow: TimeInterval = 0.017

        /// Time constant of catch-up (late motion and prediction error).
        public var catchUpTime: TimeInterval = 0.02
        /// Catch-up never runs faster than this many times the stream's own speed, plus
        /// `catchUpMinSpeed` (units per second).
        public var catchUpSpeedFactor: Double = 1
        public var catchUpMinSpeed: Double = 150
        /// Motion up to this many display frames late goes out directly (ordinary jitter).
        public var lateGraceFrames: Double = 0.5
        public init() {}
    }

    /// What the scheduler did to hide the link, for the `feel:` log.
    public struct Stats: Equatable, Sendable {
        /// Playhead time spent predicting (seconds).
        public var predictedTime: TimeInterval = 0
        /// Predictions reconciled with real frames, and the largest error between the real
        /// travel over the gap and the predicted one (Mac points or scroll pixels).
        public var corrections: Int = 0
        public var maxCorrection: Double = 0
        /// Late motion fed out through catch-up (units) instead of in one display frame.
        public var smoothedLate: Double = 0
        public init() {}
    }

    public var config = Config()
    /// Current buffer delay in seconds.
    public private(set) var delay: TimeInterval = 0
    /// Display frame period last seen (seconds).
    public private(set) var framePeriod: TimeInterval = 1.0 / 120
    public private(set) var stats = Stats()
    /// True while anything is queued or still being fed out.
    public var hasPending: Bool {
        !queue.isEmpty || (swipe.map { $0.owed != 0 } ?? false)
            || streams.contains { $0.catchUp != .zero || ($0.prediction.map { !$0.finished } ?? false) }
    }

    public func resetStats() { stats = Stats() }

    typealias V = SIMD2<Double>

    private enum MotionKind: Int, CaseIterable {
        case move, drag, scroll
        init(_ s: MotionStream) {
            switch s {
            case .move: self = .move
            case .drag: self = .drag
            case .scroll: self = .scroll
            }
        }
    }

    private enum Item {
        /// Motion spread over phone time [t0, t1]; `done` is the fraction already emitted. A
        /// `lump` carries a whole gap's travel and always goes out through catch-up.
        case motion(MotionKind, V, t0: TimeInterval, t1: TimeInterval, done: Double, lump: Bool)
        case discrete(GestureEvent, t: TimeInterval)
    }

    private struct Prediction {
        /// Phone time the prediction counts from.
        var origin: TimeInterval
        var v0: V
        var tauMax: TimeInterval
        var maxTravel: Double
        var emitted: V = .zero
        var lastTau: TimeInterval = 0
        var finished = false
    }

    private struct Stream {
        /// Phone time of the last sample (for spreading).
        var lastTime: TimeInterval?
        /// Recent samples for the velocity estimate.
        var samples: [(t: TimeInterval, d: V)] = []
        /// Motion waiting to be fed out smoothly (late motion minus prediction debt).
        var catchUp: V = .zero
        /// Speed (units per second) catch-up may add on top of the stream: the speed the
        /// stream had when the catch-up began, so it does not crawl while history rebuilds.
        var catchUpSpeed: Double = 0
        /// Predicted motion posted but not yet confirmed by a real frame.
        var debt: V = .zero
        var prediction: Prediction?
    }

    /// An open dock swipe: its newest progress, how much of that is late and not shown yet,
    /// and whether a progress update is due this frame.
    private struct SwipeEase {
        var kind: SwipeKind
        var target: Double
        var owed: Double = 0
        var dirty = false
    }

    private var queue: [Item] = []
    private var streams = [Stream](repeating: Stream(), count: MotionKind.allCases.count)
    /// Phone times of frames not yet reached by the playhead (ascending).
    private var pendingFrames: [TimeInterval] = []
    /// Phone time of the newest frame the playhead has passed.
    private var lastReleasedFrame: TimeInterval?
    private var lastEnqueuedTime: TimeInterval?
    private var gate: MotionKind?
    private var swipe: SwipeEase?
    private var lateness: [Double] = []
    private var latenessHead = 0
    private var delayTarget: TimeInterval = 0
    private var offset: Double?
    private var lastPlayhead: TimeInterval?
    private var lastFlush: TimeInterval?

    /// A frame this much older than the newest one means the phone's clock restarted (the
    /// recognizer's own rule).
    static let clockJump: TimeInterval = GestureTuning.clockJumpTolerance

    public init(config: Config = Config()) { self.config = config }

    // MARK: Input

    /// Adds what the recognizer produced for one frame. `frameTime` is the phone timestamp,
    /// `arrival` the local clock when the frame arrived, `clockOffset` the recognizer's learned
    /// `local - phone` offset, `continuing` the recognizer's `continuingMotion` after the frame.
    public func enqueue(_ events: [GestureEvent], frameTime: TimeInterval, arrival: TimeInterval, clockOffset: Double,
                        continuing: MotionStream? = nil) {
        offset = clockOffset
        noteLateness(max(arrival - (frameTime + clockOffset), 0))
        if let last = lastEnqueuedTime, last - frameTime > Self.clockJump {
            // The phone's clock restarted: what is queued belongs to the old timeline and goes
            // out at once; spreading and prediction start over.
            queue = queue.map { item in
                switch item {
                case let .motion(k, d, _, _, done, _): .motion(k, d, t0: frameTime, t1: frameTime, done: done, lump: false)
                case let .discrete(e, _): .discrete(e, t: frameTime)
                }
            }
            for k in MotionKind.allCases {
                let owed = streams[k.rawValue].catchUp
                streams[k.rawValue] = Stream()
                streams[k.rawValue].catchUp = owed
            }
            pendingFrames = []
            lastEnqueuedTime = nil
            lastReleasedFrame = nil
            lastPlayhead = nil
        }
        // The recognizer drops reordered frames (only a lift survives, at the newest time), so
        // anything older than what is queued is placed at the newest time: order is kept.
        let t = max(frameTime, lastEnqueuedTime ?? frameTime)
        let fresh = lastEnqueuedTime.map { frameTime > $0 } ?? true
        lastEnqueuedTime = t
        // Every frame, even a reordered lift placed at the newest time, ends a prediction.
        if pendingFrames.last.map({ t > $0 }) ?? true { pendingFrames.append(t) }
        let wasGate = gate
        var moved = [Bool](repeating: false, count: MotionKind.allCases.count)
        for e in events {
            if let (k, d) = Self.motion(e) {
                var length = 0.0
                var lump = false
                if let p = streams[k.rawValue].lastTime, p < t {
                    let gap = t - p
                    if gap <= config.maxSpread {
                        length = gap * config.spreadFraction
                    } else if wasGate == k {
                        lump = true       // the stream kept going through a gap: this is its travel
                        streams[k.rawValue].catchUpSpeed = max(streams[k.rawValue].catchUpSpeed, Self.length(d) / gap)
                    }
                }
                streams[k.rawValue].lastTime = t
                streams[k.rawValue].samples.append((t, d))
                moved[k.rawValue] = true
                queue.append(.motion(k, d, t0: t, t1: t + length, done: 0, lump: lump))
            } else {
                // A discrete event breaks motion continuity of its stream (e.g. scroll began/ended).
                if case .scroll = e { breakStream(.scroll) }
                if case .button = e { breakStream(.move); breakStream(.drag) }
                queue.append(.discrete(e, t: t))
            }
        }
        gate = continuing.map(MotionKind.init)
        // Another stream took over (a press turned a move into a drag): old samples no longer apply.
        if let g = gate { for k in MotionKind.allCases where k != g { streams[k.rawValue].samples = [] } }
        if let g = gate, !moved[g.rawValue], fresh { streams[g.rawValue].samples.append((t, .zero)) }
        for k in MotionKind.allCases {
            streams[k.rawValue].samples.removeAll { $0.t < t - config.velocityWindow * 2 }
        }
    }

    private func breakStream(_ k: MotionKind) {
        streams[k.rawValue].lastTime = nil
        streams[k.rawValue].samples = []
    }

    /// The phone time the output has reached at local time `now` (nil before any frame).
    public func playhead(at now: TimeInterval) -> TimeInterval? {
        offset.map { now - $0 - delay }
    }

    /// The local time to hand `GestureRecognizer.tick(now:)` so its timers and momentum run on
    /// the same delayed timeline as everything else.
    public func tickTime(at now: TimeInterval) -> TimeInterval { now - delay }

    // MARK: Output

    /// Called at each display frame. Returns the events due by `now` (local clock), with
    /// consecutive motion of one kind merged into a single event.
    public func flush(now: TimeInterval, framePeriod period: TimeInterval) -> [GestureEvent] {
        if period > 0.001, period < 0.1 { framePeriod = period }
        updateDelay(now: now)
        guard let P = playhead(at: now) else { return [] }
        let lateBefore = lastPlayhead.map { $0 - framePeriod * config.lateGraceFrames }
        lastPlayhead = P
        var out: [GestureEvent] = []
        var pending: (MotionKind, V)?
        func flushPending() {
            if let (k, v) = pending { out.append(Self.event(k, v)) }
            pending = nil
        }
        func addMotion(_ k: MotionKind, _ v: V) {
            if let p = pending, p.0 == k { pending = (k, p.1 + v) } else { flushPending(); pending = (k, v) }
        }
        func addCatchUp(_ k: MotionKind, _ v: V) {
            streams[k.rawValue].catchUp += v
            stats.smoothedLate += Self.length(v)
        }
        /// Everything owed goes out now (before a discrete event, so a button or a phase never
        /// lands before the motion that came first).
        func settle() {
            for k in MotionKind.allCases where streams[k.rawValue].catchUp != .zero {
                addMotion(k, streams[k.rawValue].catchUp)
                streams[k.rawValue].catchUp = .zero
                streams[k.rawValue].catchUpSpeed = 0
            }
            if let s = swipe, s.dirty || s.owed != 0 {
                flushPending()
                out.append(.swipe(s.kind, progress: s.target, phase: .changed))
                swipe!.owed = 0
                swipe!.dirty = false
            }
        }

        // Frames the playhead reached end any prediction: what was predicted becomes debt the
        // real motion pays back (through catch-up).
        while let f = pendingFrames.first, f <= P {
            pendingFrames.removeFirst()
            lastReleasedFrame = f
            for k in MotionKind.allCases where streams[k.rawValue].prediction != nil { reconcile(k, frame: f) }
        }

        var consumed = 0
        loop: for i in queue.indices {
            switch queue[i] {
            case .discrete(let e, let t):
                guard t <= P else { break loop }
                consumed = i + 1
                if case let .swipe(kind, progress, .changed) = e, let s = swipe, s.kind == kind {
                    // Progress is cumulative: the late part of its change is shown over a few
                    // frames, the on-time part at once. Never ahead of the fingers.
                    if lateBefore.map({ t <= $0 }) == true { swipe!.owed += progress - s.target }
                    swipe!.target = progress
                    swipe!.dirty = true
                    continue
                }
                settle()
                flushPending()
                out.append(e)
                if case let .swipe(kind, progress, phase) = e {
                    swipe = phase == .began || phase == .changed ? SwipeEase(kind: kind, target: progress) : nil
                }
            case .motion(let k, let d, let t0, let t1, let done, let lump):
                let reached = t1 <= t0 ? (P >= t1 ? 1.0 : 0.0) : min(max((P - t0) / (t1 - t0), 0), 1)
                if reached > done {
                    let f = reached - done
                    if lump {
                        addCatchUp(k, d * f)
                    } else {
                        var lateF = 0.0
                        if let L = lateBefore {
                            let lf = t1 <= t0 ? (t1 <= L ? 1.0 : 0.0) : min(max((L - t0) / (t1 - t0), 0), 1)
                            lateF = max(0, min(reached, lf) - done)
                        }
                        if lateF > 0 { addCatchUp(k, d * lateF) }
                        if f - lateF > 0 { addMotion(k, d * (f - lateF)) }
                    }
                }
                if reached >= 1 {
                    consumed = i + 1
                } else {
                    queue[i] = .motion(k, d, t0: t0, t1: t1, done: max(done, reached), lump: lump)
                    break loop
                }
            }
        }
        queue.removeFirst(consumed)

        let alpha = 1 - exp(-framePeriod / config.catchUpTime)
        for k in MotionKind.allCases where streams[k.rawValue].catchUp != .zero {
            addMotion(k, catchUpStep(k, alpha: alpha))
        }
        if config.predicts, let k = gate { if let step = predictionStep(k, playhead: P) { addMotion(k, step) } }
        flushPending()
        if var s = swipe, s.dirty || s.owed != 0 {
            s.owed = abs(s.owed) < 0.002 ? 0 : s.owed * (1 - alpha)
            s.dirty = false
            swipe = s
            out.append(.swipe(s.kind, progress: s.target - s.owed, phase: .changed))
        }
        return out
    }

    /// Everything still queued or owed, at once (disconnect, cancel, or the display stopped).
    /// Predicted motion stays where it is.
    public func drain() -> [GestureEvent] {
        var out: [GestureEvent] = []
        var pending: (MotionKind, V)?
        func flushPending() {
            if let (k, v) = pending { out.append(Self.event(k, v)) }
            pending = nil
        }
        func add(_ k: MotionKind, _ v: V) {
            if let p = pending, p.0 == k { pending = (k, p.1 + v) } else { flushPending(); pending = (k, v) }
        }
        for k in MotionKind.allCases where streams[k.rawValue].catchUp != .zero { add(k, streams[k.rawValue].catchUp) }
        if let s = swipe, s.dirty || s.owed != 0 {
            flushPending()
            out.append(.swipe(s.kind, progress: s.target, phase: .changed))
        }
        for item in queue {
            switch item {
            case .discrete(let e, _):
                flushPending()
                out.append(e)
            case .motion(let k, let d, _, _, let done, _):
                add(k, d * (1 - done))
            }
        }
        flushPending()
        queue = []
        pendingFrames = []
        swipe = nil
        for k in MotionKind.allCases {
            streams[k.rawValue] = Stream()
        }
        return out
    }

    /// Forget timing (a new session or a phone clock restart).
    public func reset() {
        queue = []
        streams = [Stream](repeating: Stream(), count: MotionKind.allCases.count)
        pendingFrames = []
        lastReleasedFrame = nil
        lastEnqueuedTime = nil
        gate = nil
        swipe = nil
        lateness = []
        latenessHead = 0
        delayTarget = 0
        offset = nil
        lastPlayhead = nil
        lastFlush = nil
        delay = 0
    }

    // MARK: Prediction

    private func predictionStep(_ k: MotionKind, playhead P: TimeInterval) -> V? {
        var s = streams[k.rawValue]
        defer { streams[k.rawValue] = s }
        if s.prediction == nil {
            // Only once every frame up to now has been played and nothing new is due.
            guard let last = lastReleasedFrame, pendingFrames.first.map({ $0 > P }) ?? true,
                  P - last >= config.predictAfter else { return nil }
            let origin = last + config.predictAfter
            guard let v = velocity(s.samples), Self.length(v) >= config.minPredictSpeed else {
                s.prediction = Prediction(origin: origin, v0: .zero, tauMax: 0, maxTravel: 0, finished: true)
                return nil
            }
            let speed = Self.length(v)
            let tauStop = config.predictionHold + config.predictionDecay * log(speed / config.stopPredictSpeed)
            s.prediction = Prediction(origin: origin, v0: v, tauMax: min(config.maxPrediction, max(tauStop, 0)),
                                      maxTravel: k == .scroll ? config.maxPredictedScroll : config.maxPredictedTravel)
        }
        guard var p = s.prediction, !p.finished else { return nil }
        let tau = min(P - p.origin, p.tauMax)
        guard tau > p.lastTau else { return nil }
        let hold = config.predictionHold
        var S = p.v0 * (tau <= hold ? tau : hold + config.predictionDecay * (1 - exp(-(tau - hold) / config.predictionDecay)))
        // Soft travel cap: unchanged for short gaps, easing smoothly into `maxTravel`.
        let travel = Self.length(S)
        if travel > 0 { S *= p.maxTravel * tanh(travel / p.maxTravel) / travel }
        if tau >= p.tauMax { p.finished = true }
        let step = S - p.emitted
        stats.predictedTime += tau - p.lastTau
        p.emitted = S
        p.lastTau = tau
        s.debt += step
        s.prediction = p
        return step
    }

    /// A real frame (phone time `frame`) reached the playhead after a prediction began.
    private func reconcile(_ k: MotionKind, frame: TimeInterval) {
        var s = streams[k.rawValue]
        defer { streams[k.rawValue] = s }
        guard s.prediction != nil else { return }
        if s.debt != .zero {
            // The real travel over the gap is in this frame's motion (the snapshot after a gap
            // carries all of it), so the error is that minus what was predicted.
            var real = V.zero
            for item in queue {
                if case .motion(let mk, let d, let t0, _, _, _) = item, mk == k, t0 == frame { real += d }
            }
            let err = Self.length(real - s.debt)
            stats.corrections += 1
            stats.maxCorrection = max(stats.maxCorrection, err)
            s.catchUp -= s.debt
            s.debt = .zero
            s.catchUpSpeed = max(s.catchUpSpeed, Self.length(s.prediction!.v0))
        }
        s.prediction = nil
    }

    /// Robust recent velocity (units per phone second) from `samples`, or nil without enough
    /// history (no prediction in the first tens of ms of a move).
    private func velocity(_ samples: [(t: TimeInterval, d: V)]) -> V? {
        guard samples.count >= 3, let last = samples.last?.t else { return nil }
        func average(_ window: TimeInterval) -> (v: V, span: Double)? {
            guard let i = samples.firstIndex(where: { $0.t > last - window }), i >= 1 else { return nil }
            let span = last - samples[i - 1].t
            guard span > 0.004 else { return nil }
            let sum = samples[i...].reduce(V.zero) { $0 + $1.d }
            return (sum / span, span)
        }
        guard let long = average(config.velocityWindow), long.span >= config.velocityWindow / 2 else { return nil }
        let short = average(config.velocityShortWindow)?.v ?? long.v
        let ls = Self.length(long.v), ss = Self.length(short)
        guard ls > 0, (long.v * short).sum() > 0 else { return nil }
        return long.v * (min(ls, ss) / ls)
    }

    // MARK: Catch-up

    private func catchUpStep(_ k: MotionKind, alpha: Double) -> V {
        let c = streams[k.rawValue].catchUp
        let m = Self.length(c)
        var step = c
        if m > 0.05 {
            step = c * alpha
            let ref = max(velocity(streams[k.rawValue].samples).map(Self.length) ?? 0,
                          streams[k.rawValue].prediction.map { Self.length($0.v0) } ?? 0,
                          streams[k.rawValue].catchUpSpeed)
            let cap = (config.catchUpSpeedFactor * ref + config.catchUpMinSpeed) * framePeriod
            let sl = Self.length(step)
            if sl > cap { step *= cap / sl }
            if m - Self.length(step) < 0.05 { step = c }
        }
        streams[k.rawValue].catchUp -= step
        if Self.length(streams[k.rawValue].catchUp) < 1e-12 {
            streams[k.rawValue].catchUp = .zero
            streams[k.rawValue].catchUpSpeed = 0
        }
        return step
    }

    // MARK: Jitter estimate

    private func noteLateness(_ l: Double) {
        if lateness.count < config.historyLength {
            lateness.append(l)
        } else {
            lateness[latenessHead] = l
            latenessHead = (latenessHead + 1) % config.historyLength
        }
        delayTarget = min(Self.quantile(lateness, config.lateQuantile), config.maxDelay)
    }

    /// Moves `D` toward its target at a bounded rate, so the playhead never visibly speeds up
    /// or slows down while the buffer adapts.
    private func updateDelay(now: TimeInterval) {
        defer { lastFlush = now }
        guard let last = lastFlush else { return }
        let dt = min(max(now - last, 0), 0.05)
        if delayTarget > delay {
            delay = min(delayTarget, delay + config.delayRiseRate * dt)
        } else {
            delay = max(delayTarget, delay - config.delayFallRate * dt)
        }
    }

    static func quantile(_ values: [Double], _ q: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        let i = min(max(Int((q * Double(s.count)).rounded(.up)) - 1, 0), s.count - 1)
        return s[i]
    }

    // MARK: Event mapping

    private static func length(_ v: V) -> Double { (v * v).sum().squareRoot() }

    private static func motion(_ e: GestureEvent) -> (MotionKind, V)? {
        switch e {
        case let .move(dx, dy): (.move, V(dx, dy))
        case let .drag(dx, dy): (.drag, V(dx, dy))
        case let .scroll(dx, dy, .changed, .none): (.scroll, V(dx, dy))
        default: nil
        }
    }

    private static func event(_ k: MotionKind, _ v: V) -> GestureEvent {
        switch k {
        case .move: .move(dx: v.x, dy: v.y)
        case .drag: .drag(dx: v.x, dy: v.y)
        case .scroll: .scroll(dx: v.x, dy: v.y, phase: .changed, momentum: .none)
        }
    }
}
