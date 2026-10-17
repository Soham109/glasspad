import Foundation

/// Measures, on the Mac, how late the first touch arrives after the phone went quiet (its
/// keep-awake heartbeats stopped, so its Wi-Fi radio may have gone to sleep). The two clocks
/// differ, so it compares the first frame's arrival minus its phone timestamp with the same
/// for the fastest frame in the next second: the difference is the extra delay of the first
/// touch. One line per rest, in the log:
/// `rest: first touch after 47.2 s quiet came 112 ms late (fastest of 63 frames in the next 1.0 s)`.
public struct RestWakeProbe: Sendable {
    /// Quiet for at least this long (no touch frame and no heartbeat) counts as a rest.
    /// Heartbeats come every 20 ms while they run, so anything near this is a real pause.
    public static let restAfter: TimeInterval = 2
    /// How long after the first touch to look for the fastest frame.
    public static let window: TimeInterval = 1

    public struct Result: Equatable, Sendable {
        /// Seconds without any datagram before the touch.
        public var quiet: TimeInterval
        /// How much later the first touch came than the fastest frame after it, in ms.
        public var lateMs: Double
        /// Frames looked at, the first one included.
        public var frames: Int

        public var line: String {
            String(format: "rest: first touch after %.1f s quiet came %.0f ms late (fastest of %d frames in the next %.1f s)",
                   quiet, lateMs, frames, RestWakeProbe.window)
        }
    }

    private var lastDatagram: TimeInterval?
    /// The rest being measured: how long it was, when the first touch came, and its offset.
    private var measuring: (quiet: TimeInterval, start: TimeInterval, firstOffset: Double, bestOffset: Double, frames: Int)?

    public init() {}

    /// A heartbeat arrived (Mac uptime).
    public mutating func heartbeat(at arrival: TimeInterval) -> Result? {
        let done = finishIfDue(arrival)
        lastDatagram = arrival
        return done
    }

    /// A touch frame arrived (Mac uptime), stamped `timestamp` on the phone. Returns a result
    /// once the window after a rest's first touch has passed.
    public mutating func touch(at arrival: TimeInterval, timestamp: TimeInterval) -> Result? {
        let done = finishIfDue(arrival)
        let offset = arrival - timestamp
        if var m = measuring {
            m.bestOffset = min(m.bestOffset, offset)
            m.frames += 1
            measuring = m
        } else if let last = lastDatagram, arrival - last >= Self.restAfter {
            measuring = (arrival - last, arrival, offset, offset, 1)
        }
        lastDatagram = arrival
        return done
    }

    /// A new session started at `now`: quiet is counted from there, nothing carries over.
    public mutating func sessionStarted(at now: TimeInterval) {
        lastDatagram = now
        measuring = nil
    }

    private mutating func finishIfDue(_ now: TimeInterval) -> Result? {
        guard let m = measuring, now - m.start >= Self.window else { return nil }
        measuring = nil
        return Result(quiet: m.quiet, lateMs: max(0, (m.firstOffset - m.bestOffset) * 1000), frames: m.frames)
    }
}
