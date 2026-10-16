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

    /// The same place in the Displays screen's terms.
    public var tile: WindowTile {
        switch self {
        case .left: .leftHalf
        case .right: .rightHalf
        case .top: .topHalf
        case .bottom: .bottomHalf
        case .fill: .fill
        case .center: .center
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
    /// "Studio Display", for messages.
    public var name: String

    public init(frame: CGRect, visible: CGRect, name: String = "this display") {
        self.frame = frame
        self.visible = visible
        self.name = name
    }
}

/// The frame math behind the window buttons, in the terms they use. The math itself is
/// `DisplayGeometry` (GlasspadKit), shared with the Displays screen on both sides.
public enum WindowTiling {
    /// The gap macOS leaves around tiled windows when "Tiled windows have margins" is on.
    public static let margin: CGFloat = DisplayGeometry.tileMargin

    /// A Cocoa screen rectangle (origin bottom-left of the main display, y up) in Quartz
    /// coordinates. `mainHeight` is the height of the main display.
    public static func quartz(_ cocoa: CGRect, mainHeight: CGFloat) -> CGRect {
        DisplayGeometry.quartz(cocoa, mainHeight: mainHeight)
    }

    /// The screen showing most of the window; the one nearest its centre when it is on none.
    public static func screenIndex(for window: CGRect, in screens: [TilingScreen]) -> Int? {
        DisplayGeometry.displayIndex(for: window, in: screens.map(\.frame))
    }

    /// Where the window goes within `visible` (the screen without menu bar and Dock), with
    /// `gap` points around it and between halves. Whole points, like macOS itself.
    public static func frame(_ placement: WindowPlacement, window: CGRect, in visible: CGRect, gap: CGFloat = 0) -> CGRect {
        DisplayGeometry.tile(placement.tile, window: window, in: visible, gap: gap)
    }

    /// The two halves for Split Screen: front window left, the next one right.
    public static func split(in visible: CGRect, gap: CGFloat = 0) -> (left: CGRect, right: CGRect) {
        DisplayGeometry.split(in: visible, gap: gap)
    }

    /// The window moved from one screen's visible area to another's, keeping where it sits and
    /// how much of the screen it covers (a left half stays a left half).
    public static func moved(_ window: CGRect, from: CGRect, to: CGRect) -> CGRect {
        DisplayGeometry.moved(window, from: from, to: to)
    }

    /// The screen after `index`, going left to right (then top to bottom), wrapping around.
    public static func nextScreenIndex(after index: Int, in screens: [TilingScreen]) -> Int? {
        DisplayGeometry.nextDisplayIndex(after: index, in: screens.map(\.frame))
    }

    /// True when the window already sits at `target` (macOS rounds sizes to what an app allows).
    public static func isClose(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
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

    /// True for Arrange > Left & Right: shift, control and the left arrow, no command or option.
    /// macOS puts the front window on the left and the one behind it on the right.
    public static func isLeftAndRight(_ s: Shortcut) -> Bool {
        guard s.modifiers & 4 != 0, s.modifiers & 8 != 0, s.modifiers & 1 != 0, s.modifiers & 2 == 0 else { return false }
        if s.virtualKey == 123 || s.glyph == 0x64 { return true }
        return s.char?.unicodeScalars.first.map { Int($0.value) == 0xF702 } ?? false
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

/// One window through the Accessibility API, for `WindowArranger`.
@MainActor
final class AXMovableWindow: MovableWindow {
    let app: AXUIElement
    let window: AXUIElement
    let appName: String

    init(app: AXUIElement, window: AXUIElement) {
        self.app = app
        self.window = window
        var pid: pid_t = 0
        let name = AXUIElementGetPid(app, &pid) == .success ? NSRunningApplication(processIdentifier: pid)?.localizedName : nil
        appName = name ?? AXUI.string(app, kAXTitleAttribute) ?? "That app"
    }

    var frame: CGRect? { AXUI.frame(window) }
    var isFullScreen: Bool { AXUI.bool(window, "AXFullScreen") == true }
    var isMinimized: Bool { AXUI.bool(window, kAXMinimizedAttribute) == true }
    func exitFullScreen() -> Bool { AXUI.set(window, "AXFullScreen", false) }
    func setPosition(_ origin: CGPoint) -> Bool { AXUI.setPosition(window, origin) }
    func setSize(_ size: CGSize) -> Bool { AXUI.setSize(window, size) }
}

/// Moves real windows with the Accessibility API, falling back to the app's own Move & Resize
/// menu items when a window refuses to be set directly.
@MainActor
enum WindowMover {
    /// Every display, Quartz coordinates.
    static func screens() -> [TilingScreen] {
        let all = NSScreen.screens
        guard let main = all.first else { return [] }
        let h = main.frame.height
        return all.map { TilingScreen(frame: WindowTiling.quartz($0.frame, mainHeight: h),
                                      visible: WindowTiling.quartz($0.visibleFrame, mainHeight: h), name: $0.localizedName) }
    }

    /// The gap from "Tiled windows have margins" (on unless the user turned it off).
    static func gap() -> CGFloat {
        CFPreferencesAppSynchronize("com.apple.WindowManager" as CFString)
        let on = CFPreferencesCopyAppValue("EnableTiledWindowMargins" as CFString, "com.apple.WindowManager" as CFString) as? Bool
        return on ?? true ? WindowTiling.margin : 0
    }

    static func arranger(_ screens: [TilingScreen]) -> WindowArranger {
        WindowArranger(displays: screens.map(\.frame)) { Thread.sleep(forTimeInterval: $0) }
    }

    static func place(_ placement: WindowPlacement) -> Result<Void, WindowFailure> {
        guard AXIsProcessTrusted() else { return .failure(.noPermission) }
        guard let (app, window) = frontWindow() else { return .failure(.noWindow) }
        let w = AXMovableWindow(app: app, window: window)
        let all = screens()
        if !arranger(all).leaveFullScreen(w) { return .failure(.fullScreen(w.appName)) }
        guard let current = w.frame, let i = WindowTiling.screenIndex(for: current, in: all) else { return .failure(.noWindow) }
        let target = WindowTiling.frame(placement, window: current, in: all[i].visible, gap: gap())
        if set(window, app: app, to: target) { return .success(()) }
        return pressMenuItem(placement, app: app) ? .success(()) : .failure(.refused(w.appName))
    }

    /// The front window on the left half of its display and the one behind it on the right.
    /// macOS's own Window > Move & Resize > Arrange > Left & Right when both are already on that
    /// display; otherwise (or when it does not land) Glasspad moves the second window over to
    /// the front window's display and sizes both itself.
    static func split() -> Result<Void, WindowFailure> {
        guard AXIsProcessTrusted() else { return .failure(.noPermission) }
        let windows = frontWindows(limit: 2).map { AXMovableWindow(app: $0.app, window: $0.window) }
        let all = screens()
        let candidates = windows.map { SplitScreen.Candidate(app: $0.appName, frame: $0.frame ?? .zero, isFullScreen: $0.isFullScreen) }
        let choice: SplitScreen.Choice
        switch SplitScreen.choose(candidates, displays: all.map(\.frame)) {
        case .success(let c): choice = c
        case .failure(let f): return .failure(f)
        }
        let first = windows[choice.left], second = windows[choice.right], screen = all[choice.display]
        // Out of full screen first, as macOS does when a full-screen window is tiled.
        for w in [first, second] where !arranger(all).leaveFullScreen(w) { return .failure(.fullScreen(w.appName)) }
        let sameDisplay = WindowTiling.screenIndex(for: second.frame ?? candidates[choice.right].frame, in: all) == choice.display
        if sameDisplay, pressLeftAndRight(app: first.app), nativeSplitLanded(first, second, in: screen.visible) {
            return .success(())
        }
        let failure = withoutEnhancedUI([first.app, second.app]) {
            arranger(all).split(left: first, right: second, in: screen.visible, gap: gap(), displayName: screen.name)
        }
        // Bring both forward, the right one first, so neither half is left behind other windows.
        bringForward((second.app, second.window))
        bringForward((first.app, first.window))
        return failure.map { .failure($0) } ?? .success(())
    }

    static func toNextScreen() -> Result<Void, WindowFailure> {
        guard AXIsProcessTrusted() else { return .failure(.noPermission) }
        let all = screens()
        guard all.count > 1 else { return .failure(.oneScreen) }
        guard let (app, window) = frontWindow() else { return .failure(.noWindow) }
        let w = AXMovableWindow(app: app, window: window)
        if !arranger(all).leaveFullScreen(w) { return .failure(.fullScreen(w.appName)) }
        guard let current = w.frame, let i = WindowTiling.screenIndex(for: current, in: all),
              let next = WindowTiling.nextScreenIndex(after: i, in: all) else { return .failure(.noWindow) }
        let target = WindowTiling.moved(current, from: all[i].visible, to: all[next].visible)
        return set(window, app: app, to: target) ? .success(()) : .failure(.refused(w.appName))
    }

    /// Moves one window to `target` the way that works across displays (`WindowArranger`).
    /// True once it is there, or as close as its own minimum or maximum size allows.
    static func set(_ window: AXUIElement, app: AXUIElement, to target: CGRect) -> Bool {
        withoutEnhancedUI([app]) {
            arranger(screens()).move(AXMovableWindow(app: app, window: window), to: target).frame != nil
        }
    }

    /// Two windows side by side on `visible`, for Displays' Split With. nil when it worked.
    static func split(left: (app: AXUIElement, window: AXUIElement), right: (app: AXUIElement, window: AXUIElement),
                      in visible: CGRect, gap: CGFloat, displayName: String) -> WindowFailure? {
        let l = AXMovableWindow(app: left.app, window: left.window), r = AXMovableWindow(app: right.app, window: right.window)
        return withoutEnhancedUI([left.app, right.app]) {
            arranger(screens()).split(left: l, right: r, in: visible, gap: gap, displayName: displayName)
        }
    }

    // MARK: Private

    /// "Enhanced user interface", which some apps turn on for assistive tools, animates every
    /// change and makes sizes land wrong, so it is off while moving.
    private static func withoutEnhancedUI<T>(_ apps: [AXUIElement], _ body: () -> T) -> T {
        let enhanced = apps.filter { AXUI.bool($0, "AXEnhancedUserInterface") == true }
        for app in enhanced { AXUI.set(app, "AXEnhancedUserInterface", false) }
        defer { for app in enhanced { AXUI.set(app, "AXEnhancedUserInterface", true) } }
        return body()
    }

    /// After Left & Right: true once both windows sit on their sides (macOS animates there).
    private static func nativeSplitLanded(_ left: AXMovableWindow, _ right: AXMovableWindow, in visible: CGRect) -> Bool {
        let deadline = Date().addingTimeInterval(0.6)
        repeat {
            if let l = left.frame, let r = right.frame, SplitScreen.looksSplit(left: l, right: r, in: visible) { return true }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return false
    }

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

    /// The front `limit` ordinary windows on screen, any app, front to back (minimized ones are
    /// not on screen).
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
    static func windowID(_ window: AXUIElement) -> CGWindowID? {
        guard let getWindow else { return nil }
        var id = CGWindowID(0)
        return getWindow(window, &id) == .success && id != 0 ? id : nil
    }

    /// Raises the window and activates its app (a raised window of an app behind stays hidden).
    private static func bringForward(_ w: (app: AXUIElement, window: AXUIElement)) {
        // Through Accessibility: a menu bar app can't take activation from the app in front.
        AXUI.set(w.app, kAXFrontmostAttribute, true)
        AXUIElementPerformAction(w.window, kAXRaiseAction as CFString)
    }

    /// Window > Move & Resize > Left & Right in the front app, found by its shortcut.
    private static func pressLeftAndRight(app: AXUIElement) -> Bool {
        guard let bar = AXUI.element(app, kAXMenuBarAttribute) else { return false }
        let item = AXUI.first(in: bar, maxDepth: 6, budget: 3000) { e in
            guard AXUI.string(e, kAXRoleAttribute) == kAXMenuItemRole as String,
                  let mods = AXUI.int(e, kAXMenuItemCmdModifiersAttribute) else { return false }
            return MoveResizeMenu.isLeftAndRight(MoveResizeMenu.Shortcut(
                char: AXUI.string(e, kAXMenuItemCmdCharAttribute), virtualKey: AXUI.int(e, kAXMenuItemCmdVirtualKeyAttribute),
                glyph: AXUI.int(e, kAXMenuItemCmdGlyphAttribute), modifiers: mods))
        }
        guard let item, AXUI.bool(item, kAXEnabledAttribute) != false else { return false }
        return AXUI.press(item)
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
