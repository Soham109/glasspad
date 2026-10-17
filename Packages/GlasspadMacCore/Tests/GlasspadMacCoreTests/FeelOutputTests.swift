import CoreGraphics
import Foundation
import GlasspadKit
import Testing
@testable import GlasspadMacCore

/// Display-synced output: scripted frames with a fake clock, nothing posted to the session.
@Suite struct MotionSchedulerTests {
    let frame = 1.0 / 120
    let offset = 50.0          // local = phone + 50 s (+ network)

    func moves(_ e: [GestureEvent]) -> [Double] {
        e.compactMap { if case .move(let x, _) = $0 { return x }; return nil }
    }

    @Test func burstyArrivalsLeaveEvenly() {
        // The phone samples every 8.33 ms and moves 10 pt each time, but Wi-Fi delivers every
        // other frame 7 ms late, so frames bunch up in pairs. The fastest frames take 1 ms,
        // which is the offset the recognizer learns.
        let s = MotionScheduler()
        var outputs: [Double] = []
        var immediate: [Double] = []
        var vsync = 0.0
        var pendingArrivals: [(t: Double, arrival: Double)] = []
        for k in 0..<240 {
            let t = Double(k) * frame
            let late = k % 2 == 0 ? 0.007 : 0.0
            pendingArrivals.append((t, t + offset + 0.001 + late))
        }
        pendingArrivals.sort { $0.arrival < $1.arrival }
        var i = 0
        var perVsync: [Double] = []
        vsync = offset + 0.004          // display frames fall between the two arrival times
        while vsync < offset + 2.1 {
            var arrivedThisFrame = 0.0
            while i < pendingArrivals.count, pendingArrivals[i].arrival <= vsync {
                s.enqueue([.move(dx: 10, dy: 0)], frameTime: pendingArrivals[i].t, arrival: pendingArrivals[i].arrival,
                          clockOffset: offset + 0.001)
                arrivedThisFrame += 10
                i += 1
            }
            immediate.append(arrivedThisFrame)
            let out = moves(s.flush(now: vsync, framePeriod: frame)).reduce(0, +)
            perVsync.append(out)
            outputs.append(out)
            vsync += frame
        }
        // Steady state (skip the first half second while the buffer settles).
        let steady = Array(perVsync[60..<240])
        let raw = Array(immediate[60..<240])
        func spread(_ v: [Double]) -> Double { (v.max() ?? 0) - (v.min() ?? 0) }
        #expect(spread(raw) >= 10)              // posting on arrival: 0, 10 or 20 pt per frame
        #expect(spread(steady) < 2)             // display synced: about 10 pt every frame
        #expect(s.delay <= frame + 1e-9)        // never more than one display frame of delay
        // Nothing is lost or invented.
        let total = outputs.reduce(0, +) + moves(s.drain()).reduce(0, +)
        #expect(abs(total - 2400) < 1e-6)
    }

    @Test func motionIsSpreadAcrossItsSampleInterval() {
        let s = MotionScheduler()
        s.enqueue([.move(dx: 0, dy: 0)], frameTime: 1.0, arrival: 1.0 + offset, clockOffset: offset)
        s.enqueue([.move(dx: 12, dy: 6)], frameTime: 1.012, arrival: 1.012 + offset, clockOffset: offset)
        func xy(_ e: [GestureEvent]) -> (Double, Double)? {
            guard e.count == 1, case .move(let x, let y) = e[0] else { return nil }
            return (x, y)
        }
        // The second sample came 12 ms after the first, so its motion is spread over the 12 ms
        // after it: none before its own time, half 6 ms later, the rest by the end.
        #expect(s.flush(now: 1.0119 + offset, framePeriod: frame).allSatisfy { $0 == .move(dx: 0, dy: 0) })
        let half = xy(s.flush(now: 1.018 + offset, framePeriod: frame))
        #expect(half.map { abs($0.0 - 6) < 1e-6 && abs($0.1 - 3) < 1e-6 } == true)
        let rest = xy(s.flush(now: 1.03 + offset, framePeriod: frame))
        #expect(rest.map { abs($0.0 - 6) < 1e-6 && abs($0.1 - 3) < 1e-6 } == true)
        #expect(!s.hasPending)
    }

    @Test func discreteEventsKeepTheirPlaceAroundMotion() {
        let s = MotionScheduler()
        let t = 2.0
        s.enqueue([.move(dx: 5, dy: 0)], frameTime: t, arrival: t + offset, clockOffset: offset)
        s.enqueue([.button(.left, down: true, clickCount: 1), .drag(dx: 4, dy: 0)], frameTime: t + 0.008,
                  arrival: t + 0.008 + offset, clockOffset: offset)
        s.enqueue([.drag(dx: 4, dy: 0)], frameTime: t + 0.016, arrival: t + 0.016 + offset, clockOffset: offset)
        s.enqueue([.button(.left, down: false, clickCount: 1)], frameTime: t + 0.024, arrival: t + 0.024 + offset, clockOffset: offset)
        var out: [GestureEvent] = []
        var now = t + offset
        while now < t + offset + 0.05 { out += s.flush(now: now, framePeriod: frame); now += frame }
        let kinds = out.map { e -> String in
            switch e {
            case .move: "move"
            case .drag: "drag"
            case .button(_, let down, _): down ? "down" : "up"
            default: "other"
            }
        }
        // Merging never reorders: every move comes before the press, every drag inside it.
        let down = kinds.firstIndex(of: "down")!, up = kinds.firstIndex(of: "up")!
        #expect(kinds[..<down].allSatisfy { $0 == "move" })
        #expect(kinds[(down + 1)..<up].allSatisfy { $0 == "drag" })
        #expect(up == kinds.count - 1)
        let drags: [Double] = out.compactMap { if case .drag(let x, _) = $0 { return x }; return nil }
        let dragTotal = drags.reduce(0.0) { $0 + $1 }
        #expect(abs(dragTotal - 8) < 1e-9)
    }

    @Test func scrollPhasesSurviveAndChangesMerge() {
        let s = MotionScheduler()
        let t = 3.0
        s.enqueue([.scroll(dx: 0, dy: 4, phase: .began, momentum: .none)], frameTime: t, arrival: t + offset, clockOffset: offset)
        for k in 1...4 {
            let tk = t + Double(k) * 0.004
            s.enqueue([.scroll(dx: 0, dy: 2, phase: .changed, momentum: .none)], frameTime: tk, arrival: tk + offset, clockOffset: offset)
        }
        s.enqueue([.scroll(dx: 0, dy: 0, phase: .ended, momentum: .none)], frameTime: t + 0.02, arrival: t + 0.02 + offset, clockOffset: offset)
        let out = s.flush(now: t + 0.03 + offset, framePeriod: frame)
        #expect(out == [.scroll(dx: 0, dy: 4, phase: .began, momentum: .none),
                        .scroll(dx: 0, dy: 8, phase: .changed, momentum: .none),
                        .scroll(dx: 0, dy: 0, phase: .ended, momentum: .none)])
    }

    @Test func hugeLatenessRaisesTheBufferGraduallyToItsCap() {
        let s = MotionScheduler()
        var previous = 0.0
        var largestStep = 0.0
        for k in 0..<300 {
            let t = Double(k) * frame
            let late = k % 3 == 0 ? 0.08 : 0.0           // a third of the frames 80 ms late
            s.enqueue([.move(dx: 1, dy: 0)], frameTime: t, arrival: t + offset + late, clockOffset: offset)
            _ = s.flush(now: t + offset, framePeriod: frame)
            largestStep = max(largestStep, s.delay - previous)
            previous = s.delay
        }
        // Bursty link: the buffer grows to its cap, never past it, and only a few percent of
        // each display frame at a time (the playhead slows imperceptibly while it grows).
        #expect(s.delay <= s.config.maxDelay + 1e-9)
        #expect(s.delay > s.config.maxDelay * 0.9)
        #expect(largestStep <= s.config.delayRiseRate * frame + 1e-9)
    }

    @Test func bufferShrinksBackOnceTheLinkCalms() {
        let s = MotionScheduler()
        var t = 0.0
        func run(seconds: Double, late: (Int) -> Double) {
            let n = Int(seconds * 120)
            for k in 0..<n {
                s.enqueue([.move(dx: 1, dy: 0)], frameTime: t, arrival: t + offset + late(k), clockOffset: offset)
                _ = s.flush(now: t + offset, framePeriod: frame)
                t += frame
            }
        }
        run(seconds: 2) { $0 % 4 == 0 ? 0.05 : 0 }
        let bursty = s.delay
        #expect(bursty > 0.03)
        run(seconds: 1.5) { _ in 0.0005 }
        // Falls once the bursty frames leave the history, but slowly (at most
        // `delayFallRate`), so the playhead's catch-up is invisible...
        #expect(s.delay < bursty)
        #expect(bursty - s.delay <= s.config.delayFallRate * 1.5 + 1e-6)
        run(seconds: 5) { _ in 0.0005 }
        // ...and a clean link is back to almost nothing.
        #expect(s.delay < 0.001)
    }

    @Test func steadyLinkAddsAlmostNoDelay() {
        let s = MotionScheduler()
        for k in 0..<300 {
            let t = Double(k) * frame
            s.enqueue([.move(dx: 1, dy: 0)], frameTime: t, arrival: t + offset + 0.0002 * Double(k % 2), clockOffset: offset)
        }
        #expect(s.delay < 0.0005)
    }
}

@Suite @MainActor struct DisplaySyncedPipelineTests {
    func frame(_ seq: UInt32, _ t: TimeInterval, _ touches: [Touch]) -> TouchFrame {
        TouchFrame(seq: seq, timestamp: t, touches: touches, surface: CGSize(width: 390, height: 844))
    }

    @Test func eventsWaitForTheDisplayAndTheClockSleepsWhenIdle() {
        let (synth, poster) = makeSynth()
        let clock = ManualFrameClock()
        let pipeline = TouchPipeline(settings: .macDefault, synth: synth, frameClock: clock)
        pipeline.onDiagnostics = nil
        var local = 100.0
        pipeline.now = { local }
        var t = 10.0
        pipeline.process(frame(1, t, [Touch(id: 1, phase: .began, x: 100, y: 400)]))
        #expect(clock.isRunning)
        // Two touch frames per display frame (a 240 Hz sender): still one pointer event per frame.
        for i in 1...12 {
            t += 1.0 / 240; local += 1.0 / 240
            let before = poster.events.count
            pipeline.process(frame(UInt32(i + 1), t, [Touch(id: 1, phase: .moved, x: 100 + Double(i) * 5, y: 400)]))
            #expect(poster.events.count == before)      // nothing leaves between display frames
            if i % 2 == 0 {
                clock.fire()
                #expect(poster.events.count - before <= 1)
            }
        }
        #expect(poster.events.filter { $0.type == .mouseMoved }.count >= 4)
        t += 1.0 / 120; local += 1.0 / 120
        pipeline.process(frame(14, t, [Touch(id: 1, phase: .ended, x: 160, y: 400)]))
        for _ in 0..<(TouchPipeline.idleFramesBeforeStop + 5) {
            local += 1.0 / 120
            clock.fire()
        }
        #expect(!clock.isRunning)
        #expect(poster.events.filter { $0.type == .mouseMoved }.count >= 1)
    }

    @Test func momentumRunsOnDisplayFrames() {
        let (synth, poster) = makeSynth()
        let clock = ManualFrameClock()
        let pipeline = TouchPipeline(settings: .macDefault, synth: synth, frameClock: clock)
        pipeline.onDiagnostics = nil
        var local = 100.0
        pipeline.now = { local }
        var t = 10.0
        pipeline.process(frame(1, t, [Touch(id: 1, phase: .began, x: 150, y: 300), Touch(id: 2, phase: .began, x: 230, y: 300)]))
        for i in 1...10 {
            t += 1.0 / 120; local += 1.0 / 120
            let y = 300 + Double(i) * 12
            pipeline.process(frame(UInt32(i + 1), t, [Touch(id: 1, phase: .moved, x: 150, y: y), Touch(id: 2, phase: .moved, x: 230, y: y)]))
            clock.fire()
        }
        t += 1.0 / 120; local += 1.0 / 120
        pipeline.process(frame(12, t, [Touch(id: 1, phase: .ended, x: 150, y: 420), Touch(id: 2, phase: .ended, x: 230, y: 420)]))
        let before = poster.events.count
        for _ in 0..<30 { local += 1.0 / 120; clock.fire() }
        let momentum = poster.events[before...].filter { $0.type == .scrollWheel && int($0, .scrollWheelEventMomentumPhase) != 0 }
        // One momentum event per display frame once it starts.
        #expect(momentum.count >= 25 && momentum.count <= 30)
        pipeline.cancelAll()
        #expect(!clock.isRunning)
    }

    /// The display is asleep (the clock runs but never fires) and a quick tap's last frame
    /// arrives before the stall limit: the click must still go out on its own, not wait for the
    /// next touch.
    @Test func quickTapIsPostedWithNoDisplayFrames() async {
        let (synth, poster) = makeSynth()
        let clock = ManualFrameClock()
        let pipeline = TouchPipeline(settings: .macDefault, synth: synth, frameClock: clock)
        pipeline.onDiagnostics = nil
        let t = 10.0
        pipeline.process(frame(1, t, [Touch(id: 1, phase: .began, x: 100, y: 400)]))
        pipeline.process(frame(2, t + 0.03, [Touch(id: 1, phase: .ended, x: 100, y: 400)]))
        #expect(clock.isRunning)
        // Real time: the stall timer fires on its own; a busy CI machine can be slow to run it.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !poster.events.contains(where: { $0.type == .leftMouseUp }) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(poster.events.contains { $0.type == .leftMouseDown })
        #expect(poster.events.contains { $0.type == .leftMouseUp })
        pipeline.cancelAll()
    }

    @Test func displayStallFallsBackToImmediatePosting() {
        let (synth, poster) = makeSynth()
        let clock = ManualFrameClock()
        let pipeline = TouchPipeline(settings: .macDefault, synth: synth, frameClock: clock)
        pipeline.onDiagnostics = nil
        var local = 100.0
        pipeline.now = { local }
        var t = 10.0
        pipeline.process(frame(1, t, [Touch(id: 1, phase: .began, x: 100, y: 400)]))
        for i in 1...20 {        // the display never fires (asleep), frames keep coming
            t += 0.01; local += 0.01
            pipeline.process(frame(UInt32(i + 1), t, [Touch(id: 1, phase: .moved, x: 100 + Double(i) * 5, y: 400)]))
        }
        #expect(poster.events.contains { $0.type == .mouseMoved })
    }
}

@Suite struct TouchDiagnosticsTests {
    @Test func countsRateGapsLossAndLateness() {
        var d = TouchDiagnostics()
        var seq: UInt32 = 0
        for k in 0..<120 {
            seq += k == 50 ? 3 : 1                  // two packets lost
            d.frame(seq: seq, arrival: Double(k) / 120, lateness: k == 70 ? 0.02 : 0.001)
            d.displayFrame(outputEvents: 1)
        }
        #expect(d.summary(now: 0.5, bufferDelay: 0.003) == nil)       // window not over yet
        let summary = d.summary(now: 1.0, bufferDelay: 0.003)
        #expect(summary != nil)
        guard let s = summary else { return }
        #expect(s.frames == 120)
        #expect(s.lost == 2)
        #expect(abs(s.gapP50Ms - 8.333) < 0.01)
        #expect(abs(s.lateMaxMs - 20) < 1e-9)
        #expect(abs(s.lateP50Ms - 1) < 1e-9)
        #expect(s.line.hasPrefix("feel: 120 fps"))
        #expect(d.summary(now: 2, bufferDelay: 0) == nil)              // a fresh window starts empty
    }
}

@Suite struct ScrollSpeedPrefTests {
    @Test func scrollingSpeedIsReadAndDefaults() {
        var g = observedGlobal
        #expect(TrackpadPrefsReader.map(.init(trackpad: observedTrackpad, global: g)).scrollSpeed == TrackpadSettings.defaultScrollSpeed)
        g["com.apple.trackpad.scrolling"] = "0.5"
        #expect(TrackpadPrefsReader.map(.init(trackpad: observedTrackpad, global: g)).scrollSpeed == 0.5)
    }
}
