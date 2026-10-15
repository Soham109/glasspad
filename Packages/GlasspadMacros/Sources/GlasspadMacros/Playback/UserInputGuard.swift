import Foundation
import CoreGraphics

/// Decides whether an observed event means the user has taken over.
///
/// Ignored on purpose:
/// - events the macro itself posted (tagged with `MacroEventMarker`);
/// - key-ups, modifier changes and key auto-repeat, because the hotkey that
///   started the macro is usually still being released when playback begins;
/// - mouse-ups, for the same reason with a click that triggered it;
/// - mouse jitter below `movementThreshold` points in total.
public struct UserInputFilter: Sendable {
    public enum Observed: Sendable {
        case keyDown(isRepeat: Bool)
        case keyUp
        case flagsChanged
        case mouseDown
        case mouseUp
        case mouseMoved(CGPoint)
        case scroll
    }

    public var movementThreshold: Double
    private var moveOrigin: CGPoint?

    public init(movementThreshold: Double = 4) {
        self.movementThreshold = movementThreshold
    }

    public mutating func isUserInput(_ event: Observed, fromPlayback: Bool) -> Bool {
        if fromPlayback { return false }
        switch event {
        case .keyDown(let isRepeat): return !isRepeat
        case .keyUp, .flagsChanged, .mouseUp: return false
        case .mouseDown, .scroll: return true
        case .mouseMoved(let p):
            guard let origin = moveOrigin else { moveOrigin = p; return false }
            return hypot(p.x - origin.x, p.y - origin.y) >= movementThreshold
        }
    }
}

/// Real monitor: a listen-only event tap feeding `UserInputFilter`.
public final class EventTapUserInputMonitor: UserInputMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tap: ListenOnlyEventTap?
    private let threshold: Double

    public init(movementThreshold: Double = 4) {
        self.threshold = movementThreshold
    }

    public func start(onUserInput: @escaping @Sendable () -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        tap?.stop()
        let filter = LockedBox(UserInputFilter(movementThreshold: threshold))
        let fired = LockedBox(false)
        let newTap = ListenOnlyEventTap(types: [
            .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel,
        ]) { type, event in
            let observed: UserInputFilter.Observed
            switch type {
            case .keyDown: observed = .keyDown(isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
            case .keyUp: observed = .keyUp
            case .flagsChanged: observed = .flagsChanged
            case .leftMouseDown, .rightMouseDown, .otherMouseDown: observed = .mouseDown
            case .leftMouseUp, .rightMouseUp, .otherMouseUp: observed = .mouseUp
            case .scrollWheel: observed = .scroll
            default: observed = .mouseMoved(event.location)
            }
            let playback = event.isFromMacroPlayback
            if filter.update({ $0.isUserInput(observed, fromPlayback: playback) }),
               fired.update({ f -> Bool in defer { f = true }; return !f }) {
                onUserInput()
            }
        }
        guard newTap.start() else { return false }
        tap = newTap
        return true
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        tap?.stop()
        tap = nil
    }
}
