import AppKit
import QuartzCore

/// Something that calls back once per display frame while running.
@MainActor
public protocol FrameClock: AnyObject {
    /// Called on the main thread each frame with the display's frame period in seconds.
    var onFrame: ((_ framePeriod: TimeInterval) -> Void)? { get set }
    var isRunning: Bool { get }
    func start()
    func stop()
}

/// The display's own refresh (`NSScreen.displayLink`, macOS 14+), at the screen's real rate:
/// 120 Hz on a ProMotion display while the pointer moves. Follows the screen under the pointer
/// each time it starts. Falls back to a 120 Hz timer if no display link can be made.
@MainActor
public final class DisplayFrameClock: FrameClock {
    public var onFrame: ((TimeInterval) -> Void)?
    public private(set) var isRunning = false
    private var link: CADisplayLink?
    private var timer: DispatchSourceTimer?
    private var target: Target?

    public init() {}

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        if let screen {
            let t = Target { [weak self] link in self?.fire(link) }
            let l = screen.displayLink(target: t, selector: #selector(Target.tick(_:)))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            l.add(to: .main, forMode: .common)
            target = t
            link = l
            return
        }
        let s = DispatchSource.makeTimerSource(queue: .main)
        s.schedule(deadline: .now(), repeating: 1.0 / 120, leeway: .microseconds(500))
        s.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.onFrame?(1.0 / 120) } }
        s.resume()
        timer = s
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        link?.invalidate()
        link = nil
        target = nil
        timer?.cancel()
        timer = nil
    }

    private func fire(_ link: CADisplayLink) {
        let period = link.targetTimestamp - link.timestamp
        onFrame?(period > 0.001 && period < 0.1 ? period : link.duration)
    }

    /// CADisplayLink retains its target; this box keeps the clock out of that cycle.
    private final class Target: NSObject {
        let action: @MainActor (CADisplayLink) -> Void
        init(_ action: @escaping @MainActor (CADisplayLink) -> Void) { self.action = action }
        @MainActor @objc func tick(_ link: CADisplayLink) { action(link) }
    }
}

/// A clock tests drive by hand.
@MainActor
public final class ManualFrameClock: FrameClock {
    public var onFrame: ((TimeInterval) -> Void)?
    public private(set) var isRunning = false
    public private(set) var starts = 0
    public init() {}
    public func start() { if !isRunning { isRunning = true; starts += 1 } }
    public func stop() { isRunning = false }
    /// Fires one frame (only while running, like a real display link).
    public func fire(period: TimeInterval = 1.0 / 120) { if isRunning { onFrame?(period) } }
}
