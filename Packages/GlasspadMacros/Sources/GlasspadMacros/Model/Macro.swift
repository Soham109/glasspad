import Foundation
import CoreGraphics

public enum MouseButton: String, Codable, Sendable, CaseIterable {
    case left, right, middle
}

/// Which corner (or the centre) of the frontmost window a relative point is measured from.
public enum WindowAnchor: String, Codable, Sendable, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight, center
}

/// A point on screen, stored either in global screen coordinates or relative
/// to the frontmost window.
///
/// Coordinates are Quartz global points: origin at the top-left of the main
/// display, y grows downwards. This is the space `CGEvent.location` and the
/// Accessibility API use, so no flipping is needed anywhere.
public struct MacroPoint: Hashable, Codable, Sendable {
    public enum Reference: Hashable, Sendable {
        case screen
        /// Offset from an anchor of the frontmost window's frame, resolved at run time.
        case frontWindow(WindowAnchor)
    }

    public var x: Double
    public var y: Double
    public var reference: Reference

    public init(x: Double, y: Double, reference: Reference = .screen) {
        self.x = x
        self.y = y
        self.reference = reference
    }

    public static func screen(_ x: Double, _ y: Double) -> MacroPoint {
        MacroPoint(x: x, y: y, reference: .screen)
    }

    public static func window(_ x: Double, _ y: Double, from anchor: WindowAnchor = .topLeft) -> MacroPoint {
        MacroPoint(x: x, y: y, reference: .frontWindow(anchor))
    }

    enum CodingKeys: String, CodingKey { case x, y, relativeTo, anchor }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        let rel = try c.decodeIfPresent(String.self, forKey: .relativeTo) ?? "screen"
        switch rel {
        case "screen": reference = .screen
        case "window":
            reference = .frontWindow(try c.decodeIfPresent(WindowAnchor.self, forKey: .anchor) ?? .topLeft)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .relativeTo, in: c, debugDescription: "Unknown point reference \"\(rel)\"")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        switch reference {
        case .screen:
            try c.encode("screen", forKey: .relativeTo)
        case .frontWindow(let anchor):
            try c.encode("window", forKey: .relativeTo)
            try c.encode(anchor, forKey: .anchor)
        }
    }

    /// Resolves to a global screen point. `windowFrame` is the frontmost
    /// window's frame in global coordinates; it is only consulted for
    /// window-relative points.
    public func resolve(windowFrame: CGRect?) throws -> CGPoint {
        switch reference {
        case .screen:
            return CGPoint(x: x, y: y)
        case .frontWindow(let anchor):
            guard let f = windowFrame else { throw MacroError.noFrontWindow }
            let origin: CGPoint
            switch anchor {
            case .topLeft: origin = CGPoint(x: f.minX, y: f.minY)
            case .topRight: origin = CGPoint(x: f.maxX, y: f.minY)
            case .bottomLeft: origin = CGPoint(x: f.minX, y: f.maxY)
            case .bottomRight: origin = CGPoint(x: f.maxX, y: f.maxY)
            case .center: origin = CGPoint(x: f.midX, y: f.midY)
            }
            return CGPoint(x: origin.x + x, y: origin.y + y)
        }
    }

    var isWindowRelative: Bool {
        if case .frontWindow = reference { return true }
        return false
    }
}

/// One step of a macro.
public indirect enum MacroStep: Hashable, Sendable {
    case keystroke(KeyCombo)
    case typeText(String)
    case click(button: MouseButton, at: MacroPoint, count: Int, modifiers: KeyModifiers)
    case moveMouse(to: MacroPoint)
    /// Press at `from`, move to `to` over `durationMs`, release.
    case drag(button: MouseButton, from: MacroPoint, to: MacroPoint, durationMs: Int)
    /// Pixel scroll. Positive `dy` scrolls up, positive `dx` scrolls left
    /// (the raw Quartz wheel convention, which is what the recorder captures).
    case scroll(dx: Int, dy: Int)
    case wait(ms: Int)
    case waitForApp(bundleID: String, timeoutMs: Int)
    case openApp(bundleID: String)
    case openURL(String)
    case openFile(path: String)
    /// Runs an Apple Shortcut by name or identifier, optionally with text input.
    case runShortcut(nameOrID: String, input: String?)
    case runAppleScript(source: String)
    case runShell(command: String, timeoutMs: Int)
    case setClipboard(String)
    case notify(title: String, body: String)
    /// One of Glasspad's Mac controls, by its id: a Do Not Disturb or window tiling button
    /// (`DeckSystemAction` raw values such as `doNotDisturb` or `windowLeft`). The Mac app runs
    /// it exactly as the Actions button would.
    case macControl(String)
    case repeatBlock(count: Int, steps: [MacroStep])

    /// Shell and AppleScript steps can do anything the user can, so a macro
    /// must opt in with `allowScripts` before either runs. AppleScript is gated
    /// too because `do shell script` makes it exactly as powerful as a shell.
    public var needsScriptPermission: Bool {
        switch self {
        case .runShell, .runAppleScript: true
        case .repeatBlock(_, let steps): steps.contains(where: \.needsScriptPermission)
        default: false
        }
    }

    public var typeName: String {
        switch self {
        case .keystroke: "keystroke"
        case .typeText: "typeText"
        case .click: "click"
        case .moveMouse: "moveMouse"
        case .drag: "drag"
        case .scroll: "scroll"
        case .wait: "wait"
        case .waitForApp: "waitForApp"
        case .openApp: "openApp"
        case .openURL: "openURL"
        case .openFile: "openFile"
        case .runShortcut: "runShortcut"
        case .runAppleScript: "runAppleScript"
        case .runShell: "runShell"
        case .setClipboard: "setClipboard"
        case .notify: "notify"
        case .macControl: "macControl"
        case .repeatBlock: "repeat"
        }
    }

    /// A short human readable line, used in the editor and on the phone.
    public var summary: String {
        switch self {
        case .keystroke(let k): "Press \(k.displayString)"
        case .typeText(let t): "Type \"\(t.count > 40 ? String(t.prefix(40)) + "…" : t)\""
        case .click(let b, let p, let n, let m):
            "\(n == 2 ? "Double-click" : n == 3 ? "Triple-click" : "Click") \(b == .left ? "" : b.rawValue + " ")\(m.symbols)at \(p.summary)"
        case .moveMouse(let p): "Move pointer to \(p.summary)"
        case .drag(_, let a, let b, _): "Drag from \(a.summary) to \(b.summary)"
        case .scroll(let dx, let dy): "Scroll \(dx), \(dy)"
        case .wait(let ms): "Wait \(ms) ms"
        case .waitForApp(let id, let t): "Wait for \(id) (up to \(t) ms)"
        case .openApp(let id): "Open \(id)"
        case .openURL(let u): "Open \(u)"
        case .openFile(let p): "Open \(p)"
        case .runShortcut(let n, _): "Run shortcut \"\(n)\""
        case .runAppleScript: "Run AppleScript"
        case .runShell(let c, _): "Run \(c.count > 40 ? String(c.prefix(40)) + "…" : c)"
        case .setClipboard: "Set clipboard"
        case .notify(let t, _): "Notify \"\(t)\""
        case .macControl(let id): MacControlName.title(id)
        case .repeatBlock(let n, let s): "Repeat \(n)× (\(s.count) steps)"
        }
    }
}

/// The name of a Mac control, as the Actions Library shows it (GlasspadKit's
/// `DeckSystemAction.title`; a test keeps the two the same).
public enum MacControlName {
    static let titles: [String: String] = [
        "lockScreen": "Lock Screen", "sleepDisplay": "Sleep Display", "sleepMac": "Sleep Mac",
        "toggleDarkMode": "Dark Mode", "volumeUp": "Volume Up", "volumeDown": "Volume Down", "mute": "Mute",
        "micMute": "Mute Microphone", "brightnessUp": "Brightness Up", "brightnessDown": "Brightness Down",
        "playPause": "Play or Pause", "nextTrack": "Next Track", "previousTrack": "Previous Track",
        "showDesktop": "Show Desktop", "missionControl": "Mission Control", "appExpose": "App Windows",
        "launchpad": "Apps", "emptyTrash": "Empty Trash", "ejectAll": "Eject All", "doNotDisturb": "Do Not Disturb",
        "nightShift": "Night Shift", "keepAwake": "Keep Awake", "notificationCenter": "Notifications",
        "windowLeft": "Left Half", "windowRight": "Right Half", "windowTop": "Top Half", "windowBottom": "Bottom Half",
        "windowFill": "Fill Screen", "windowCenter": "Center Window", "windowSplit": "Split Screen",
        "windowNextDisplay": "Next Display",
    ]

    public static func title(_ id: String) -> String { titles[id] ?? id }
}

extension MacroPoint {
    var summary: String {
        switch reference {
        case .screen: "(\(Int(x)), \(Int(y)))"
        case .frontWindow(let a): "(\(Int(x)), \(Int(y))) from window \(a.rawValue)"
        }
    }
}

// MARK: - Step JSON

extension MacroStep: Codable {
    enum CodingKeys: String, CodingKey {
        case type, key, modifiers, text, button, at, count, to, from, durationMs
        case dx, dy, ms, bundleID, timeoutMs, url, path, shortcut, input, source
        case command, title, body, steps, control
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "keystroke":
            self = .keystroke(KeyCombo(
                try c.decode(MacroKey.self, forKey: .key),
                try c.decodeIfPresent(KeyModifiers.self, forKey: .modifiers) ?? []))
        case "typeText":
            self = .typeText(try c.decode(String.self, forKey: .text))
        case "click":
            self = .click(
                button: try c.decodeIfPresent(MouseButton.self, forKey: .button) ?? .left,
                at: try c.decode(MacroPoint.self, forKey: .at),
                count: try c.decodeIfPresent(Int.self, forKey: .count) ?? 1,
                modifiers: try c.decodeIfPresent(KeyModifiers.self, forKey: .modifiers) ?? [])
        case "moveMouse":
            self = .moveMouse(to: try c.decode(MacroPoint.self, forKey: .to))
        case "drag":
            self = .drag(
                button: try c.decodeIfPresent(MouseButton.self, forKey: .button) ?? .left,
                from: try c.decode(MacroPoint.self, forKey: .from),
                to: try c.decode(MacroPoint.self, forKey: .to),
                durationMs: try c.decodeIfPresent(Int.self, forKey: .durationMs) ?? 300)
        case "scroll":
            self = .scroll(dx: try c.decodeIfPresent(Int.self, forKey: .dx) ?? 0,
                           dy: try c.decodeIfPresent(Int.self, forKey: .dy) ?? 0)
        case "wait":
            self = .wait(ms: try c.decode(Int.self, forKey: .ms))
        case "waitForApp":
            self = .waitForApp(bundleID: try c.decode(String.self, forKey: .bundleID),
                               timeoutMs: try c.decodeIfPresent(Int.self, forKey: .timeoutMs) ?? 5000)
        case "openApp":
            self = .openApp(bundleID: try c.decode(String.self, forKey: .bundleID))
        case "openURL":
            self = .openURL(try c.decode(String.self, forKey: .url))
        case "openFile":
            self = .openFile(path: try c.decode(String.self, forKey: .path))
        case "runShortcut":
            self = .runShortcut(nameOrID: try c.decode(String.self, forKey: .shortcut),
                                input: try c.decodeIfPresent(String.self, forKey: .input))
        case "runAppleScript":
            self = .runAppleScript(source: try c.decode(String.self, forKey: .source))
        case "runShell":
            self = .runShell(command: try c.decode(String.self, forKey: .command),
                             timeoutMs: try c.decodeIfPresent(Int.self, forKey: .timeoutMs) ?? 30_000)
        case "setClipboard":
            self = .setClipboard(try c.decode(String.self, forKey: .text))
        case "notify":
            self = .notify(title: try c.decode(String.self, forKey: .title),
                           body: try c.decodeIfPresent(String.self, forKey: .body) ?? "")
        case "macControl":
            self = .macControl(try c.decode(String.self, forKey: .control))
        case "repeat":
            self = .repeatBlock(count: try c.decode(Int.self, forKey: .count),
                                steps: try c.decode([MacroStep].self, forKey: .steps))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "Unknown step type \"\(type)\"")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(typeName, forKey: .type)
        switch self {
        case .keystroke(let k):
            try c.encode(k.key, forKey: .key)
            if !k.modifiers.isEmpty { try c.encode(k.modifiers, forKey: .modifiers) }
        case .typeText(let t):
            try c.encode(t, forKey: .text)
        case .click(let b, let p, let n, let m):
            try c.encode(b, forKey: .button)
            try c.encode(p, forKey: .at)
            try c.encode(n, forKey: .count)
            if !m.isEmpty { try c.encode(m, forKey: .modifiers) }
        case .moveMouse(let p):
            try c.encode(p, forKey: .to)
        case .drag(let b, let from, let to, let d):
            try c.encode(b, forKey: .button)
            try c.encode(from, forKey: .from)
            try c.encode(to, forKey: .to)
            try c.encode(d, forKey: .durationMs)
        case .scroll(let dx, let dy):
            try c.encode(dx, forKey: .dx)
            try c.encode(dy, forKey: .dy)
        case .wait(let ms):
            try c.encode(ms, forKey: .ms)
        case .waitForApp(let id, let t):
            try c.encode(id, forKey: .bundleID)
            try c.encode(t, forKey: .timeoutMs)
        case .openApp(let id):
            try c.encode(id, forKey: .bundleID)
        case .openURL(let u):
            try c.encode(u, forKey: .url)
        case .openFile(let p):
            try c.encode(p, forKey: .path)
        case .runShortcut(let n, let input):
            try c.encode(n, forKey: .shortcut)
            try c.encodeIfPresent(input, forKey: .input)
        case .runAppleScript(let s):
            try c.encode(s, forKey: .source)
        case .runShell(let cmd, let t):
            try c.encode(cmd, forKey: .command)
            try c.encode(t, forKey: .timeoutMs)
        case .setClipboard(let t):
            try c.encode(t, forKey: .text)
        case .notify(let t, let b):
            try c.encode(t, forKey: .title)
            try c.encode(b, forKey: .body)
        case .macControl(let id):
            try c.encode(id, forKey: .control)
        case .repeatBlock(let n, let s):
            try c.encode(n, forKey: .count)
            try c.encode(s, forKey: .steps)
        }
    }
}

// MARK: - Macro

/// Where a macro or profile came from. Starters ship with Glasspad and can be
/// edited or deleted like anything else; "Restore starters" brings them back.
public enum ItemOrigin: String, Codable, Sendable {
    case user, starter, recorded
}

public struct Macro: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    /// SF Symbol name shown on the phone button.
    public var symbol: String
    /// Button colour as `#RRGGBB`.
    public var color: String
    public var steps: [MacroStep]
    /// Must be true before any shell or AppleScript step will run.
    public var allowScripts: Bool
    /// Phone gesture names (emitted by the gesture engine) that run this macro.
    public var gestureTriggers: [String]
    /// A global Mac hotkey that runs this macro.
    public var hotkey: KeyCombo?
    public var origin: ItemOrigin

    public init(id: UUID = UUID(), name: String, symbol: String = "bolt.fill", color: String = "#0A84FF",
                steps: [MacroStep], allowScripts: Bool = false, gestureTriggers: [String] = [],
                hotkey: KeyCombo? = nil, origin: ItemOrigin = .user) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.color = color
        self.steps = steps
        self.allowScripts = allowScripts
        self.gestureTriggers = gestureTriggers
        self.hotkey = hotkey
        self.origin = origin
    }

    enum CodingKeys: String, CodingKey {
        case id, name, symbol, color, steps, allowScripts, gestureTriggers, hotkey, origin
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "bolt.fill"
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "#0A84FF"
        steps = try c.decode([MacroStep].self, forKey: .steps)
        allowScripts = try c.decodeIfPresent(Bool.self, forKey: .allowScripts) ?? false
        gestureTriggers = try c.decodeIfPresent([String].self, forKey: .gestureTriggers) ?? []
        hotkey = try c.decodeIfPresent(KeyCombo.self, forKey: .hotkey)
        origin = try c.decodeIfPresent(ItemOrigin.self, forKey: .origin) ?? .user
    }

    public var needsScriptPermission: Bool { steps.contains(where: \.needsScriptPermission) }
}
