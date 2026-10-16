import AppKit
import ApplicationServices
import GlasspadKit

/// Where a tiling button puts the front window.
public enum WindowPlacement: String, Sendable, CaseIterable {
    case left, right, top, bottom, fill, center

    public init?(_ action: DeckSystemAction) {
        switch action {
        case .windowLeft: self = .left
        case .windowRight: self = .right
        case .windowTop: self = .top
        case .windowBottom: self = .bottom
        case .windowFill: self = .fill
        case .windowCenter: self = .center
        default: return nil
        }
    }
}

/// One display, in Quartz global coordinates (origin at the top-left of the main display, y
/// grows downwards: the space the Accessibility API uses for window frames).
public struct TilingScreen: Equatable, Sendable {
    /// The whole display.
    public var frame: CGRect
    /// Without the menu bar and the Dock.
    public var visible: CGRect

    public init(frame: CGRect, visible: CGRect) {
        self.frame = frame
        self.visible = visible
    }
}

/// The frame math behind the window buttons. Pure, so it is tested without moving anything.
public enum WindowTiling {
    /// The gap macOS leaves around tiled windows when "Tiled windows have margins" is on.
    public static let margin: CGFloat = 8

    /// A Cocoa screen rectangle (origin bottom-left of the main display, y up) in Quartz
    /// coordinates. `mainHeight` is the height of the main display (the one with the menu bar
    /// at the origin).
    public static func quartz(_ cocoa: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: cocoa.minX, y: mainHeight - cocoa.maxY, width: cocoa.width, height: cocoa.height)
    }

    /// The screen showing most of the window; the one under its centre when it is on none.
    public static func screenIndex(for window: CGRect, in screens: [TilingScreen]) -> Int? {
        guard !screens.isEmpty else { return nil }
        let areas = screens.map { s -> CGFloat in
            let i = s.frame.intersection(window)
            return i.isNull ? 0 : i.width * i.height
        }
        if let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 { return best }
        let centre = CGPoint(x: window.midX, y: window.midY)
        func distance(_ r: CGRect) -> CGFloat {
            let dx = max(r.minX - centre.x, 0, centre.x - r.maxX), dy = max(r.minY - centre.y, 0, centre.y - r.maxY)
            return dx * dx + dy * dy
        }
        return screens.indices.min { distance(screens[$0].frame) < distance(screens[$1].frame) }
    }

    /// Where the window goes within `visible` (the screen without menu bar and Dock), with
    /// `gap` points around it and between halves. Whole points, like macOS itself.
    public static func frame(_ placement: WindowPlacement, window: CGRect, in visible: CGRect, gap: CGFloat = 0) -> CGRect {
        let area = visible.insetBy(dx: gap, dy: gap)
        let halfW = (area.width - gap) / 2, halfH = (area.height - gap) / 2
        let r: CGRect
        switch placement {
        case .left: r = CGRect(x: area.minX, y: area.minY, width: halfW, height: area.height)
        case .right: r = CGRect(x: area.maxX - halfW, y: area.minY, width: halfW, height: area.height)
        case .top: r = CGRect(x: area.minX, y: area.minY, width: area.width, height: halfH)
        case .bottom: r = CGRect(x: area.minX, y: area.maxY - halfH, width: area.width, height: halfH)
        case .fill: r = area
        case .center:
            let w = min(window.width, area.width), h = min(window.height, area.height)
            r = CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
        }
        return r.integral(keepingInside: visible)
    }

    /// The two halves for Split Screen: front window left, the next one right.
    public static func split(in visible: CGRect, gap: CGFloat = 0) -> (left: CGRect, right: CGRect) {
        (frame(.left, window: .zero, in: visible, gap: gap), frame(.right, window: .zero, in: visible, gap: gap))
    }

    /// The window moved from one screen's visible area to another's, keeping where it sits and
    /// how much of the screen it covers (a left half stays a left half).
    public static func moved(_ window: CGRect, from: CGRect, to: CGRect) -> CGRect {
        guard from.width > 0, from.height > 0 else { return frame(.center, window: window, in: to) }
        let sx = to.width / from.width, sy = to.height / from.height
        var r = CGRect(x: to.minX + (window.minX - from.minX) * sx, y: to.minY + (window.minY - from.minY) * sy,
                       width: window.width * sx, height: window.height * sy)
        r.size.width = min(r.width, to.width)
        r.size.height = min(r.height, to.height)
        r.origin.x = min(max(r.minX, to.minX), to.maxX - r.width)
        r.origin.y = min(max(r.minY, to.minY), to.maxY - r.height)
        return r.integral(keepingInside: to)
    }

    /// The screen after `index`, going left to right (then top to bottom), wrapping around.
    public static func nextScreenIndex(after index: Int, in screens: [TilingScreen]) -> Int? {
        guard screens.count > 1, screens.indices.contains(index) else { return nil }
        let order = screens.indices.sorted {
            let a = screens[$0].frame, b = screens[$1].frame
            return a.minX != b.minX ? a.minX < b.minX : a.minY < b.minY
        }
        guard let at = order.firstIndex(of: index) else { return nil }
        return order[(at + 1) % order.count]
    }

    /// True when the window already sits at `target` (macOS rounds sizes to what an app allows).
    public static func isClose(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}

private extension CGRect {
    /// Rounded to whole points without spilling outside `bounds`.
    func integral(keepingInside bounds: CGRect) -> CGRect {
        var x = minX.rounded(), y = minY.rounded(), w = width.rounded(), h = height.rounded()
        x = Swift.max(x, bounds.minX.rounded(.up))
        y = Swift.max(y, bounds.minY.rounded(.up))
        w = Swift.max(0, Swift.min(w, bounds.maxX.rounded(.down) - x))
        h = Swift.max(0, Swift.min(h, bounds.maxY.rounded(.down) - y))
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

// MARK: - Move & Resize menu

/// Finds an app's Window > Move & Resize item for a placement by its keyboard shortcut
/// (fn control plus an arrow, F or C since macOS 15), so it works in every language.
public enum MoveResizeMenu {
    /// What the Accessibility API says about a menu item's shortcut.
    public struct Shortcut: Equatable, Sendable {
        public var char: String?
        public var virtualKey: Int?
        public var glyph: Int?
        /// `AXMenuItemCmdModifiers`: shift 1, option 2, control 4, no command 8.
        public var modifiers: Int

        public init(char: String? = nil, virtualKey: Int? = nil, glyph: Int? = nil, modifiers: Int) {
            self.char = char
            self.virtualKey = virtualKey
            self.glyph = glyph
            self.modifiers = modifiers
        }
    }

    /// True when the shortcut is the one macOS gives this placement.
    public static func matches(_ s: Shortcut, _ placement: WindowPlacement) -> Bool {
        // Control, and no command key.
        guard s.modifiers & 4 != 0, s.modifiers & 8 != 0, s.modifiers & 3 == 0 else { return false }
        let arrow: (key: Int, glyph: Int, char: Int)?
        switch placement {
        case .left: arrow = (123, 0x64, 0xF702)
        case .right: arrow = (124, 0x65, 0xF703)
        case .top: arrow = (126, 0x68, 0xF700)
        case .bottom: arrow = (125, 0x6A, 0xF701)
        case .fill: return s.char?.uppercased() == "F"
        case .center: return s.char?.uppercased() == "C"
        }
        guard let arrow else { return false }
        if s.virtualKey == arrow.key || s.glyph == arrow.glyph { return true }
        return s.char?.unicodeScalars.first.map { Int($0.value) == arrow.char } ?? false
    }
}

// MARK: - Live windows

/// Moves real windows with the Accessibility API, falling back to the app's own Move & Resize
/// menu items when a window refuses to be set directly.
@MainActor
enum WindowMover {
    /// Both a problem the user can fix and a short message for the phone.
    enum Failure: Error, Equatable {
        case noPermission, noWindow, fullScreen, refused, oneScreen, noSecondWindow

        var message: String {
            switch self {
            case .noPermission: AXUI.permissionHint
            case .noWindow: "No window to move"
            case .fullScreen: "That window is in full screen"
            case .refused: "That window cannot be moved"
            case .oneScreen: "Only one display is connected"
            case .noSecondWindow: "Open a second window to split the screen"
            }
        }
    }

    /// Every display, Quartz coordinates.
    static func screens() -> [TilingScreen] {
        let all = NSScreen.screens
        guard let main = all.first else { return [] }
        let h = main.frame.height
        return all.map { TilingScreen(frame: WindowTiling.quartz($0.frame, mainHeight: h),
                                      visible: WindowTiling.quartz($0.visibleFrame, mainHeight: h)) }
    }

    /// The gap from "Tiled windows have margins" (on unless the user turned it off).
    static func gap() -> CGFloat {
        CFPreferencesAppSynchronize("com.apple.WindowManager" as CFString)
        let on = CFPreferencesCopyAppValue("EnableTiledWindowMargins" as CFString, "com.apple.WindowManager" as CFString) as? Bool
        return on ?? true ? WindowTiling.margin : 0
    }

    static func place(_ placement: WindowPlacement) -> Result<Void, Failure> {
        guard AXIsProcessTrusted() else { return .failure(.noPermission) }
        guard let (app, window) = frontWindow() else { return .failure(.noWindow) }
        if AXUI.bool(window, "AXFullScreen") == true { return .failure(.fullScreen) }
        let all = screens()
        guard let current = AXUI.frame(window), let i = WindowTiling.screenIndex(for: current, in: all) else {
            return .failure(.noWindow)
        }
        let target = WindowTiling.frame(placement, window: current, in: all[i].visible, gap: gap())
        if set(window, app: app, to: target) { return .success(()) }
        return pressMenuItem(placement, app: app) ? .success(()) : .failure(.refused)
    }

    static func split() -> Result<Void, Failure> {
        guard AXIsProcessTrusted() else { return .failure(.noPermission) }
        let windows = frontWindows(limit: 2)
        guard let first = windows.first else { return .failure(.noWindow) }
        guard windows.count == 2 else { return .failure(.noSecondWindow) }
        let all = screens()
        guard let frame = AXUI.frame(first.window), let i = WindowTiling.screenIndex(for: frame, in: all) else {
            return .failure(.noWindow)
        }
        let halves = WindowTiling.split(in: all[i].visible, gap: gap())
        let second = windows[1]
        let ok = set(second.window, app: second.app, to: halves.right) && set(first.window, app: first.app, to: halves.left)
        AXUIElementPerformAction(second.window, kAXRaiseAction as CFString)
        AXUIElementPerformAction(first.window, kAXRaiseAction as CFString)
        return ok ? .success(()) : .failure(.refused)
    }

    static func toNextScreen() -> Result<Void, Failure> {
        guard AXIsProcessTrusted() else { return .failure(.noPermission) }
        let all = screens()
        guard all.count > 1 else { return .failure(.oneScreen) }
        guard let (app, window) = frontWindow() else { return .failure(.noWindow) }
        if AXUI.bool(window, "AXFullScreen") == true { return .failure(.fullScreen) }
        guard let current = AXUI.frame(window), let i = WindowTiling.screenIndex(for: current, in: all),
              let next = WindowTiling.nextScreenIndex(after: i, in: all) else { return .failure(.noWindow) }
        let target = WindowTiling.moved(current, from: all[i].visible, to: all[next].visible)
        return set(window, app: app, to: target) ? .success(()) : .failure(.refused)
    }

    // MARK: Private

    /// The frontmost app's focused (else main) window.
    private static func frontWindow() -> (AXUIElement, AXUIElement)? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        for name in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let w = AXUI.element(app, name), AXUI.string(w, kAXSubroleAttribute) != "AXSystemDialog" { return (app, w) }
        }
        return AXUI.elements(app, kAXWindowsAttribute).first.map { (app, $0) }
    }

    /// The front `limit` ordinary windows on screen, any app, front to back.
    private static func frontWindows(limit: Int) -> [(app: AXUIElement, window: AXUIElement)] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        var out: [(AXUIElement, AXUIElement)] = []
        var apps: [pid_t: AXUIElement] = [:]
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let wid = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= 120, bounds.height >= 80 else { continue }
            let app = apps[pid] ?? AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 1)
            apps[pid] = app
            let candidates = AXUI.elements(app, kAXWindowsAttribute)
            let match = candidates.first { windowID($0) == wid }
                ?? candidates.first { AXUI.frame($0).map { WindowTiling.isClose($0, bounds) } ?? false }
            guard let match, AXUI.bool(match, "AXMinimized") != true else { continue }
            out.append((app, match))
            if out.count == limit { break }
        }
        return out
    }

    private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let getWindow: GetWindowFn? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(sym, to: GetWindowFn.self)
    }()

    /// The window server id of an Accessibility window (private, with a frame match as fallback).
    private static func windowID(_ window: AXUIElement) -> CGWindowID? {
        guard let getWindow else { return nil }
        var id = CGWindowID(0)
        return getWindow(window, &id) == .success && id != 0 ? id : nil
    }

    /// Size, position, size again (a window crossing displays can be limited by the screen it
    /// starts on). "Enhanced user interface", which some apps turn on for assistive tools,
    /// animates every change and makes sizes land wrong, so it is off while moving.
    private static func set(_ window: AXUIElement, app: AXUIElement, to target: CGRect) -> Bool {
        let enhanced = AXUI.bool(app, "AXEnhancedUserInterface") == true
        if enhanced { AXUI.set(app, "AXEnhancedUserInterface", false) }
        defer { if enhanced { AXUI.set(app, "AXEnhancedUserInterface", true) } }
        let sized = AXUI.setSize(window, target.size)
        let moved = AXUI.setPosition(window, target.origin)
        AXUI.setSize(window, target.size)
        guard sized || moved else { return false }
        guard let now = AXUI.frame(window) else { return moved }
        // A window with a fixed or minimum size still counts once it is where it should be.
        return WindowTiling.isClose(now, target) || (moved && abs(now.minX - target.minX) <= 2 && abs(now.minY - target.minY) <= 2)
    }

    /// Window > Move & Resize > the item for this placement, found by its shortcut.
    private static func pressMenuItem(_ placement: WindowPlacement, app: AXUIElement) -> Bool {
        guard let bar = AXUI.element(app, kAXMenuBarAttribute) else { return false }
        let item = AXUI.first(in: bar, maxDepth: 6, budget: 3000) { e in
            guard AXUI.string(e, kAXRoleAttribute) == kAXMenuItemRole as String,
                  let mods = AXUI.int(e, kAXMenuItemCmdModifiersAttribute) else { return false }
            let shortcut = MoveResizeMenu.Shortcut(char: AXUI.string(e, kAXMenuItemCmdCharAttribute),
                                                   virtualKey: AXUI.int(e, kAXMenuItemCmdVirtualKeyAttribute),
                                                   glyph: AXUI.int(e, kAXMenuItemCmdGlyphAttribute), modifiers: mods)
            return MoveResizeMenu.matches(shortcut, placement)
        }
        guard let item, AXUI.bool(item, kAXEnabledAttribute) != false else { return false }
        return AXUI.press(item)
    }
}
