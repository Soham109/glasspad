import Foundation
import CoreGraphics

/// Supplies raw input events while recording.
public protocol RecordingEventSource: AnyObject, Sendable {
    /// Starts delivering events. Throws if the source cannot listen
    /// (for example `MacroError.inputMonitoringNotGranted`).
    func start(_ handler: @escaping @Sendable (RecordedEvent) -> Void) throws
    func stop()
}

public struct RecordingResult: Equatable, Sendable {
    public var steps: [MacroStep]
    /// Raw events kept (after dropping secure-input keys and the stop hotkey).
    public var eventCount: Int
    /// Key presses thrown away because secure input came on mid-recording.
    public var droppedSecureKeyEvents: Int
    public var durationSeconds: Double
    /// True when the stop hotkey (rather than `stop()`) ended the recording.
    public var stoppedByHotkey: Bool
}

/// Records the user's keyboard and mouse into macro steps.
///
/// Passwords are never captured: recording refuses to start while secure
/// keyboard input is on, and any key press that arrives while it is on
/// (a password field focused mid-recording) is discarded.
public final class MacroRecorder: @unchecked Sendable {
    private let source: any RecordingEventSource
    private let secureInput: any SecureInputChecking
    private let windows: any FrontmostWindowProviding
    private let lock = NSLock()

    private var recording = false
    private var events: [RecordedEvent] = []
    private var dropped = 0
    private var options = RecordingOptions()
    private var layout = KeyboardLayoutMap.ansi
    private var onAutoStop: (@Sendable (RecordingResult) -> Void)?

    public init(source: any RecordingEventSource = CGEventTapRecordingSource(),
                secureInput: any SecureInputChecking = SystemSecureInputChecker(),
                windows: any FrontmostWindowProviding = AXWindowProvider()) {
        self.source = source
        self.secureInput = secureInput
        self.windows = windows
    }

    public var isRecording: Bool {
        lock.lock(); defer { lock.unlock() }
        return recording
    }

    /// Starts recording. `onAutoStop` is called (on the tap thread) when the
    /// user presses the stop hotkey. `layout` should be `KeyboardLayoutMap.current()`.
    public func start(options: RecordingOptions = .init(), layout: KeyboardLayoutMap = .ansi,
                      onAutoStop: (@Sendable (RecordingResult) -> Void)? = nil) throws {
        lock.lock()
        if recording { lock.unlock(); throw MacroError.alreadyRecording }
        if secureInput.isSecureInputEnabled() { lock.unlock(); throw MacroError.secureInputActive }
        recording = true
        events = []
        dropped = 0
        self.options = options
        self.layout = layout
        self.onAutoStop = onAutoStop
        lock.unlock()
        do {
            try source.start { [weak self] event in self?.receive(event) }
        } catch {
            lock.lock(); recording = false; lock.unlock()
            throw error
        }
    }

    /// Stops recording and returns the steps.
    ///
    /// Pass `discardTrailingClick: true` when the user stopped by clicking a
    /// Mac control (the menu bar item): that click was recorded too, and is
    /// removed along with the pause before it. Stopping from the phone or the
    /// hotkey leaves nothing to trim.
    public func stop(discardTrailingClick: Bool = false) throws -> RecordingResult {
        var result = try finish(byHotkey: false)
        if discardTrailingClick { result.steps = Self.trimTrailingClick(result.steps) }
        return result
    }

    static func trimTrailingClick(_ steps: [MacroStep]) -> [MacroStep] {
        var s = steps
        guard case .click = s.last else { return s }
        s.removeLast()
        if case .wait = s.last { s.removeLast() }
        return s
    }

    private func finish(byHotkey: Bool) throws -> RecordingResult {
        lock.lock()
        guard recording else { lock.unlock(); throw MacroError.notRecording }
        recording = false
        let captured = events
        let droppedCount = dropped
        let opts = options
        let map = layout
        events = []
        lock.unlock()
        source.stop()
        let duration = (captured.last?.time ?? 0) - (captured.first?.time ?? 0)
        return RecordingResult(steps: RecordingCoalescer(options: opts, layout: map).steps(from: captured),
                               eventCount: captured.count, droppedSecureKeyEvents: droppedCount,
                               durationSeconds: max(0, duration), stoppedByHotkey: byHotkey)
    }

    /// Entry point for every raw event. Internal so tests can feed it through
    /// a fake source.
    func receive(_ incoming: RecordedEvent) {
        var event = incoming
        lock.lock()
        guard recording else { lock.unlock(); return }
        if case .keyDown(let code, _, let mods, _) = event.kind {
            if secureInput.isSecureInputEnabled() {
                dropped += 1
                lock.unlock()
                return
            }
            if KeyCombo(layout.key(for: code), mods) == options.stopHotkey {
                let callback = onAutoStop
                lock.unlock()
                if let result = try? finish(byHotkey: true) { callback?(result) }
                return
            }
        }
        let wantsFrame = options.positions == .frontWindow
        lock.unlock()

        if wantsFrame, case .mouseDown = event.kind, event.windowFrame == nil {
            event.windowFrame = windows.frontmostWindowFrame()
        }

        lock.lock()
        if recording { events.append(event) }
        lock.unlock()
    }
}

/// Real event source: a listen-only Quartz event tap. Needs Input Monitoring.
/// Events posted by macro playback are skipped.
public final class CGEventTapRecordingSource: RecordingEventSource, @unchecked Sendable {
    private let lock = NSLock()
    private var tap: ListenOnlyEventTap?

    public init() {}

    public func start(_ handler: @escaping @Sendable (RecordedEvent) -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        guard CGPreflightListenEventAccess() else {
            CGRequestListenEventAccess()
            throw MacroError.inputMonitoringNotGranted
        }
        let newTap = ListenOnlyEventTap(types: [
            .keyDown, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .mouseMoved, .leftMouseDragged, .rightMouseDragged,
            .otherMouseDragged, .scrollWheel,
        ]) { type, event in
            guard !event.isFromMacroPlayback, let recorded = RecordedEvent(cgEvent: event, type: type) else { return }
            handler(recorded)
        }
        guard newTap.start() else { throw MacroError.inputMonitoringNotGranted }
        tap = newTap
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        tap?.stop()
        tap = nil
    }
}

extension RecordedEvent {
    /// Converts a Quartz event. Returns nil for events the recorder ignores
    /// (extra mouse buttons such as back/forward).
    public init?(cgEvent e: CGEvent, type: CGEventType) {
        let time = Double(e.timestamp) / 1_000_000_000
        func button(_ t: CGEventType) -> MouseButton? {
            switch t {
            case .leftMouseDown, .leftMouseUp, .leftMouseDragged: return .left
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged: return .right
            default: return e.getIntegerValueField(.mouseEventButtonNumber) == 2 ? .middle : nil
            }
        }
        switch type {
        case .keyDown:
            var length = 0
            var chars = [UniChar](repeating: 0, count: 8)
            e.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
            self.init(time: time, kind: .keyDown(
                keyCode: UInt16(truncatingIfNeeded: e.getIntegerValueField(.keyboardEventKeycode)),
                characters: String(utf16CodeUnits: chars, count: length),
                modifiers: e.macroModifiers,
                isRepeat: e.getIntegerValueField(.keyboardEventAutorepeat) != 0))
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard let b = button(type) else { return nil }
            self.init(time: time, kind: .mouseDown(b, e.location,
                                                   clickCount: Int(e.getIntegerValueField(.mouseEventClickState)),
                                                   modifiers: e.macroModifiers))
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            guard let b = button(type) else { return nil }
            self.init(time: time, kind: .mouseUp(b, e.location))
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            guard let b = button(type) else { return nil }
            self.init(time: time, kind: .mouseDragged(b, e.location))
        case .mouseMoved:
            self.init(time: time, kind: .mouseMoved(e.location))
        case .scrollWheel:
            self.init(time: time, kind: .scroll(
                dx: Int(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)),
                dy: Int(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))))
        default:
            return nil
        }
    }
}
