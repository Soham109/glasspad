import Foundation
import GlasspadKit

/// Touch frames in, CGEvents out: GestureRecognizer feeding EventSynthesizer, plus the haptic
/// hints that only the Mac can know (a Space actually snapped into place). The phone runs its
/// own recognizer for instant click haptics, so recognizer haptics are not echoed back.
@MainActor
public final class TouchPipeline {
    public let recognizer: GestureRecognizer
    public let synth: EventSynthesizer
    /// Mac -> phone haptic hints.
    public var onHaptic: ((HapticKind) -> Void)?

    private var tickTimer: DispatchSourceTimer?
    /// Tick period while the recognizer has work (momentum, tap timeouts), per GestureRecognizer docs.
    public static let tickInterval: TimeInterval = 0.008

    public init(settings: TrackpadSettings, synth: EventSynthesizer) {
        self.recognizer = GestureRecognizer(settings: settings)
        self.synth = synth
        synth.settings = settings
        // Dock-level transitions (Spaces, Mission Control, ...) snap; the phone plays a sharp tick.
        synth.onSwipeCompleted = { [weak self] _ in self?.onHaptic?(.snap) }
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
        synth.handle(recognizer.process(frame))
        scheduleTicks()
    }

    public func tick(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        synth.handle(recognizer.tick(now: now))
        if !recognizer.needsTick { stopTicks() }
    }

    /// Link dropped: release buttons, end gestures, stop momentum.
    public func cancelAll() {
        synth.handle(recognizer.cancelAll())
        synth.reset()
        stopTicks()
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
