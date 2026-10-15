import CoreGraphics
import Foundation

/// Every gesture that has a native (private event) path and/or a fallback.
public enum SynthGesture: String, CaseIterable, Sendable, Codable {
    case magnify, rotate, smartMagnify, navigate
    case spaces, missionControl, appExpose, launchpad, showDesktop
    case lookUp, forceClick, notificationCenter

    public var displayName: String {
        switch self {
        case .magnify: "Pinch to zoom"
        case .rotate: "Rotate"
        case .smartMagnify: "Smart zoom"
        case .navigate: "Swipe between pages"
        case .spaces: "Swipe between spaces"
        case .missionControl: "Mission Control"
        case .appExpose: "App Exposé"
        case .launchpad: "Launchpad"
        case .showDesktop: "Show Desktop"
        case .lookUp: "Look Up"
        case .forceClick: "Force click"
        case .notificationCenter: "Notification Center"
        }
    }

    /// True when Glasspad has a private-event implementation for this gesture at all.
    public var hasNativePath: Bool {
        switch self {
        case .lookUp, .forceClick, .notificationCenter: false
        default: true
        }
    }

    /// True when a public fallback exists (SPEC section 7).
    public var hasFallback: Bool {
        switch self {
        case .rotate, .smartMagnify: false
        default: true
        }
    }
}

public enum SynthMode: String, Sendable, Codable, Equatable {
    case native, fallback, unavailable
}

/// Decides native vs fallback per gesture. `selfCheck()` runs once at launch: for each gesture
/// with a native path it builds the private event(s) and checks the private fields read back
/// exactly. If the event cannot be created (a future macOS could refuse type 29/30) the gesture
/// switches to its fallback, and the menu says so.
public struct SynthCapabilities: Sendable, Equatable {
    public private(set) var modes: [SynthGesture: SynthMode]

    public init(modes: [SynthGesture: SynthMode]) { self.modes = modes }

    public func mode(for g: SynthGesture) -> SynthMode { modes[g] ?? .unavailable }

    /// Forces a gesture onto its fallback (or unavailable when it has none).
    public mutating func forceFallback(_ g: SynthGesture) {
        modes[g] = g.hasFallback ? .fallback : .unavailable
    }

    /// Pure selection rule, unit tested: native when the probe passes, else fallback when one
    /// exists, else unavailable.
    public static func select(probe: (SynthGesture) -> Bool) -> SynthCapabilities {
        var m: [SynthGesture: SynthMode] = [:]
        for g in SynthGesture.allCases {
            if g.hasNativePath, probe(g) { m[g] = .native }
            else if g.hasFallback { m[g] = .fallback }
            else { m[g] = .unavailable }
        }
        return SynthCapabilities(modes: m)
    }

    /// Builds (never posts) each native event and verifies its private fields.
    public static func selfCheck() -> SynthCapabilities {
        select(probe: probeNative)
    }

    static func probeNative(_ g: SynthGesture) -> Bool {
        let builder = GestureEventBuilder(source: nil)
        let location = CGPoint(x: 10, y: 10)
        switch g {
        case .magnify:
            guard let e = builder.magnify(delta: 0.125, phase: .changed, at: location) else { return false }
            return e.type.rawValue == CGSEventKind.gesture.rawValue
                && e.get(.gestureHIDType) == HIDEventType.zoom.rawValue
                && e.getDouble(.gestureZoomValue) == 0.125
                && e.get(.gesturePhase) == HIDPhase.changed.rawValue
        case .rotate:
            guard let e = builder.rotate(degrees: 15, phase: .changed, at: location) else { return false }
            return e.type.rawValue == CGSEventKind.gesture.rawValue
                && e.get(.gestureHIDType) == HIDEventType.rotation.rawValue
                && e.getDouble(.gestureRotationValue) == 15
        case .smartMagnify:
            guard let e = builder.smartMagnify(at: location) else { return false }
            return e.get(.gestureHIDType) == HIDEventType.zoomToggle.rawValue
        case .navigate:
            let es = builder.navigationSwipe(direction: .left, at: location)
            return es.count == 2 && es[0].get(.gestureSwipeValue) == HIDSwipe.left.rawValue
                && es[0].get(.gestureHIDType) == HIDEventType.navigationSwipe.rawValue
        case .spaces, .missionControl, .appExpose, .launchpad, .showDesktop:
            let motion: DockSwipeMotion = g == .spaces ? .horizontal : (g == .launchpad || g == .showDesktop ? .pinch : .vertical)
            let es = builder.dockSwipe(motion: motion, originOffset: 0.25, phase: .changed, exitSpeed: nil, invertedFromDevice: false, at: location)
            guard es.count == 2 else { return false }
            let dock = es[1]
            return es[0].type.rawValue == CGSEventKind.gesture.rawValue
                && dock.type.rawValue == CGSEventKind.dockControl.rawValue
                && dock.get(.gestureHIDType) == HIDEventType.dockSwipe.rawValue
                && dock.get(.dockSwipeMotion) == motion.rawValue
                && dock.getDouble(.dockSwipeOriginOffset) == 0.25
        case .lookUp, .forceClick, .notificationCenter:
            return false
        }
    }

    /// Text for the menu, one line per gesture.
    public var summary: [(gesture: SynthGesture, mode: SynthMode)] {
        SynthGesture.allCases.map { ($0, mode(for: $0)) }
    }
}
