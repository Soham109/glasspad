import ApplicationServices
import Foundation
import GlasspadKit
import QuartzCore

/// Touch frames in, CGEvents out: GestureRecognizer feeding EventSynthesizer.
///
/// With a `FrameClock` (the app passes `DisplayFrameClock`), output is display synced: the
/// recognizer's events go through `MotionScheduler` and leave at display frames, smoothed by a
/// jitter buffer of at most one frame, and recognizer ticks (momentum, hold timers) run once per
/// display frame too. Without one (tests), events are posted as soon as each frame arrives and
/// ticks run from an 8 ms timer, which is how it used to work.
///
/// Haptics: the phone runs its own recognizer and plays every trackpad haptic itself, so the
/// Mac sends none (Spaces and Mission Control no longer buzz either). `onHaptic` stays for callers.
@MainActor
public final class TouchPipeline {
    public let recognizer: GestureRecognizer
    public let synth: EventSynthesizer
    public let scheduler = MotionScheduler()
    /// Mac -> phone haptic hints. Nothing is sent today (see the type's doc comment).
    public var onHaptic: ((HapticKind) -> Void)?
    /// The local clock (same base as the display link and `systemUptime`).
    public var now: () -> TimeInterval = { CACurrentMediaTime() }
    public private(set) var diagnostics = TouchDiagnostics()
    /// Called with each one-second summary of the touch stream; the default writes it to GPLog.
    public var onDiagnostics: ((TouchDiagnostics.Summary) -> Void)? = { GPLog.log($0.line) }

    private let frameClock: FrameClock?
    private var tickTimer: DispatchSourceTimer?
    /// Idle display frames before the frame clock stops (about half a second at 120 Hz).
    static let idleFramesBeforeStop = 60
    private var idleFrames = 0
    private var lastDisplayFrame: TimeInterval?
    /// If the display stops calling back (asleep, lid closed) for this long while frames keep
    /// arriving, events are posted straight away instead of waiting.
    static let displayStallLimit: TimeInterval = 0.05
    /// Tick period while the recognizer has work (momentum, tap timeouts), without a frame clock.
    public static let tickInterval: TimeInterval = 0.008

    public init(settings: TrackpadSettings, synth: EventSynthesizer, frameClock: FrameClock? = nil) {
        self.recognizer = GestureRecognizer(settings: settings)
        self.synth = synth
        self.frameClock = frameClock
        synth.settings = settings
        frameClock?.onFrame = { [weak self] period in self?.displayFrame(period: period) }
    }

    public var settings: TrackpadSettings {
        get { recognizer.settings }
        set {
            recognizer.settings = newValue
            synth.settings = newValue
        }
    }

    public func setDisplayWidth(_ width: Double) {
        if width > 0 { recognizer.displayWidth = width }
    }

    public func process(_ frame: TouchFrame) {
        let arrival = now()
        let events = recognizer.process(frame, receivedAt: arrival)
        let offset = recognizer.learnedClockOffset ?? (arrival - frame.timestamp)
        diagnostics.frame(seq: frame.seq, arrival: arrival, lateness: arrival - (frame.timestamp + offset))
        if let clock = frameClock {
            scheduler.enqueue(events, frameTime: frame.timestamp, arrival: arrival, clockOffset: offset)
            idleFrames = 0
            if !clock.isRunning {
                clock.start()
                lastDisplayFrame = arrival
            } else if let last = lastDisplayFrame, arrival - last > Self.displayStallLimit {
                synth.handle(scheduler.drain())
                synth.handle(recognizer.tick(now: arrival))
            }
        } else {
            synth.handle(events)
            scheduleTicks()
        }
        if let s = diagnostics.summary(now: arrival, bufferDelay: scheduler.delay) { onDiagnostics?(s) }
    }

    /// One display frame: release what is due, then run the recognizer's timers on the same
    /// (delayed) timeline.
    func displayFrame(period: TimeInterval) {
        let t = now()
        lastDisplayFrame = t
        var out = scheduler.flush(now: t, framePeriod: period)
        out += recognizer.tick(now: scheduler.tickTime(at: t))
        synth.handle(out)
        diagnostics.displayFrame(outputEvents: out.count)
        if scheduler.hasPending || recognizer.needsTick {
            idleFrames = 0
        } else {
            idleFrames += 1
            if idleFrames >= Self.idleFramesBeforeStop { frameClock?.stop() }
        }
    }

    /// Without a frame clock: drive recognizer timers directly.
    public func tick(now: TimeInterval? = nil) {
        synth.handle(recognizer.tick(now: now ?? self.now()))
        if !recognizer.needsTick { stopTicks() }
    }

    /// Link dropped: release buttons, end gestures, stop momentum.
    public func cancelAll() {
        synth.handle(scheduler.drain())
        synth.handle(recognizer.cancelAll())
        synth.reset()
        scheduler.reset()
        stopTicks()
        frameClock?.stop()
    }

    private func scheduleTicks() {
        guard recognizer.needsTick, tickTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + Self.tickInterval, repeating: Self.tickInterval, leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.resume()
        tickTimer = t
    }

    private func stopTicks() {
        tickTimer?.cancel()
        tickTimer = nil
    }
}
