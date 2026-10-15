import Foundation
import CoreGraphics
import ApplicationServices

/// Posts real keyboard and mouse events with Quartz. Needs Accessibility.
/// Every event carries `MacroEventMarker.userData`.
public struct CGEventOutput: MacroEventOutput {
    public init() {}

    /// Characters per synthetic key event when typing text. Apps reliably
    /// accept up to 20 UTF-16 units in one event.
    static let typeChunkUTF16 = 20

    private func source() throws -> CGEventSource {
        guard AXIsProcessTrusted() else { throw MacroError.accessibilityNotGranted }
        guard let s = CGEventSource(stateID: .hidSystemState) else {
            throw MacroError.outputFailed("Could not create an event source.")
        }
        return s
    }

    private func post(_ event: CGEvent?) throws {
        guard let event else { throw MacroError.outputFailed("Could not create an event.") }
        event.setIntegerValueField(.eventSourceUserData, value: MacroEventMarker.userData)
        event.post(tap: .cghidEventTap)
    }

    static func flags(_ m: KeyModifiers) -> CGEventFlags {
        var f: CGEventFlags = []
        if m.contains(.command) { f.insert(.maskCommand) }
        if m.contains(.shift) { f.insert(.maskShift) }
        if m.contains(.option) { f.insert(.maskAlternate) }
        if m.contains(.control) { f.insert(.maskControl) }
        return f
    }

    public func press(_ combo: KeyCombo) async throws {
        let src = try source()
        let layout = await KeyboardLayoutMap.current()
        guard let code = layout.keyCode(for: combo.key) else {
            throw MacroError.outputFailed("No key types \"\(combo.key.jsonName)\" on this keyboard layout.")
        }
        let flags = Self.flags(combo.modifiers)
        let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
        down?.flags = flags
        try post(down)
        let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
        up?.flags = flags
        try post(up)
    }

    public func type(_ text: String) async throws {
        let src = try source()
        var chunk: [UniChar] = []
        func flush() async throws {
            guard !chunk.isEmpty else { return }
            for keyDown in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: keyDown)
                e?.flags = []
                chunk.withUnsafeBufferPointer { e?.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress) }
                try post(e)
            }
            chunk.removeAll()
            try await Task.sleep(for: .milliseconds(3))
        }
        for ch in text {
            // Newlines and tabs as real keys: many apps ignore them as unicode strings.
            if ch == "\n" || ch == "\r" || ch == "\r\n" || ch == "\t" {
                try await flush()
                try await press(KeyCombo(.special(ch == "\t" ? .tab : .returnKey)))
                continue
            }
            let units = Array(String(ch).utf16)
            if chunk.count + units.count > Self.typeChunkUTF16 { try await flush() }
            chunk.append(contentsOf: units)
        }
        try await flush()
    }

    public func moveMouse(to point: CGPoint) async throws {
        let src = try source()
        try post(CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left))
    }

    private static func types(_ b: MouseButton) -> (down: CGEventType, up: CGEventType, drag: CGEventType, cg: CGMouseButton) {
        switch b {
        case .left: (.leftMouseDown, .leftMouseUp, .leftMouseDragged, .left)
        case .right: (.rightMouseDown, .rightMouseUp, .rightMouseDragged, .right)
        case .middle: (.otherMouseDown, .otherMouseUp, .otherMouseDragged, .center)
        }
    }

    public func click(_ button: MouseButton, at point: CGPoint, count: Int, modifiers: KeyModifiers) async throws {
        let src = try source()
        let t = Self.types(button)
        try post(CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: t.cg))
        for n in 1...max(1, count) {
            for type in [t.down, t.up] {
                let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: point, mouseButton: t.cg)
                e?.flags = Self.flags(modifiers)
                e?.setIntegerValueField(.mouseEventClickState, value: Int64(n))
                try post(e)
            }
            if n < count { try await Task.sleep(for: .milliseconds(15)) }
        }
    }

    public func drag(_ button: MouseButton, from: CGPoint, to: CGPoint, durationMs: Int) async throws {
        let src = try source()
        let t = Self.types(button)
        try post(CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: from, mouseButton: t.cg))
        let down = CGEvent(mouseEventSource: src, mouseType: t.down, mouseCursorPosition: from, mouseButton: t.cg)
        down?.setIntegerValueField(.mouseEventClickState, value: 1)
        try post(down)
        let steps = max(2, durationMs / 16)
        let pause = Double(durationMs) / Double(steps)
        do {
            for i in 1...steps {
                let f = Double(i) / Double(steps)
                let p = CGPoint(x: from.x + (to.x - from.x) * f, y: from.y + (to.y - from.y) * f)
                try post(CGEvent(mouseEventSource: src, mouseType: t.drag, mouseCursorPosition: p, mouseButton: t.cg))
                if pause > 0 { try await Task.sleep(for: .microseconds(Int64(pause * 1000))) }
            }
        } catch {
            // Never leave a button held down if playback is cancelled mid-drag.
            try? post(CGEvent(mouseEventSource: src, mouseType: t.up, mouseCursorPosition: to, mouseButton: t.cg))
            throw error
        }
        let up = CGEvent(mouseEventSource: src, mouseType: t.up, mouseCursorPosition: to, mouseButton: t.cg)
        up?.setIntegerValueField(.mouseEventClickState, value: 1)
        try post(up)
    }

    public func scroll(dx: Int, dy: Int) async throws {
        let src = try source()
        try post(CGEvent(scrollWheelEvent2Source: src, units: .pixel, wheelCount: 2,
                         wheel1: Int32(clamping: dy), wheel2: Int32(clamping: dx), wheel3: 0))
    }
}
