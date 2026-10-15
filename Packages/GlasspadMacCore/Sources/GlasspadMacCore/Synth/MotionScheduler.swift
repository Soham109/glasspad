import Foundation
import GlasspadKit

/// Display-synced output with a small adaptive jitter buffer.
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
/// `D` is the 90th percentile of how late frames arrive (arrival minus the fastest-seen delay),
/// eased slowly, and never more than one display frame. Added latency: `D`, plus half a
/// sample interval on average for the spreading (about 4 ms at 120 Hz). On a clean link `D` is
/// 1 to 3 ms, so the total stays under one display frame.
///
/// Pure logic, no clocks of its own: the caller passes times. Not thread safe.
public final class MotionScheduler {
    public struct Config: Sendable {
        /// Late fraction the buffer absorbs (0.9 = wait for 90% of frames).
        public var lateQuantile: Double = 0.9
        /// Lateness samples kept (about 1 to 2 s of touch frames).
        public var historyLength: Int = 240
        /// How fast `D` follows its target per frame (0...1).
        public var easing: Double = 0.05
        /// Longest sample interval that is spread (a gap longer than this is a pause, and the
        /// motion after it goes out at once).
        public var maxSpread: TimeInterval = 0.025
        /// Fraction of the sample interval motion is spread over: 1 = fully even, 0 = each
        /// sample's motion goes out whole at its own time (half an interval less latency).
        public var spreadFraction: Double = 1
        /// `D` never exceeds this many display frames.
        public var maxDelayFrames: Double = 1.0
        public init() {}
    }

    public var config = Config()
    /// Current buffer delay in seconds.
    public private(set) var delay: TimeInterval = 0
    /// Display frame period last seen (seconds).
    public private(set) var framePeriod: TimeInterval = 1.0 / 120
    public var hasPending: Bool { !queue.isEmpty }

    private enum MotionKind: Equatable { case move, drag, scroll }

    private enum Item {
        /// Motion spread over phone time [t0, t1]; `done` is the fraction already emitted.
        case motion(MotionKind, dx: Double, dy: Double, t0: TimeInterval, t1: TimeInterval, done: Double)
        case discrete(GestureEvent, t: TimeInterval)

        var end: TimeInterval {
            switch self {
            case .motion(_, _, _, _, let t1, _): t1
            case .discrete(_, let t): t
            }
        }
    }

    private var queue: [Item] = []
    private var lateness: [Double] = []
    private var latenessHead = 0
    private var lastMotionTime: [MotionKind: TimeInterval] = [:]
    private var offset: Double?

    public init(config: Config = Config()) { self.config = config }

    // MARK: Input

    /// Adds what the recognizer produced for one frame. `frameTime` is the phone timestamp,
    /// `arrival` the local clock when the frame arrived, `clockOffset` the recognizer's learned
    /// `local - phone` offset.
    public func enqueue(_ events: [GestureEvent], frameTime t: TimeInterval, arrival: TimeInterval, clockOffset: Double) {
        offset = clockOffset
        noteLateness(max(arrival - (t + clockOffset), 0))
        for e in events {
            if let (kind, dx, dy) = Self.motion(e) {
                let prev = lastMotionTime[kind]
                var length = 0.0
                if let p = prev, p < t, t - p <= config.maxSpread { length = (t - p) * config.spreadFraction }
                lastMotionTime[kind] = t
                queue.append(.motion(kind, dx: dx, dy: dy, t0: t, t1: t + length, done: 0))
            } else {
                // A discrete event breaks motion continuity of its stream (e.g. scroll began/ended).
                if case .scroll = e { lastMotionTime[.scroll] = nil }
                if case .button = e { lastMotionTime[.move] = nil; lastMotionTime[.drag] = nil }
                queue.append(.discrete(e, t: t))
            }
        }
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
        delay = min(delay, framePeriod * config.maxDelayFrames)
        guard let P = playhead(at: now) else { return [] }
        var out: [GestureEvent] = []
        var pending: (MotionKind, Double, Double)?
        func flushPending() {
            if let (k, x, y) = pending { out.append(Self.event(k, x, y)) }
            pending = nil
        }
        func addMotion(_ k: MotionKind, _ x: Double, _ y: Double) {
            if let p = pending, p.0 == k { pending = (k, p.1 + x, p.2 + y) } else { flushPending(); pending = (k, x, y) }
        }
        var consumed = 0
        loop: for i in queue.indices {
            switch queue[i] {
            case .discrete(let e, let t):
                guard t <= P else { break loop }
                flushPending()
                out.append(e)
                consumed = i + 1
            case .motion(let k, let dx, let dy, let t0, let t1, let done):
                let reached = t1 <= t0 ? (P >= t1 ? 1.0 : 0.0) : min(max((P - t0) / (t1 - t0), 0), 1)
                if reached > done {
                    let f = reached - done
                    addMotion(k, dx * f, dy * f)
                }
                if reached >= 1 {
                    consumed = i + 1
                } else {
                    queue[i] = .motion(k, dx: dx, dy: dy, t0: t0, t1: t1, done: max(done, reached))
                    break loop
                }
            }
        }
        flushPending()
        queue.removeFirst(consumed)
        return out
    }

    /// Everything still queued, at once (disconnect, cancel, or the display stopped).
    public func drain() -> [GestureEvent] {
        var out: [GestureEvent] = []
        var pending: (MotionKind, Double, Double)?
        for item in queue {
            switch item {
            case .discrete(let e, _):
                if let (k, x, y) = pending { out.append(Self.event(k, x, y)); pending = nil }
                out.append(e)
            case .motion(let k, let dx, let dy, _, _, let done):
                let f = 1 - done
                if let p = pending, p.0 == k { pending = (k, p.1 + dx * f, p.2 + dy * f) } else {
                    if let (pk, x, y) = pending { out.append(Self.event(pk, x, y)) }
                    pending = (k, dx * f, dy * f)
                }
            }
        }
        if let (k, x, y) = pending { out.append(Self.event(k, x, y)) }
        queue = []
        lastMotionTime = [:]
        return out
    }

    /// Forget timing (a new session or a phone clock restart).
    public func reset() {
        queue = []
        lateness = []
        latenessHead = 0
        lastMotionTime = [:]
        offset = nil
        delay = 0
    }

    // MARK: Jitter estimate

    private func noteLateness(_ l: Double) {
        if lateness.count < config.historyLength {
            lateness.append(l)
        } else {
            lateness[latenessHead] = l
            latenessHead = (latenessHead + 1) % config.historyLength
        }
        let target = min(Self.quantile(lateness, config.lateQuantile), framePeriod * config.maxDelayFrames)
        delay += (target - delay) * config.easing
    }

    static func quantile(_ values: [Double], _ q: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        let i = min(max(Int((q * Double(s.count)).rounded(.up)) - 1, 0), s.count - 1)
        return s[i]
    }

    // MARK: Event mapping

    private static func motion(_ e: GestureEvent) -> (MotionKind, Double, Double)? {
        switch e {
        case let .move(dx, dy): (.move, dx, dy)
        case let .drag(dx, dy): (.drag, dx, dy)
        case let .scroll(dx, dy, .changed, .none): (.scroll, dx, dy)
        default: nil
        }
    }

    private static func event(_ k: MotionKind, _ x: Double, _ y: Double) -> GestureEvent {
        switch k {
        case .move: .move(dx: x, dy: y)
        case .drag: .drag(dx: x, dy: y)
        case .scroll: .scroll(dx: x, dy: y, phase: .changed, momentum: .none)
        }
    }
}
