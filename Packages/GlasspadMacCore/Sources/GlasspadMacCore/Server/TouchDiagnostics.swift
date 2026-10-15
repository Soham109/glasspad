import Foundation
import GlasspadKit

/// Measures the touch stream as the Mac sees it, so feel problems can be read from the log
/// instead of guessed: frames per second, gaps between arrivals, lost packets (sequence holes),
/// how late frames arrive compared with the fastest one, the jitter buffer delay, and how
/// many display frames and pointer events went out. One summary line per second while frames
/// flow (`GPLog`, subsystem com.soham109.glasspad), e.g.
/// `feel: 238 fps, gap p50 4.2 p95 8.4 max 21.0 ms, lost 0, late p50 0.9 p95 3.1 max 12.4 ms, buffer 3.0 ms, display 120 Hz, out 120/s`.
public struct TouchDiagnostics {
    public struct Summary: Equatable, Sendable {
        public var frames: Int
        public var seconds: Double
        public var gapP50Ms: Double, gapP95Ms: Double, gapMaxMs: Double
        public var lost: Int
        public var lateP50Ms: Double, lateP95Ms: Double, lateMaxMs: Double
        public var bufferMs: Double
        public var displayFrames: Int
        public var outputEvents: Int

        public var line: String {
            func f(_ v: Double) -> String { String(format: "%.1f", v) }
            let fps = seconds > 0 ? Double(frames) / seconds : 0
            let hz = seconds > 0 ? Double(displayFrames) / seconds : 0
            let out = seconds > 0 ? Double(outputEvents) / seconds : 0
            return "feel: \(Int(fps.rounded())) fps, gap p50 \(f(gapP50Ms)) p95 \(f(gapP95Ms)) max \(f(gapMaxMs)) ms, "
                + "lost \(lost), late p50 \(f(lateP50Ms)) p95 \(f(lateP95Ms)) max \(f(lateMaxMs)) ms, "
                + "buffer \(f(bufferMs)) ms, display \(Int(hz.rounded())) Hz, out \(Int(out.rounded()))/s"
        }
    }

    /// Length of one summary window.
    public var interval: TimeInterval = 1
    private var windowStart: TimeInterval?
    private var lastArrival: TimeInterval?
    private var lastSeq: UInt32?
    private var gaps: [Double] = []
    private var late: [Double] = []
    private var lost = 0
    private var frames = 0
    private var displayFrames = 0
    private var outputEvents = 0

    public init() {}

    /// One touch frame arrived. `lateness` = arrival minus (phone time + learned offset).
    public mutating func frame(seq: UInt32, arrival: TimeInterval, lateness: Double) {
        if windowStart == nil { windowStart = arrival }
        if let a = lastArrival, arrival - a < 1 { gaps.append(arrival - a) }
        if let s = lastSeq {
            let d = seq &- s
            if d > 1, d < 1024 { lost += Int(d - 1) }
        }
        lastSeq = seq
        lastArrival = arrival
        late.append(max(lateness, 0))
        frames += 1
    }

    public mutating func displayFrame(outputEvents n: Int) {
        guard windowStart != nil else { return }
        displayFrames += 1
        outputEvents += n
    }

    /// Returns a summary once `interval` has passed since the window opened, and starts a new one.
    public mutating func summary(now: TimeInterval, bufferDelay: TimeInterval) -> Summary? {
        guard let start = windowStart, now - start >= interval, frames > 0 else { return nil }
        func q(_ v: [Double], _ p: Double) -> Double { MotionScheduler.quantile(v, p) * 1000 }
        let s = Summary(frames: frames, seconds: now - start,
                        gapP50Ms: q(gaps, 0.5), gapP95Ms: q(gaps, 0.95), gapMaxMs: (gaps.max() ?? 0) * 1000,
                        lost: lost,
                        lateP50Ms: q(late, 0.5), lateP95Ms: q(late, 0.95), lateMaxMs: (late.max() ?? 0) * 1000,
                        bufferMs: bufferDelay * 1000, displayFrames: displayFrames, outputEvents: outputEvents)
        windowStart = nil
        gaps = []; late = []; lost = 0; frames = 0; displayFrames = 0; outputEvents = 0
        return s
    }
}
