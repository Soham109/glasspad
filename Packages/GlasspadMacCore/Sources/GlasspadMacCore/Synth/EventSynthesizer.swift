import AppKit
import CoreGraphics
import GlasspadKit

/// Turns `GestureEvent`s into CGEvents and hands them to an `EventPoster`.
///
/// Not thread safe: drive it from one queue (the server uses the main actor).
public final class EventSynthesizer {
    public struct Tuning: Sendable {
        /// Fallback swipes fire when the gesture ends past this fraction of a full swipe.
        public var fallbackSwipeThreshold: Double = 0.3
        /// A dock swipe that ends past this fraction counts as completed (snap haptic).
        public var completionThreshold: Double = 0.5
        /// Cumulative dock origin offset per 1.0 of recognizer progress, per motion.
        /// ASSUMED 1.0; [MMF] measured that one Space is 1 + 1/(spaces - 1) offset units
        /// horizontally, so this may need a live tune.
        public var horizontalOffsetScale: Double = 1.0
        public var verticalOffsetScale: Double = 1.0
        public var pinchOffsetScale: Double = 1.0
        /// cmd+scroll pixels per 1.0 of magnification in the magnify fallback.
        public var magnifyFallbackPixels: Double = 400
        /// Dock end events are re-sent after these delays: [MMF] does this to avoid the Dock
        /// getting stuck mid-swipe.
        public var dockEndRepostDelays: [TimeInterval] = [0.2, 0.5]
        public init() {}
    }

    public var capabilities: SynthCapabilities
    public var settings: TrackpadSettings
    public var tuning = Tuning()
    /// Called when a Spaces / Mission Control / ... swipe completes (used for the snap haptic).
    public var onSwipeCompleted: ((SwipeKind) -> Void)?

    private let poster: EventPoster
    private let source: CGEventSource?
    private let builder: GestureEventBuilder
    private let cursorLocation: () -> CGPoint
    private let displayBounds: () -> [CGRect]

    // State
    private var cursor: CGPoint?
    private var buttonsDown: Set<Int> = []           // CGMouseButton raw values
    private var lastClickCount: [Int: Int] = [:]
    private var scrollRemainder = CGPoint.zero
    private var deltaRemainder = CGPoint.zero
    private var dock: (kind: SwipeKind, offset: Double, lastDelta: Double)?

    public init(poster: EventPoster,
                settings: TrackpadSettings = .macDefault,
                capabilities: SynthCapabilities = .selfCheck(),
                source: CGEventSource? = EventSynthesizer.makeSource(),
                cursorLocation: @escaping () -> CGPoint = EventSynthesizer.liveCursorLocation,
                displayBounds: @escaping () -> [CGRect] = EventSynthesizer.liveDisplayBounds) {
        self.poster = poster
        self.settings = settings
        self.capabilities = capabilities
        self.source = source
        self.builder = GestureEventBuilder(source: source)
        self.cursorLocation = cursorLocation
        self.displayBounds = displayBounds
    }

    /// A HID-state source with local event suppression turned off, so the real trackpad and
    /// mouse keep working while we post (the default suppresses them for 0.25 s after each post).
    public static func makeSource() -> CGEventSource? {
        let s = CGEventSource(stateID: .hidSystemState)
        s?.localEventsSuppressionInterval = 0
        return s
    }

    /// Reads the current pointer location without posting anything.
    public static func liveCursorLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    public static func liveDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }

    // MARK: - Dispatch

    public func handle(_ events: [GestureEvent]) { events.forEach(handle) }

    public func handle(_ event: GestureEvent) {
        switch event {
        case let .move(dx, dy): pointer(dx: dx, dy: dy, forceDrag: false)
        case let .drag(dx, dy): pointer(dx: dx, dy: dy, forceDrag: true)
        case let .button(button, down, clickCount): self.button(button, down: down, clickCount: clickCount)
        case let .scroll(dx, dy, phase, momentum): scroll(dx: dx, dy: dy, phase: phase.cgValue, momentum: momentum.cgValue, flags: [])
        case let .magnify(delta, phase): magnify(delta: delta, phase: phase)
        case let .rotate(degrees, phase): rotate(degrees: degrees, phase: phase)
        case .smartMagnify: smartMagnify()
        case let .swipe(kind, progress, phase): swipe(kind, progress: progress, phase: phase)
        case let .navigate(back): navigate(back: back)
        case let .forceClick(stage): forceClick(stage: stage)
        case .lookUp: lookUp()
        case .notificationCenter: notificationCenter()
        }
    }

    // MARK: - Pointer

    /// Clamps a point to the displays: a point inside any display is kept; otherwise it is
    /// clamped into the display that contains (or is nearest to) the previous point. Clamping
    /// to the plain union rectangle would let the pointer into gaps between displays.
    public static func clamp(_ p: CGPoint, from previous: CGPoint, displays: [CGRect]) -> CGPoint {
        guard !displays.isEmpty else { return p }
        if displays.contains(where: { $0.contains(p) }) { return p }
        func distance(_ r: CGRect, _ q: CGPoint) -> CGFloat {
            let dx = max(r.minX - q.x, 0, q.x - r.maxX), dy = max(r.minY - q.y, 0, q.y - r.maxY)
            return dx * dx + dy * dy
        }
        let home = displays.min { distance($0, previous) < distance($1, previous) }!
        // The display nearest the target lets the pointer cross onto an adjacent display.
        let target = displays.min { distance($0, p) < distance($1, p) }!
        let r = distance(target, p) < distance(home, p) ? target : home
        return CGPoint(x: min(max(p.x, r.minX), r.maxX - 1), y: min(max(p.y, r.minY), r.maxY - 1))
    }

    private func pointer(dx: Double, dy: Double, forceDrag: Bool) {
        let start = cursorLocation()
        let next = Self.clamp(CGPoint(x: start.x + dx, y: start.y + dy), from: start, displays: displayBounds())
        cursor = next

        let type: CGEventType
        let button: CGMouseButton
        if forceDrag || buttonsDown.contains(Int(CGMouseButton.left.rawValue)) {
            type = .leftMouseDragged; button = .left
        } else if buttonsDown.contains(Int(CGMouseButton.right.rawValue)) {
            type = .rightMouseDragged; button = .right
        } else if buttonsDown.contains(Int(CGMouseButton.center.rawValue)) {
            type = .otherMouseDragged; button = .center
        } else {
            type = .mouseMoved; button = .left
        }
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: next, mouseButton: button) else { return }
        // Delta fields are integers; carry the fraction so slow motion is not lost.
        let fx = dx + deltaRemainder.x, fy = dy + deltaRemainder.y
        let ix = fx.rounded(.towardZero), iy = fy.rounded(.towardZero)
        deltaRemainder = CGPoint(x: fx - ix, y: fy - iy)
        e.setIntegerValueField(.mouseEventDeltaX, value: Int64(ix))
        e.setIntegerValueField(.mouseEventDeltaY, value: Int64(iy))
        poster.post(e, tap: .cghidEventTap)
    }

    private func button(_ b: MouseButton, down: Bool, clickCount: Int) {
        let location = cursorLocation()
        let (cgButton, type): (CGMouseButton, CGEventType) = switch (b, down) {
        case (.left, true): (.left, .leftMouseDown)
        case (.left, false): (.left, .leftMouseUp)
        case (.right, true): (.right, .rightMouseDown)
        case (.right, false): (.right, .rightMouseUp)
        case (.middle, true): (.center, .otherMouseDown)
        case (.middle, false): (.center, .otherMouseUp)
        }
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: cgButton) else { return }
        let count = max(1, clickCount)
        e.setIntegerValueField(.mouseEventClickState, value: Int64(count))
        e.setIntegerValueField(.mouseEventButtonNumber, value: Int64(cgButton.rawValue))
        if down { buttonsDown.insert(Int(cgButton.rawValue)) } else { buttonsDown.remove(Int(cgButton.rawValue)) }
        lastClickCount[Int(cgButton.rawValue)] = count
        poster.post(e, tap: .cghidEventTap)
    }

    // MARK: - Scroll

    /// Continuous pixel scroll. `dy` is wheel axis 1 (positive = content moves down, as a
    /// wheel scrolled up), `dx` is axis 2. Natural scrolling is already applied by the
    /// recognizer: synthetic events are not inverted by macOS.
    private func scroll(dx: Double, dy: Double, phase: Int64, momentum: Int64, flags: CGEventFlags) {
        let fx = dx + scrollRemainder.x, fy = dy + scrollRemainder.y
        let ix = fx.rounded(.towardZero), iy = fy.rounded(.towardZero)
        scrollRemainder = CGPoint(x: fx - ix, y: fy - iy)
        if phase == 4 || phase == 8 || momentum == 3 { scrollRemainder = .zero }
        guard let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                              wheel1: Int32(iy), wheel2: Int32(ix), wheel3: 0) else { return }
        e.setIntegerValueField(CGScrollField.isContinuous, value: 1)
        e.setIntegerValueField(CGScrollField.pointDeltaAxis1, value: Int64(iy))
        e.setIntegerValueField(CGScrollField.pointDeltaAxis2, value: Int64(ix))
        e.setDoubleValueField(CGScrollField.fixedDeltaAxis1, value: dy)
        e.setDoubleValueField(CGScrollField.fixedDeltaAxis2, value: dx)
        e.setIntegerValueField(CGScrollField.scrollPhase, value: phase)
        e.setIntegerValueField(CGScrollField.momentumPhase, value: momentum)
        e.location = cursorLocation()
        if !flags.isEmpty { e.flags = flags }
        poster.post(e, tap: .cghidEventTap)
    }

    // MARK: - Gestures

    private func magnify(delta: Double, phase: GesturePhase) {
        switch capabilities.mode(for: .magnify) {
        case .native:
            if let e = builder.magnify(delta: delta, phase: phase.hidPhase, at: cursorLocation()) {
                poster.post(e, tap: .cghidEventTap)
            }
        case .fallback:
            // cmd+scroll zooms in browsers, Maps, Preview and most document apps.
            let px = delta * tuning.magnifyFallbackPixels
            scroll(dx: 0, dy: px, phase: 0, momentum: 0, flags: .maskCommand)
        case .unavailable: break
        }
    }

    private func rotate(degrees: Double, phase: GesturePhase) {
        guard capabilities.mode(for: .rotate) == .native,
              let e = builder.rotate(degrees: degrees, phase: phase.hidPhase, at: cursorLocation()) else { return }
        poster.post(e, tap: .cghidEventTap)
    }

    private func smartMagnify() {
        guard capabilities.mode(for: .smartMagnify) == .native,
              let e = builder.smartMagnify(at: cursorLocation()) else { return }
        poster.post(e, tap: .cghidEventTap)
    }

    private func navigate(back: Bool) {
        switch capabilities.mode(for: .navigate) {
        case .native:
            for e in builder.navigationSwipe(direction: back ? .left : .right, at: cursorLocation()) {
                poster.post(e, tap: .cghidEventTap)
            }
        case .fallback:
            keystroke(KeyStroke(back ? .leftBracket : .rightBracket, command: true))
        case .unavailable: break
        }
    }

    private func forceClick(stage: Int) {
        // No native pressure events yet. Stage 2 performs Look Up when the user has
        // "Force click with one finger" chosen for Look Up.
        if stage >= 2, settings.lookUp == .forceClick { lookUp() }
    }

    private func lookUp() {
        keystroke(KeyStroke(.d, command: true, control: true))
    }

    private func notificationCenter() {
        poster.perform(.runAppleScript(
            "tell application \"System Events\" to tell process \"ControlCenter\" to click menu bar item \"Clock\" of menu bar 1"))
    }

    public func keystroke(_ stroke: KeyStroke) {
        for e in KeyboardSynth.events(for: stroke, source: source) { poster.post(e, tap: .cghidEventTap) }
    }

    // MARK: - Dock swipes

    /// `progress` is cumulative since the gesture began, 1.0 = one full transition, with the
    /// kit's sign convention (GestureEvent.swipe): spaces positive = go to the Space on the
    /// right; missionControl positive = up; appExpose positive = down; launchpad positive =
    /// pinched in; showDesktop positive = spread out.
    private func swipe(_ kind: SwipeKind, progress: Double, phase: GesturePhase) {
        let gesture = kind.synthGesture
        switch capabilities.mode(for: gesture) {
        case .native: nativeDockSwipe(kind, progress: progress, phase: phase)
        case .fallback: fallbackSwipe(kind, progress: progress, phase: phase)
        case .unavailable: break
        }
    }

    static func dockMotionAndOffset(_ kind: SwipeKind, progress: Double, tuning: Tuning) -> (DockSwipeMotion, Double) {
        switch kind {
        case .spaces: return (.horizontal, progress * tuning.horizontalOffsetScale)
        case .missionControl: return (.vertical, -progress * tuning.verticalOffsetScale)
        case .appExpose: return (.vertical, progress * tuning.verticalOffsetScale)
        // ASSUMED: pinch-in (Launchpad) is positive, spread (Show Desktop) is negative, from
        // [MMF] Scroll.m mapping zoom-in to a negated pinch delta. Needs a live check.
        case .launchpad: return (.pinch, progress * tuning.pinchOffsetScale)
        case .showDesktop: return (.pinch, -progress * tuning.pinchOffsetScale)
        }
    }

    private func nativeDockSwipe(_ kind: SwipeKind, progress: Double, phase: GesturePhase) {
        let (motion, offset) = Self.dockMotionAndOffset(kind, progress: progress, tuning: tuning)
        var hidPhase = phase.hidPhase
        if phase == .began || dock == nil || dock?.kind != kind {
            dock = (kind, 0, 0)
            hidPhase = .began
        }
        let delta = offset - (dock?.offset ?? 0)
        if delta != 0 { dock?.lastDelta = delta }
        dock?.offset = offset

        var exitSpeed: Double?
        if phase.isTerminal {
            let last = dock?.lastDelta ?? 0
            exitSpeed = last * 100
            // [MMF]: ended when still moving in the direction of the offset, else cancelled.
            if phase == .ended, last != 0, (last > 0) != (offset > 0) { hidPhase = .cancelled }
        }
        let events = builder.dockSwipe(motion: motion, originOffset: offset, phase: hidPhase,
                                       exitSpeed: exitSpeed, invertedFromDevice: settings.naturalScrolling,
                                       at: cursorLocation())
        for e in events { poster.post(e, tap: .cgSessionEventTap) }
        if phase.isTerminal {
            for delay in tuning.dockEndRepostDelays {
                for e in events { if let copy = e.copy() { poster.post(copy, tap: .cgSessionEventTap, after: delay) } }
            }
            if hidPhase == .ended, (kind == .spaces ? abs(progress) : progress) >= tuning.completionThreshold { onSwipeCompleted?(kind) }
            dock = nil
        }
    }

    private func fallbackSwipe(_ kind: SwipeKind, progress: Double, phase: GesturePhase) {
        guard phase == .ended else { return }
        // Spaces may go either way; the others only fire in their own direction.
        let reached = kind == .spaces ? abs(progress) >= tuning.fallbackSwipeThreshold : progress >= tuning.fallbackSwipeThreshold
        guard reached else { return }
        switch kind {
        case .spaces: keystroke(KeyStroke(progress > 0 ? .right : .left, control: true))
        case .missionControl: keystroke(KeyStroke(.up, control: true))
        case .appExpose: keystroke(KeyStroke(.down, control: true))
        case .showDesktop: keystroke(KeyStroke(.f11))
        case .launchpad: poster.perform(.openApplication(Self.launchpadURL()))
        }
        onSwipeCompleted?(kind)
    }

    /// macOS 26 replaced Launchpad with Apps.app (bundle com.apple.apps.launcher, seen in this
    /// Mac's Dock); older systems have Launchpad.app.
    public static func launchpadURL(fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> URL {
        for path in ["/System/Applications/Apps.app", "/System/Applications/Launchpad.app"] where fileExists(path) {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: "/System/Applications/Launchpad.app")
    }

    /// Releases any held buttons and ends an open dock swipe (call on disconnect so nothing
    /// stays stuck down).
    /// Switches gesture paths while running (Settings > Trackpad, "If a gesture stops
    /// working"). A native Dock swipe in progress whose gesture leaves the native path is
    /// cancelled first, through the native path, so the Dock is never left mid-transition.
    public func updateCapabilities(_ new: SynthCapabilities) {
        if let d = dock, new.mode(for: d.kind.synthGesture) != .native {
            nativeDockSwipe(d.kind, progress: 0, phase: .cancelled)
            dock = nil
        }
        capabilities = new
    }

    public func reset() {
        for raw in buttonsDown {
            let b: MouseButton = raw == Int(CGMouseButton.left.rawValue) ? .left : (raw == Int(CGMouseButton.right.rawValue) ? .right : .middle)
            button(b, down: false, clickCount: lastClickCount[raw] ?? 1)
        }
        if let d = dock { nativeDockSwipe(d.kind, progress: 0, phase: .cancelled) }
        scrollRemainder = .zero
        deltaRemainder = .zero
    }
}
