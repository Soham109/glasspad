import GlasspadKit
import QuartzCore
import SwiftUI
import UIKit

/// The trackpad: just the surface and finger dots. Touches go to the Mac immediately;
/// the same gesture recognizer the Mac runs also runs here, only to fire haptics without
/// waiting for the network.
struct TrackpadScreen: View {
    @Environment(\.palette) private var palette
    var settings = PhoneSettings.shared
    var session = MacSession.shared
    var router = AppRouter.shared
    var tuning = TrackpadTuningStore.shared

    var body: some View {
        SurfaceRepresentable(palette: palette, showsDots: settings.showDots, isDimmed: router.isDimmed,
                             trackpadSettings: tuning.merged(session.trackpadSettings))
            .ignoresSafeArea()
            .onAppear { session.setTrackpadVisible(true) }
            .onDisappear { session.setTrackpadVisible(false) }
    }
}

private struct SurfaceRepresentable: UIViewRepresentable {
    let palette: Palette
    let showsDots: Bool
    let isDimmed: Bool
    let trackpadSettings: TrackpadSettings

    func makeCoordinator() -> TrackpadDriver { TrackpadDriver(settings: trackpadSettings) }

    func makeUIView(context: Context) -> TrackpadSurfaceView {
        let view = TrackpadSurfaceView()
        let driver = context.coordinator
        view.onFrame = { [weak driver] frame in driver?.handle(frame) }
        view.onWake = { AppRouter.shared.noteActivity() }
        driver.surface = view
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-GPDemoTouches") { DemoTouches.run(on: view) }
        #endif
        return view
    }

    func updateUIView(_ view: TrackpadSurfaceView, context: Context) {
        if view.palette != palette { view.palette = palette }
        if view.showsDots != showsDots { view.showsDots = showsDots }
        view.isDimmed = isDimmed
        context.coordinator.update(settings: trackpadSettings)
        // Settings from the Mac carry its copy of the phone's tuning; resend ours if it differs.
        TrackpadTuningStore.shared.macSettingsArrived(MacSession.shared.trackpadSettings)
    }

    static func dismantleUIView(_ view: TrackpadSurfaceView, coordinator: TrackpadDriver) {
        view.cancelAllTouches()
        coordinator.stop()
    }
}

/// Sends frames, runs the local recognizer and turns its output into haptics.
@MainActor
final class TrackpadDriver {
    weak var surface: TrackpadSurfaceView?
    private let recognizer: GestureRecognizer
    private var displayLink: CADisplayLink?
    private var pendingHaptics: [HapticKind] = []

    init(settings: TrackpadSettings) {
        recognizer = GestureRecognizer(settings: settings)
        // UIKit sends nothing for a resting finger, so the stale-link guard must be off here.
        recognizer.staleTouchTimeout = nil
        recognizer.onHaptic = { [weak self] kind in
            MainActor.assumeIsolated { self?.pendingHaptics.append(kind) }
        }
    }

    func update(settings: TrackpadSettings) {
        if recognizer.settings != settings { recognizer.settings = settings }
    }

    func handle(_ frame: TouchFrame) {
        MacSession.shared.send(frame: frame)
        SetupGuide.shared.note(frame)
        AppRouter.shared.noteActivity()
        play(recognizer.process(frame))
        scheduleTicks()
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        _ = recognizer.cancelAll()
        pendingHaptics = []
    }

    /// Hold timers (force click) and deferred taps need ticks about every 8 ms while active.
    private func scheduleTicks() {
        guard recognizer.needsTick, displayLink == nil else { return }
        let link = CADisplayLink(target: DisplayLinkTarget { [weak self] in self?.tick() }, selector: #selector(DisplayLinkTarget.fire))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func tick() {
        play(recognizer.tick(now: ProcessInfo.processInfo.systemUptime))
        if !recognizer.needsTick {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    /// Force click gets its own shape: a ramp at stage 1 and a sharp tick at stage 2.
    /// Everything else maps one to one. The recognizer only reports clicks, force click stages
    /// and drag lock; anything else is ignored here too, so no swipe or scroll ever buzzes.
    private func play(_ events: [GestureEvent]) {
        let haptics = pendingHaptics
        pendingHaptics = []
        guard !haptics.isEmpty else { return }
        var stage1 = false, stage2 = false
        for event in events {
            if case .forceClick(let stage) = event {
                if stage == 1 { stage1 = true } else { stage2 = true }
            }
        }
        let session = MacSession.shared
        if stage1 {
            Haptics.shared.play(.forceClickRamp)
            session.noteLocalHaptic(.click)
            session.noteLocalHaptic(.forceClick)
        }
        if stage2 {
            Haptics.shared.play(.forceClickDeep)
            session.noteLocalHaptic(.forceClick)
        }
        for kind in haptics {
            if stage1 && kind == .click { continue }
            if stage2 && kind == .forceClick { continue }
            guard kind == .click || kind == .forceClick || kind == .dragLock else { continue }
            Haptics.shared.play(HapticCue(kind))
            session.noteLocalHaptic(kind)
        }
    }
}

/// CADisplayLink retains its target; this small box keeps the driver out of that cycle.
private final class DisplayLinkTarget: NSObject {
    let action: @MainActor () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    @MainActor @objc func fire() { action() }
}

#if DEBUG
/// Debug builds only: a scripted two finger scroll, then two fingers held still, so a
/// simulator run sends real frames to the Mac and shows the dots. With -GPDemoRotate the
/// screen then turns under the held fingers.
@MainActor
private enum DemoTouches {
    static func run(on view: TrackpadSurfaceView) {
        let a = NSObject(), b = NSObject()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            let w = view.bounds.width, h = view.bounds.height
            for step in 0...40 {
                // Travels 30% of the height, so it reads the same in either orientation.
                let y = h * 0.62 - CGFloat(step) * h * 0.3 / 40
                let phase: TouchPhase = step == 0 ? .began : .moved
                view.debugInject([(a, CGPoint(x: w * 0.38, y: y), phase), (b, CGPoint(x: w * 0.62, y: y + 18), phase)])
                try? await Task.sleep(for: .milliseconds(8))
            }
            // -GPDemoRotate: turn the screen while both fingers are still down, to check
            // that the Mac sees them cancelled instead of stuck.
            if ProcessInfo.processInfo.arguments.contains("-GPDemoRotate") {
                try? await Task.sleep(for: .seconds(1))
                let settings = PhoneSettings.shared
                settings.orientation = OrientationLock.current.isLandscape ? .portrait : .landscape
            }
        }
    }
}
#endif
