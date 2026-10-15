import AppKit
import CoreGraphics

/// Something the synthesizer asks the system to do that is not a CGEvent.
public enum SystemAction: Equatable, Sendable {
    case openApplication(URL)
    case runAppleScript(String)
}

/// Where synthesized events go. The live poster sends them into the session; tests use
/// `CapturingEventPoster` and only inspect fields, never posting anything.
public protocol EventPoster: AnyObject {
    func post(_ event: CGEvent, tap: CGEventTapLocation, after delay: TimeInterval)
    func perform(_ action: SystemAction)
}

public extension EventPoster {
    func post(_ event: CGEvent, tap: CGEventTapLocation = .cghidEventTap) {
        post(event, tap: tap, after: 0)
    }
}

/// Posts into the live session. Only the app uses this, never tests.
public final class LiveEventPoster: EventPoster {
    public init() {}

    public func post(_ event: CGEvent, tap: CGEventTapLocation, after delay: TimeInterval) {
        if delay <= 0 {
            event.post(tap: tap)
            return
        }
        nonisolated(unsafe) let e = event
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { e.post(tap: tap) }
    }

    public func perform(_ action: SystemAction) {
        switch action {
        case .openApplication(let url):
            NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
        case .runAppleScript(let source):
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", source]
            try? p.run()
        }
    }
}

/// Records everything instead of posting. Used by tests and by self-checks.
public final class CapturingEventPoster: EventPoster {
    public struct Posted {
        public let event: CGEvent
        public let tap: CGEventTapLocation
        public let delay: TimeInterval
    }
    public private(set) var posted: [Posted] = []
    public private(set) var actions: [SystemAction] = []

    public init() {}

    public var events: [CGEvent] { posted.map(\.event) }

    public func post(_ event: CGEvent, tap: CGEventTapLocation, after delay: TimeInterval) {
        posted.append(Posted(event: event, tap: tap, delay: delay))
    }

    public func perform(_ action: SystemAction) { actions.append(action) }

    public func reset() {
        posted.removeAll()
        actions.removeAll()
    }
}
