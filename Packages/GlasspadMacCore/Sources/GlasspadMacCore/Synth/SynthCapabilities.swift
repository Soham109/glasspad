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

/// What the user wants for one gesture (Settings > Gestures), stored per gesture.
///
/// Why it exists: the native path uses private gesture events. A macOS update can stop the Dock
/// or WindowServer acting on them, and nothing short of posting one and watching the screen can
/// tell (Glasspad never posts events to check). Then a gesture silently does nothing, and this
/// switch is the user's way out without a new build.
public enum GesturePreference: String, CaseIterable, Sendable, Codable {
    /// Native when the self-check passes, else the keyboard shortcut.
    case automatic
    /// Always the private gesture event (when Glasspad has one), even if the self-check failed.
    case native
    /// Always the public fallback (a keyboard shortcut or menu action), when there is one.
    case keyboardShortcut

    public var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .native: "Native"
        case .keyboardShortcut: "Keyboard shortcut"
        }
    }

    /// The choices that make sense for a gesture (a gesture with only one path has no choice).
    public static func options(for g: SynthGesture) -> [GesturePreference] {
        guard g.hasNativePath, g.hasFallback else { return [.automatic] }
        return allCases
    }
}

/// The per-gesture overrides, read from and written to the Mac app's preferences.
public struct GesturePreferences: Equatable, Sendable {
    public static let defaultsKey = "synth.gesturePreferences"
    public private(set) var values: [SynthGesture: GesturePreference] = [:]

    public init(_ values: [SynthGesture: GesturePreference] = [:]) {
        for (g, p) in values { set(p, for: g) }
    }

    public func preference(for g: SynthGesture) -> GesturePreference { values[g] ?? .automatic }

    /// Choices a gesture cannot honour are stored as automatic.
    public mutating func set(_ p: GesturePreference, for g: SynthGesture) {
        values[g] = GesturePreference.options(for: g).contains(p) && p != .automatic ? p : nil
    }

    /// Unknown gestures or values (from a newer build) are ignored.
    public static func load(from defaults: UserDefaults = .standard) -> GesturePreferences {
        guard let raw = defaults.dictionary(forKey: defaultsKey) as? [String: String] else { return GesturePreferences() }
        var out = GesturePreferences()
        for (k, v) in raw {
            guard let g = SynthGesture(rawValue: k), let p = GesturePreference(rawValue: v) else { continue }
            out.set(p, for: g)
        }
        return out
    }

    public func save(to defaults: UserDefaults = .standard) {
        let raw = Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value.rawValue) })
        if raw.isEmpty { defaults.removeObject(forKey: Self.defaultsKey) } else { defaults.set(raw, forKey: Self.defaultsKey) }
    }
}

/// Decides native vs fallback per gesture. `selfCheck()` runs once at launch: for each gesture
/// with a native path it builds the private event(s) for every phase the gesture uses and checks
/// the private fields read back exactly. Type-29 gesture events (zoom, rotate, smart zoom,
/// page swipe) are also serialised with CGEventCreateData and read back, and the copy must
/// still carry the fields. If an event cannot be created or a field does not survive (a future
/// macOS could refuse type 29/30 or change a field) the gesture switches to its fallback, and the
/// menu says so. The user's `GesturePreferences` are applied last.
///
/// Limits: all of this runs without posting anything, so it cannot tell whether the Dock still
/// acts on an event that builds correctly. A macOS that quietly ignores the events passes the
/// check; that case is what the per-gesture "Keyboard shortcut" override is for. Dock swipe
/// events (type 30) cannot be checked by serialising: CGEventCreateData does not carry their
/// fields even today (measured on macOS 26), so for them only the in-memory check applies.
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

    /// The user's overrides on top of what the self-check found. "Native" is honoured even when
    /// the check failed (the user knows the gesture works on their Mac); "Keyboard shortcut"
    /// always wins when the gesture has one.
    public func applying(_ prefs: GesturePreferences) -> SynthCapabilities {
        var out = self
        for g in SynthGesture.allCases {
            switch prefs.preference(for: g) {
            case .automatic: break
            case .native: if g.hasNativePath { out.modes[g] = .native }
            case .keyboardShortcut: if g.hasFallback { out.modes[g] = .fallback }
            }
        }
        return out
    }

    /// Builds (never posts) each native event and verifies its private fields, then applies the
    /// user's per-gesture preferences (read from the app's preferences by default).
    public static func selfCheck(preferences: GesturePreferences = .load()) -> SynthCapabilities {
        select(probe: probeNative).applying(preferences)
    }

    static func probeNative(_ g: SynthGesture) -> Bool {
        probeNative(g, transport: roundTrip)
    }

    /// `transport` stands for the trip to the WindowServer (tests pass one that drops fields).
    static func probeNative(_ g: SynthGesture, transport: (CGEvent) -> CGEvent?) -> Bool {
        let builder = GestureEventBuilder(source: nil)
        let location = CGPoint(x: 10, y: 10)
        /// The check passes on the event as built and on its serialised copy.
        func both(_ e: CGEvent?, _ check: (CGEvent) -> Bool) -> Bool {
            guard let e, check(e), let copy = transport(e) else { return false }
            return check(copy)
        }
        /// Dock swipe events: built and read back in memory only (see the type's note).
        func built(_ e: CGEvent?, _ check: (CGEvent) -> Bool) -> Bool {
            guard let e else { return false }
            return check(e)
        }
        let phases: [HIDPhase] = [.began, .changed, .ended]
        switch g {
        case .magnify:
            return phases.allSatisfy { phase in
                both(builder.magnify(delta: 0.125, phase: phase, at: location)) { e in
                    e.type.rawValue == CGSEventKind.gesture.rawValue
                        && e.get(.gestureHIDType) == HIDEventType.zoom.rawValue
                        && e.getDouble(.gestureZoomValue) == 0.125
                        && e.get(.gesturePhase) == phase.rawValue
                }
            }
        case .rotate:
            return phases.allSatisfy { phase in
                both(builder.rotate(degrees: 15, phase: phase, at: location)) { e in
                    e.type.rawValue == CGSEventKind.gesture.rawValue
                        && e.get(.gestureHIDType) == HIDEventType.rotation.rawValue
                        && e.getDouble(.gestureRotationValue) == 15
                        && e.get(.gesturePhase) == phase.rawValue
                }
            }
        case .smartMagnify:
            return both(builder.smartMagnify(at: location)) { $0.get(.gestureHIDType) == HIDEventType.zoomToggle.rawValue }
        case .navigate:
            let es = builder.navigationSwipe(direction: .left, at: location)
            guard es.count == 2 else { return false }
            return both(es[0]) { $0.get(.gestureSwipeValue) == HIDSwipe.left.rawValue
                    && $0.get(.gestureHIDType) == HIDEventType.navigationSwipe.rawValue
                    && $0.get(.gesturePhase) == HIDPhase.began.rawValue }
                && both(es[1]) { $0.get(.gesturePhase) == HIDPhase.ended.rawValue }
        case .spaces, .missionControl, .appExpose, .launchpad, .showDesktop:
            let motion: DockSwipeMotion = g == .spaces ? .horizontal : (g == .launchpad || g == .showDesktop ? .pinch : .vertical)
            // Began, changed and ended all have to build: a Dock that gets a "began" it
            // understands and an "ended" it does not is left mid-transition.
            return phases.allSatisfy { phase in
                let es = builder.dockSwipe(motion: motion, originOffset: 0.25, phase: phase,
                                           exitSpeed: phase == .ended ? 0.5 : nil, invertedFromDevice: false, at: location)
                guard es.count == 2 else { return false }
                return built(es[0]) { $0.type.rawValue == CGSEventKind.gesture.rawValue
                        && $0.get(.dockSwipeCompanionMagic) == dockSwipeCompanionMagicValue }
                    && built(es[1]) { dock in
                        dock.type.rawValue == CGSEventKind.dockControl.rawValue
                            && dock.get(.gestureHIDType) == HIDEventType.dockSwipe.rawValue
                            && dock.get(.dockSwipeMotion) == motion.rawValue
                            && dock.getDouble(.dockSwipeOriginOffset) == 0.25
                            && dock.get(.gesturePhase) == phase.rawValue
                            && (phase != .ended || dock.getDouble(.dockSwipeExitSpeedX) == 0.5)
                    }
            }
        case .lookUp, .forceClick, .notificationCenter:
            return false
        }
    }

    /// The event serialised and read back (`CGEventCreateData` / `CGEventCreateFromData`, the
    /// format events take on their way to the WindowServer). Nothing is posted.
    static func roundTrip(_ e: CGEvent) -> CGEvent? {
        guard let data = e.data else { return nil }
        return CGEvent(withDataAllocator: nil, data: data)
    }

    /// Text for the menu, one line per gesture.
    public var summary: [(gesture: SynthGesture, mode: SynthMode)] {
        SynthGesture.allCases.map { ($0, mode(for: $0)) }
    }
}
