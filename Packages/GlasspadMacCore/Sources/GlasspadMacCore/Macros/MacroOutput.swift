import AppKit
import ApplicationServices
import CoreGraphics
import GlasspadKit
import GlasspadMacros

/// Holds the app's `EventPoster` for the macro player, which runs off the main thread. The
/// poster is only ever touched inside `MainActor.run`, the same actor the touch pipeline uses,
/// so trackpad events and macro events never interleave mid-call.
final class MainActorPoster: @unchecked Sendable {
    let poster: EventPoster
    let source: CGEventSource?
    init(_ poster: EventPoster, source: CGEventSource?) {
        self.poster = poster
        self.source = source
    }
}

/// Macro keyboard and mouse output through GlasspadMacCore's `EventPoster` and `KeyboardSynth`,
/// so tests can capture every event with `CapturingEventPoster` and nothing reaches the session.
/// Every event carries `MacroEventMarker.userData`, so the recorder and the user-input guard can
/// tell playback from the real user.
public struct PosterMacroOutput: MacroEventOutput {
    /// Characters per unicode key event (see `KeyboardSynth.unicodeEvents`).
    static let typePauseMs: Double = 3
    static let multiClickPauseMs: Double = 15

    private let box: MainActorPoster
    private let accessibilityGranted: @Sendable () -> Bool
    private let layout: @MainActor @Sendable () -> KeyboardLayoutMap
    private let pause: @Sendable (Double) async throws -> Void

    /// - Parameters:
    ///   - accessibilityGranted: posting needs Accessibility; checked before every step.
    ///   - layout: the active keyboard layout, so character shortcuts stay right on non-US layouts.
    ///   - pause: sleeps between multi-clicks, typed chunks and drag steps (tests pass a no-op).
    public init(poster: EventPoster,
                source: CGEventSource? = EventSynthesizer.makeSource(),
                accessibilityGranted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
                layout: @escaping @MainActor @Sendable () -> KeyboardLayoutMap = { KeyboardLayoutMap.current() },
                pause: @escaping @Sendable (Double) async throws -> Void = { ms in
                    try await Task.sleep(for: .microseconds(Int64(ms * 1000)))
                }) {
        self.box = MainActorPoster(poster, source: source)
        self.accessibilityGranted = accessibilityGranted
        self.layout = layout
        self.pause = pause
    }

    static func flags(_ m: GlasspadMacros.KeyModifiers) -> CGEventFlags {
        var f: CGEventFlags = []
        if m.contains(.command) { f.insert(.maskCommand) }
        if m.contains(.shift) { f.insert(.maskShift) }
        if m.contains(.option) { f.insert(.maskAlternate) }
        if m.contains(.control) { f.insert(.maskControl) }
        return f
    }

    /// Builds events on the main actor, stamps the marker and posts them in order.
    private func post(_ build: @escaping @MainActor @Sendable (CGEventSource?) throws -> [CGEvent?]) async throws {
        guard accessibilityGranted() else { throw MacroError.accessibilityNotGranted }
        let box = self.box
        try await MainActor.run {
            let events = try build(box.source)
            for e in events {
                guard let e else { throw MacroError.outputFailed("Could not create an event.") }
                e.setIntegerValueField(.eventSourceUserData, value: MacroEventMarker.userData)
                box.poster.post(e, tap: .cghidEventTap, after: 0)
            }
        }
    }

    public func press(_ combo: KeyCombo) async throws {
        let layout = self.layout
        try await post { source in
            guard let code = layout().keyCode(for: combo.key) else {
                throw MacroError.outputFailed("No key types \"\(combo.key.jsonName)\" on this keyboard layout.")
            }
            let m = combo.modifiers
            let stroke = KeyStroke(keyCode: code, command: m.contains(.command), option: m.contains(.option),
                                   control: m.contains(.control), shift: m.contains(.shift))
            return KeyboardSynth.events(for: stroke, source: source)
        }
    }

    public func type(_ text: String) async throws {
        // Newlines and tabs go out as real Return and Tab keys: many apps ignore them as unicode.
        var run = ""
        func flush() async throws {
            guard !run.isEmpty else { return }
            let chunk = run
            run = ""
            try await post { source in KeyboardSynth.unicodeEvents(for: chunk, source: source) }
            try await pause(Self.typePauseMs)
        }
        for ch in text {
            if ch == "\n" || ch == "\r" || ch == "\r\n" || ch == "\t" {
                try await flush()
                try await press(KeyCombo(.special(ch == "\t" ? .tab : .returnKey)))
            } else {
                run.append(ch)
            }
        }
        try await flush()
    }

    public func moveMouse(to point: CGPoint) async throws {
        try await post { source in
            [CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)]
        }
    }

    static func types(_ b: GlasspadMacros.MouseButton) -> (down: CGEventType, up: CGEventType, drag: CGEventType, cg: CGMouseButton) {
        switch b {
        case .left: (.leftMouseDown, .leftMouseUp, .leftMouseDragged, .left)
        case .right: (.rightMouseDown, .rightMouseUp, .rightMouseDragged, .right)
        case .middle: (.otherMouseDown, .otherMouseUp, .otherMouseDragged, .center)
        }
    }

    public func click(_ button: GlasspadMacros.MouseButton, at point: CGPoint, count: Int,
                      modifiers: GlasspadMacros.KeyModifiers) async throws {
        let t = Self.types(button)
        let flags = Self.flags(modifiers)
        try await post { source in
            [CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: t.cg)]
        }
        let total = max(1, count)
        for n in 1...total {
            try await post { source in
                [t.down, t.up].map { type in
                    let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: t.cg)
                    e?.flags = flags
                    e?.setIntegerValueField(.mouseEventClickState, value: Int64(n))
                    return e
                }
            }
            if n < total { try await pause(Self.multiClickPauseMs) }
        }
    }

    public func drag(_ button: GlasspadMacros.MouseButton, from: CGPoint, to: CGPoint, durationMs: Int) async throws {
        let t = Self.types(button)
        try await post { source in
            let down = CGEvent(mouseEventSource: source, mouseType: t.down, mouseCursorPosition: from, mouseButton: t.cg)
            down?.setIntegerValueField(.mouseEventClickState, value: 1)
            return [CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: from, mouseButton: t.cg), down]
        }
        let steps = max(2, durationMs / 16)
        let stepPause = Double(durationMs) / Double(steps)
        do {
            for i in 1...steps {
                let f = Double(i) / Double(steps)
                let p = CGPoint(x: from.x + (to.x - from.x) * f, y: from.y + (to.y - from.y) * f)
                try await post { source in
                    [CGEvent(mouseEventSource: source, mouseType: t.drag, mouseCursorPosition: p, mouseButton: t.cg)]
                }
                if stepPause > 0 { try await pause(stepPause) }
            }
        } catch {
            // Never leave a button held down when playback is cancelled mid-drag.
            try? await post { source in
                [CGEvent(mouseEventSource: source, mouseType: t.up, mouseCursorPosition: to, mouseButton: t.cg)]
            }
            throw error
        }
        try await post { source in
            let up = CGEvent(mouseEventSource: source, mouseType: t.up, mouseCursorPosition: to, mouseButton: t.cg)
            up?.setIntegerValueField(.mouseEventClickState, value: 1)
            return [up]
        }
    }

    public func scroll(dx: Int, dy: Int) async throws {
        try await post { source in
            [CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                     wheel1: Int32(clamping: dy), wheel2: Int32(clamping: dx), wheel3: 0)]
        }
    }
}

/// Opens apps, URLs and files through `EventPoster.perform`, so tests capture launches instead
/// of opening anything.
public struct PosterAppLauncher: AppLaunching {
    private let box: MainActorPoster
    private let resolve: @Sendable (String) -> URL?

    public init(poster: EventPoster,
                resolve: @escaping @Sendable (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }) {
        self.box = MainActorPoster(poster, source: nil)
        self.resolve = resolve
    }

    public func openApp(bundleID: String) async throws {
        guard let url = resolve(bundleID) else { throw MacroError.appNotFound(bundleID: bundleID) }
        let box = self.box
        await MainActor.run { box.poster.perform(.openApplication(url)) }
    }

    public func open(url: URL) async throws {
        let box = self.box
        await MainActor.run { box.poster.perform(.openURL(url)) }
    }
}

public extension MacroEnvironment {
    /// The Mac app's macro environment: keyboard and mouse through the app's `EventPoster`,
    /// launches through it too, the frontmost window through Accessibility (`AXWindowProvider`),
    /// Apple Shortcuts through `/usr/bin/shortcuts`, and the package's script, clipboard,
    /// notification and user-input-guard defaults.
    static func glasspad(poster: EventPoster) -> MacroEnvironment {
        MacroEnvironment(
            output: PosterMacroOutput(poster: poster),
            windows: AXWindowProvider(),
            apps: PosterAppLauncher(poster: poster),
            shortcuts: ShortcutsCLI(),
            scripts: SystemScriptRunner(),
            clipboard: PasteboardClipboard(),
            notifier: SystemNotifier(),
            clock: ContinuousMacroClock(),
            inputMonitor: EventTapUserInputMonitor(),
            controls: MacControlRelay.shared)
    }
}

// MARK: - Mac controls

/// Runs macro steps that use a Mac control (window tiling, Do Not Disturb...) exactly as the
/// Actions button would, through the Deck. The router points `perform` at its Deck.
@MainActor
public final class MacControlRelay: MacControlRunning {
    public nonisolated static let shared = MacControlRelay()

    nonisolated init() {}

    public var perform: ((DeckSystemAction) async -> DeckMode.Outcome)?

    public nonisolated func run(_ id: String) async throws {
        guard let action = DeckSystemAction(rawValue: id) else {
            throw MacroError.macControlFailed("This version of Glasspad does not have the Mac control \u{201C}\(id)\u{201D}.")
        }
        guard let outcome = await perform(action) else {
            throw MacroError.macControlFailed("Mac controls are not ready yet.")
        }
        if !outcome.ok { throw MacroError.macControlFailed(outcome.message ?? "\(action.title) did not work.") }
    }

    private func perform(_ action: DeckSystemAction) async -> DeckMode.Outcome? {
        guard let perform else { return nil }
        return await perform(action)
    }
}
