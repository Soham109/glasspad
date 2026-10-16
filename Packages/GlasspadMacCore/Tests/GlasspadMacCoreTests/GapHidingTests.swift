import CoreGraphics
import Foundation
import GlasspadKit
import Testing
@testable import GlasspadMacCore

/// Wi-Fi gaps hidden by `MotionScheduler`: prediction across gaps, smooth reconciliation, smooth
/// bursts, and the states where nothing may be extrapolated. Gap patterns follow the owner's
/// `feel:` logs (AWDL hops: gaps of 70 to 200 ms, frames lost or delivered in a burst). Fake
/// clocks only; nothing is posted to the session.
@Suite struct GapPredictionTests {
    static let frame = 1.0 / 120
    static let offset = 50.0

    /// One phone frame as the scheduler sees it.
    struct F {
        var t: Double
        var arrival: Double
        var events: [GestureEvent]
        var continuing: MotionStream?
    }

    /// Plays `frames` and display frames (from the first frame to `until`, phone time) on one
    /// local timeline. Returns per display frame (phone playhead time, events).
    static func play(_ frames: [F], until: Double, scheduler s: MotionScheduler = MotionScheduler())
        -> [(t: Double, events: [GestureEvent])] {
        let sorted = frames.sorted { $0.arrival < $1.arrival }
        var i = 0
        var out: [(Double, [GestureEvent])] = []
        var v = (frames.first?.t ?? 0) + offset + 0.0005
        while v < until + offset {
            while i < sorted.count, sorted[i].arrival <= v {
                let f = sorted[i]
                s.enqueue(f.events, frameTime: f.t, arrival: f.arrival, clockOffset: offset, continuing: f.continuing)
                i += 1
            }
            out.append((v - offset, s.flush(now: v, framePeriod: frame)))
            v += frame
        }
        return out
    }

    static func x(_ e: [GestureEvent]) -> Double {
        e.reduce(0) { sum, ev in
            switch ev {
            case .move(let dx, _), .drag(let dx, _): sum + dx
            case .scroll(let dx, _, .changed, .none): sum + dx
            default: sum
            }
        }
    }

    /// A finger moving 10 pt per 8.3 ms sample (1200 pt/s) from phone time 0 to `end`, then
    /// resting (the phone resends every 20 ms). `lost` phone intervals never arrive (the next
    /// frame carries their travel, as a full snapshot does); `held` intervals arrive together
    /// when the interval ends (a burst after an AWDL hop).
    static func stroke(end: Double, lost: [ClosedRange<Double>] = [], held: [ClosedRange<Double>] = [],
                       rest: Double = 0.2, kind: (Double, Double) -> GestureEvent = { .move(dx: $0, dy: $1) },
                       stream: MotionStream? = .move) -> (frames: [F], total: Double) {
        var frames: [F] = []
        var x = 0.0, sent = 0.0
        var k = 0
        while Double(k) * frame <= end {
            let t = Double(k) * frame
            x += k == 0 ? 0 : 10
            k += 1
            if lost.contains(where: { $0.contains(t) }) { continue }
            let arrival = (held.first { $0.contains(t) }?.upperBound ?? t) + offset + 0.001
            frames.append(F(t: t, arrival: arrival, events: [kind(x - sent, 0)], continuing: stream))
            sent = x
        }
        var t = Double(k - 1) * frame + 0.02
        while t <= end + rest {
            frames.append(F(t: t, arrival: t + offset + 0.001, events: [kind(x - sent, 0)], continuing: stream))
            sent = x
            t += 0.02
        }
        return (frames, x)
    }

    /// Longest run of display frames with no motion in phone time `range`.
    static func longestStall(_ out: [(t: Double, events: [GestureEvent])], in range: ClosedRange<Double>) -> Int {
        var run = 0, best = 0
        for o in out where range.contains(o.t) {
            if abs(x(o.events)) < 0.01 { run += 1; best = max(best, run) } else { run = 0 }
        }
        return best
    }

    @Test func lostFramesMidMoveAreBridgedWithoutAPauseOrAJump() {
        let (frames, total) = Self.stroke(end: 0.7, lost: [0.3...0.4])
        let s = MotionScheduler()
        let out = Self.play(frames, until: 1.0, scheduler: s)
        let steps = out.map { Self.x($0.events) }
        let moving = out.filter { (0.05...0.65).contains($0.t) }.map { Self.x($0.events) }
        // Without prediction the pointer would sit still for the whole 100 ms gap (12 frames).
        #expect(Self.longestStall(out, in: 0.05...0.65) <= 1)
        // Never backwards while the finger keeps going, and catching up is a short speed-up
        // (at most about three times the finger's own speed), not a jump.
        #expect(moving.allSatisfy { $0 >= -1e-9 })
        #expect((moving.max() ?? 0) <= 32)
        // Nothing lost or invented.
        #expect(abs(steps.reduce(0, +) + Self.x(s.drain()) - total) < 1e-6)
        #expect(s.stats.predictedTime > 0.08)
        #expect(s.stats.corrections >= 1)
        let baseline = MotionScheduler()
        baseline.config.predicts = false
        #expect(Self.longestStall(Self.play(frames, until: 1.0, scheduler: baseline), in: 0.05...0.65) >= 10)
    }

    @Test func aBurstAfterAGapIsFedOutSmoothly() {
        // Frames from 120 ms of travel are held back and then arrive in one burst, twice.
        let (frames, total) = Self.stroke(end: 0.9, held: [0.2...0.32, 0.55...0.62])
        let s = MotionScheduler()
        let out = Self.play(frames, until: 1.2, scheduler: s)
        let moving = out.filter { (0.05...0.85).contains($0.t) }.map { Self.x($0.events) }
        #expect((moving.max() ?? 0) <= 32)                  // the raw burst would be 120 pt at once
        #expect(moving.allSatisfy { $0 >= -1e-9 })
        #expect(Self.longestStall(out, in: 0.05...0.85) <= 1)
        #expect(abs(out.map { Self.x($0.events) }.reduce(0, +) + Self.x(s.drain()) - total) < 1e-6)
        #expect(s.stats.smoothedLate > 100)
        // The same burst with no smoothing and no prediction lands as one big step.
        let raw = MotionScheduler()
        raw.config.predicts = false
        raw.config.lateGraceFrames = 1000
        let rawMax = Self.play(frames, until: 1.2, scheduler: raw).map { Self.x($0.events) }.max() ?? 0
        #expect(rawMax >= 60)
    }

    @Test func aFingerThatStopsDoesNotOvershootVisibly() {
        // Constant speed, then a hard stop: the phone's 20 ms resend confirms the stop, so the
        // prediction runs a few ms at most and is taken back over a few frames.
        let (frames, total) = Self.stroke(end: 0.4)
        let s = MotionScheduler()
        let out = Self.play(frames, until: 0.7, scheduler: s)
        var pos = 0.0, peak = 0.0
        for o in out { pos += Self.x(o.events); peak = max(peak, pos) }
        #expect(peak - total <= 8)                           // under 7 ms of travel at 1200 pt/s
        #expect(abs(pos - total) < 1e-6)                     // and it ends exactly where the finger did
        // Slowing down to a stop (the usual way): no visible overshoot at all.
        var slowing: [F] = []
        var x = 0.0, t = 0.0, v = 10.0
        while v > 0.05 {
            slowing.append(F(t: t, arrival: t + Self.offset + 0.001, events: [.move(dx: v, dy: 0)], continuing: .move))
            x += v; v *= 0.85; t += Self.frame
        }
        for k in 1...10 {
            let tr = t + Double(k) * 0.02
            slowing.append(F(t: tr, arrival: tr + Self.offset + 0.001, events: [.move(dx: 0, dy: 0)], continuing: .move))
        }
        let s2 = MotionScheduler()
        var p2 = 0.0, peak2 = 0.0
        for o in Self.play(slowing, until: t + 0.3, scheduler: s2) { p2 += Self.x(o.events); peak2 = max(peak2, p2) }
        #expect(peak2 - x <= 1)
        #expect(abs(p2 - x) < 1e-6)
    }

    @Test func aLinkThatNeverComesBackOvershootsAtMostTheCap() {
        let (frames, total) = Self.stroke(end: 0.3, rest: 0)
        let s = MotionScheduler()
        let out = Self.play(frames, until: 1.0, scheduler: s)
        let after = out.map { Self.x($0.events) }.reduce(0, +) - total
        #expect(after <= s.config.maxPredictedTravel + 1e-9)
        #expect(s.stats.predictedTime <= s.config.maxPrediction + 1e-9)
        // It ramps down: the last predicted frames move far less than the first.
        let predicted = out.filter { $0.t > 0.32 }.map { Self.x($0.events) }.filter { $0 > 0 }
        #expect(predicted.count > 5)
        #expect(predicted.last! < predicted.first! * 0.5)
    }

    @Test func nothingIsExtrapolatedInAHoldOrAfterALift() {
        // The recognizer reports no continuing motion (a tap hold, a force click, a lift):
        // during the gap the output stays still.
        let (frames, _) = Self.stroke(end: 0.7, lost: [0.3...0.4], stream: nil)
        let s = MotionScheduler()
        let out = Self.play(frames, until: 1.0, scheduler: s)
        let gap = out.filter { (0.31...0.39).contains($0.t) }.map { Self.x($0.events) }
        #expect(gap.allSatisfy { abs($0) < 1e-9 })
        #expect(s.stats.predictedTime == 0)
        // A lift ends the stream: the frames after it carry no continuing motion.
        var lifted = Self.stroke(end: 0.3, rest: 0).frames
        lifted[lifted.count - 1].continuing = nil
        let s2 = MotionScheduler()
        _ = Self.play(lifted, until: 0.6, scheduler: s2)
        #expect(s2.stats.predictedTime == 0)
    }

    @Test func scrollAndDragAreBridgedToo() {
        let (scroll, scrollTotal) = Self.stroke(end: 0.7, lost: [0.3...0.4],
                                                kind: { .scroll(dx: $0, dy: $1, phase: .changed, momentum: .none) },
                                                stream: .scroll)
        let s = MotionScheduler()
        let out = Self.play(scroll, until: 1.0, scheduler: s)
        #expect(Self.longestStall(out, in: 0.05...0.65) <= 1)
        #expect(abs(out.map { Self.x($0.events) }.reduce(0, +) + Self.x(s.drain()) - scrollTotal) < 1e-6)

        // A drag through a gap, then the button comes up: every bit of drag motion (including
        // what catch-up still owed) goes out before the release, so the drop lands where the
        // finger was.
        var (drag, dragTotal) = Self.stroke(end: 0.5, lost: [0.3...0.42], rest: 0,
                                            kind: { .drag(dx: $0, dy: $1) }, stream: .drag)
        let up = drag.last!.t + Self.frame
        drag.append(F(t: up, arrival: up + Self.offset + 0.001, events: [.button(.left, down: false, clickCount: 1)]))
        let s2 = MotionScheduler()
        let dragOut = Self.play(drag, until: 0.8, scheduler: s2).flatMap(\.events)
        let upIndex = dragOut.firstIndex(of: .button(.left, down: false, clickCount: 1))!
        #expect(abs(Self.x(Array(dragOut[..<upIndex])) - dragTotal) < 1e-6)
        #expect(Self.x(Array(dragOut[upIndex...])) == 0)
    }

    @Test func lateSwipeProgressEasesAndNeverRunsAhead() {
        // A Spaces swipe whose frames from 0.2 to 0.3 s arrive in one burst.
        var frames: [F] = []
        var t = 0.0, p = 0.0
        frames.append(F(t: 0, arrival: Self.offset + 0.001, events: [.swipe(.spaces, progress: 0, phase: .began)]))
        while t < 0.5 {
            t += Self.frame; p += 0.02
            let arrival = ((0.2...0.3).contains(t) ? 0.3 : t) + Self.offset + 0.001
            frames.append(F(t: t, arrival: arrival, events: [.swipe(.spaces, progress: p, phase: .changed)]))
        }
        let final = p
        frames.append(F(t: t + Self.frame, arrival: t + Self.frame + Self.offset + 0.001,
                        events: [.swipe(.spaces, progress: final, phase: .ended)]))
        let out = Self.play(frames, until: 0.7).flatMap(\.events)
        let shown: [Double] = out.compactMap { if case .swipe(_, let q, _) = $0 { return q }; return nil }
        let jumps = zip(shown.dropFirst(), shown).map { $0 - $1 }
        #expect(jumps.allSatisfy { $0 >= -1e-9 })            // continuous, never back
        #expect((jumps.max() ?? 0) <= 0.12)                  // the raw burst is a 0.24 jump
        #expect(shown.allSatisfy { $0 <= final + 1e-9 })     // never extrapolated past the fingers
        #expect(out.last == .swipe(.spaces, progress: final, phase: .ended))
    }
}

/// The same gaps through the whole Mac pipeline (real recognizer, display clock, synthesizer).
@Suite @MainActor struct GapPipelineTests {
    static let sample = 1.0 / 120
    static let offset = 50.0

    /// A one-finger move at 60 mm/s for `duration`, delivered with a recorded-like gap pattern:
    /// a frame whose phone time falls in `lost` never arrives; one in `held` arrives at the end of
    /// its range. Returns each display frame's posted pointer x travel.
    func run(lost: [ClosedRange<Double>], held: [ClosedRange<Double>], predicts: Bool, duration: Double = 1.2)
        -> (perFrame: [(t: Double, dx: Double)], total: Double, stats: MotionScheduler.Stats) {
        let (synth, poster) = makeSynth()
        let clock = ManualFrameClock()
        let pipeline = TouchPipeline(settings: .macDefault, synth: synth, frameClock: clock)
        pipeline.scheduler.config.predicts = predicts
        var stats = MotionScheduler.Stats()
        pipeline.onDiagnostics = { stats.predictedTime += $0.predictedMs / 1000 }
        var local = 0.0
        pipeline.now = { local }
        let perFrame = GestureTuning.points(mm: 60) / 120
        var timeline: [(t: Double, frame: TouchFrame?)] = []
        var x = 100.0
        var k = 0
        while Double(k) * Self.sample <= duration {
            let t = Double(k) * Self.sample
            let phase: TouchPhase = k == 0 ? .began : .moved
            if k > 0 { x += perFrame }
            k += 1
            if lost.contains(where: { $0.contains(t) }) { continue }
            let arrival = (held.first { $0.contains(t) }?.upperBound ?? t) + Self.offset + (k % 3 == 0 ? 0.003 : 0.001)
            timeline.append((arrival, TouchFrame(seq: UInt32(k), timestamp: t, touches: [Touch(id: 1, phase: phase, x: x, y: 400, majorRadius: 22)],
                                                 surface: CGSize(width: 390, height: 844))))
        }
        let liftT = Double(k) * Self.sample
        timeline.append((liftT + Self.offset + 0.001, TouchFrame(seq: UInt32(k + 1), timestamp: liftT,
                                                                 touches: [Touch(id: 1, phase: .ended, x: x, y: 400, majorRadius: 22)],
                                                                 surface: CGSize(width: 390, height: 844))))
        var v = Self.offset + 0.003
        while v < liftT + Self.offset + 0.4 { timeline.append((v, nil)); v += Self.sample }
        timeline.sort { $0.t < $1.t }
        var out: [(Double, Double)] = []
        var seen = 0
        for item in timeline {
            local = item.t
            if let f = item.frame {
                pipeline.process(f)
            } else {
                clock.fire(period: Self.sample)
                var dx = 0.0
                while seen < poster.events.count {
                    let e = poster.events[seen]
                    if e.type == .mouseMoved { dx += Double(e.location.x) - 500 }
                    seen += 1
                }
                out.append((item.t - Self.offset, dx))
            }
        }
        stats.predictedTime += pipeline.scheduler.stats.predictedTime
        let total = poster.events.filter { $0.type == .mouseMoved }.reduce(0) { $0 + Double($1.location.x) - 500 }
        return (out, total, stats)
    }

    func longestStall(_ f: [(t: Double, dx: Double)], in range: ClosedRange<Double>) -> Int {
        var run = 0, best = 0
        for o in f where range.contains(o.t) {
            if abs(o.dx) < 0.01 { run += 1; best = max(best, run) } else { run = 0 }
        }
        return best
    }

    @Test func recordedGapsNoLongerPauseThePointer() {
        // From the owner's log: 70 ms and 120 ms gaps (frames lost), and a 90 ms hold-back that
        // arrives as one burst, while the finger moves steadily.
        let lost = [0.30...0.37, 0.62...0.74]
        let held = [0.92...1.01]
        let fixed = run(lost: lost, held: held, predicts: true)
        let before = run(lost: lost, held: held, predicts: false)
        let moving = 0.15...1.15
        #expect(longestStall(before.perFrame, in: moving) >= 8)          // what the owner saw
        #expect(longestStall(fixed.perFrame, in: moving) <= 2)
        // Never a step backwards while the finger moves forward, and no jump on resume.
        let steps = fixed.perFrame.filter { moving.contains($0.t) }.map(\.dx)
        #expect(steps.allSatisfy { $0 >= -1e-9 })
        let typical = steps.sorted()[steps.count / 2]
        #expect((steps.max() ?? 0) <= typical * 3.5 + 1)
        // Same end point as without prediction: nothing lost or invented.
        #expect(abs(fixed.total - before.total) < 1e-6)
        #expect(fixed.stats.predictedTime > 0.1)
    }

    @Test func diagnosticsReportPredictionAndFixes() {
        var d = TouchDiagnostics()
        for k in 0..<120 { d.frame(seq: UInt32(k + 1), arrival: Double(k) / 120, lateness: 0.001) }
        var m = MotionScheduler.Stats()
        m.predictedTime = 0.18
        m.corrections = 3
        m.maxCorrection = 6.24
        m.smoothedLate = 140
        let line = d.summary(now: 1.0, bufferDelay: 0.0214, motion: m)?.line ?? ""
        #expect(line.contains("buffer 21.4 ms, predicted 180 ms, fixes 3 max 6.2, smoothed 140"))
    }
}
