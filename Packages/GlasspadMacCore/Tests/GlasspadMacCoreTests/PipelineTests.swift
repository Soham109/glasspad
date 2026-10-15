import CoreGraphics
import Foundation
import GlasspadKit
import Testing
@testable import GlasspadMacCore

@Suite @MainActor struct PipelineTests {
    func frame(_ seq: UInt32, _ t: TimeInterval, _ touches: [Touch]) -> TouchFrame {
        TouchFrame(seq: seq, timestamp: t, touches: touches, surface: CGSize(width: 390, height: 844))
    }

    @Test func oneFingerSlideMovesPointerWithoutPosting() {
        let (synth, poster) = makeSynth()
        let pipeline = TouchPipeline(settings: .macDefault, synth: synth)
        pipeline.recognizer.clock = { 0 }
        var t = 0.0
        var seq: UInt32 = 0
        var events: [CGEvent] = []
        pipeline.process(frame(seq, t, [Touch(id: 1, phase: .began, x: 100, y: 400)]))
        for i in 1...20 {
            seq += 1; t += 0.008
            let now = t
            pipeline.recognizer.clock = { now }
            pipeline.process(frame(seq, t, [Touch(id: 1, phase: .moved, x: 100 + Double(i) * 6, y: 400)]))
        }
        seq += 1; t += 0.008
        pipeline.process(frame(seq, t, [Touch(id: 1, phase: .ended, x: 220, y: 400)]))
        pipeline.cancelAll()
        events = poster.events
        let moves = events.filter { $0.type == .mouseMoved }
        #expect(!moves.isEmpty)
        #expect(moves.allSatisfy { $0.location.x >= 500 })
    }

    @Test func swipeCompletionSendsSnapHaptic() {
        let (synth, _) = makeSynth()
        let pipeline = TouchPipeline(settings: .macDefault, synth: synth)
        var haptics: [HapticKind] = []
        pipeline.onHaptic = { haptics.append($0) }
        synth.handle([.swipe(.spaces, progress: 0.2, phase: .began), .swipe(.spaces, progress: 0.9, phase: .ended)])
        #expect(haptics == [.snap])
    }

    @Test func settingsPropagateToRecognizerAndSynth() {
        let (synth, _) = makeSynth()
        let pipeline = TouchPipeline(settings: .macDefault, synth: synth)
        var s = TrackpadSettings.macDefault
        s.naturalScrolling = false
        pipeline.settings = s
        #expect(pipeline.recognizer.settings == s)
        #expect(synth.settings == s)
    }
}
