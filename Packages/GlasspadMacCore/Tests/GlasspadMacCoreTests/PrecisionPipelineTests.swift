import CoreGraphics
import Foundation
import GlasspadKit
import Testing
@testable import GlasspadMacCore

/// Pointer precision end to end: scripted phone frames through `TouchPipeline`, with a fake
/// display clock, measured from what the synthesizer posts. Nothing reaches the live session.
@Suite @MainActor struct PrecisionPipelineTests {
    static let sample = 1.0 / 120          // phone touch rate
    static let display = 1.0 / 120         // display refresh
    static let offset = 50.0               // local = phone + 50 s + network

    struct Posted { var t: Double; var dx: Double; var type: CGEventType }

    /// One phone frame of a scripted single finger.
    struct Step { var x: Double; var y: Double; var radius: Double; var phase: TouchPhase }

    /// Runs `steps` (one every `sample`, from phone time 10) through a pipeline, with or
    /// without the display clock, and returns what was posted with local post times.
    func run(_ steps: [Step], clocked: Bool, network: (Int) -> Double = { $0 % 3 == 0 ? 0.004 : 0.001 }) -> [Posted] {
        let (synth, poster) = makeSynth()
        let clock = ManualFrameClock()
        let pipeline = TouchPipeline(settings: .macDefault, synth: synth, frameClock: clocked ? clock : nil)
        pipeline.onDiagnostics = nil
        var local = 0.0
        pipeline.now = { local }
        // Arrivals and display frames on one local timeline, in order.
        var timeline: [(t: Double, frame: Int?)] = steps.indices.map { i in
            (10 + Double(i) * Self.sample + Self.offset + network(i), i)
        }
        let end = timeline.last!.t + 0.2
        var v = 10 + Self.offset + 0.003
        while v < end { timeline.append((v, nil)); v += Self.display }
        timeline.sort { $0.t < $1.t }
        var posted: [Posted] = []
        var seen = 0
        for item in timeline {
            local = item.t
            if let i = item.frame {
                let s = steps[i]
                let touch = Touch(id: 1, phase: s.phase, x: s.x, y: s.y, majorRadius: s.radius)
                pipeline.process(TouchFrame(seq: UInt32(i + 1), timestamp: 10 + Double(i) * Self.sample, touches: [touch],
                                            surface: CGSize(width: 390, height: 844)))
            } else if clocked {
                clock.fire(period: Self.display)
            }
            while seen < poster.events.count {
                let e = poster.events[seen]
                posted.append(Posted(t: local, dx: Double(e.location.x) - 500, type: e.type))
                seen += 1
            }
        }
        return posted
    }

    /// Lands with a 2 pt wobble and a growing radius, then moves at `mmPerSecond` along x.
    func deliberateMove(mmPerSecond: Double, frames: Int) -> [Step] {
        var steps: [Step] = [Step(x: 100, y: 400, radius: 13, phase: .began)]
        for (dx, r) in [(1.2, 18.0), (0.8, 22.0), (-0.5, 22.0)] {
            let last = steps.last!
            steps.append(Step(x: last.x + dx, y: last.y + 0.6, radius: r, phase: .moved))
        }
        let perFrame = GlasspadKit.GestureTuning.points(mm: mmPerSecond) / 120
        for _ in 0..<frames {
            let last = steps.last!
            steps.append(Step(x: last.x + perFrame, y: last.y, radius: 22, phase: .moved))
        }
        return steps
    }

    func position(_ p: [Posted], at t: Double) -> Double {
        p.filter { $0.type == .mouseMoved && $0.t <= t + 1e-9 }.reduce(0) { $0 + $1.dx }
    }

    @Test func displaySyncAddsAtMostOneFrameAtTheStartOfAMove() {
        for speed in [20.0, 40.0, 80.0] {
            let steps = deliberateMove(mmPerSecond: speed, frames: 40)
            let immediate = run(steps, clocked: false)
            let synced = run(steps, clocked: true)
            let firstImmediate = immediate.first { $0.type == .mouseMoved && abs($0.dx) > 0.01 }!.t
            let firstSynced = synced.first { $0.type == .mouseMoved && abs($0.dx) > 0.01 }!.t
            // The buffer adds its delay plus at most one display frame of waiting.
            #expect(firstSynced - firstImmediate <= Self.display + 0.0045, "\(speed) mm/s: \((firstSynced - firstImmediate) * 1000) ms")
            // From then on the synced pointer is never more than two frames behind where the
            // immediate one was (one sample interval of spreading plus display quantisation).
            func lag(at t: Double) -> Double {
                let have = position(synced, at: t)
                var l = 0.0
                while l < 0.1, position(immediate, at: t - l) > have + 1e-6 { l += 0.0005 }
                return l
            }
            let ticks = stride(from: firstImmediate, to: firstImmediate + 0.25, by: Self.display / 4).map { $0 }
            let start = ticks.filter { $0 < firstImmediate + 0.05 }.map(lag).max() ?? 0
            let steady = ticks.filter { $0 >= firstImmediate + 0.1 }.map(lag).max() ?? 0
            #expect(start <= steady + 0.001, "\(speed) mm/s: start \(start * 1000) ms vs steady \(steady * 1000) ms")
            #expect(steady <= 2.5 * Self.display)
            // Nothing lost or invented.
            #expect(abs(position(synced, at: .infinity) - position(immediate, at: .infinity)) < 1e-6)
            // The hysteresis is short: the pointer starts within 35 ms of the finger.
            let fingerStart = 10 + 4 * Self.sample + Self.offset
            #expect(firstSynced - fingerStart <= 0.035 + Self.display, "\(speed) mm/s start \((firstSynced - fingerStart) * 1000) ms")
        }
    }

    @Test func noisyTapThroughTheDisplayPathPostsOnlyTheClick() {
        // Wobble on landing, a short rest, a 5 pt roll with the radius shrinking, lift.
        var steps: [Step] = [Step(x: 200, y: 400, radius: 13, phase: .began)]
        for (dx, dy, r) in [(1.5, 1.0, 18.0), (1.0, 0.5, 22.0), (-0.6, -0.3, 22.0), (0, 0, 22), (0, 0, 22)] {
            let l = steps.last!
            steps.append(Step(x: l.x + dx, y: l.y + dy, radius: r, phase: .moved))
        }
        for k in 1...5 {
            let l = steps.last!
            steps.append(Step(x: l.x - 1, y: l.y + 0.3, radius: 22 - Double(k) * 2.2, phase: k == 5 ? .ended : .moved))
        }
        let posted = run(steps, clocked: true)
        #expect(posted.filter { $0.type == .mouseMoved }.allSatisfy { abs($0.dx) < 1e-9 })
        #expect(posted.map(\.type).filter { $0 != .mouseMoved } == [.leftMouseDown, .leftMouseUp])
    }
}
