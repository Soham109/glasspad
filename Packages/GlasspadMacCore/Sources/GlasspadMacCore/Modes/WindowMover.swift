import AppKit
import ApplicationServices
import GlasspadKit

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

    convenience init(_ pair: (app: AXUIElement, window: AXUIElement)) {
        self.init(app: pair.app, window: pair.window)
    }

    var frame: CGRect? { AXUI.frame(window) }
    var isFullScreen: Bool { AXUI.bool(window, "AXFullScreen") == true }
    var isMinimized: Bool { AXUI.bool(window, kAXMinimizedAttribute) == true }
    var windowID: UInt32? { WindowMover.windowID(window) }
    var title: String? { AXUI.string(window, kAXTitleAttribute) }
    func exitFullScreen() -> Bool { AXUI.set(window, "AXFullScreen", false) }
    func setPosition(_ origin: CGPoint) -> Bool { AXUI.setPosition(window, origin) }
    func setSize(_ size: CGSize) -> Bool { AXUI.setSize(window, size) }
}

/// Moves real windows with the Accessibility API, preferring macOS's own Arrange items where
/// they do the same thing and falling back to the app's Move & Resize items when a window
/// refuses to be set directly.
@MainActor
enum WindowMover {
    typealias Pair = (app: AXUIElement, window: AXUIElement)

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
        WindowArranger(displays: screens.map(\.frame), history: .shared) { Thread.sleep(forTimeInterval: $0) }
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
        WindowHistory.shared.remember(w)
        return pressMenuItem(placement, app: app) ? .success(()) : .failure(.refused(w.appName))
    }

    /// Return to Previous Size: back where Glasspad found the front window before it last
    /// moved it, else macOS's own item (for a window macOS tiled).
    static func returnToPreviousSize() -> Result<Void, WindowFailure> {
        guard AXIsProcessTrusted() else { return .failure(.noPermission) }
        guard let (app, window) = frontWindow() else { return .failure(.noWindow) }
        let w = AXMovableWindow(app: app, window: window)
        let failure = withoutEnhancedUI([app]) { arranger(screens()).returnToPreviousSize(w) }
        if failure == .noPreviousSize, pressReturnToPreviousSize(app: app) { return .success(()) }
        return failure.map { .failure($0) } ?? .success(())
    }

    /// The front window on the left half of its display and the one behind it on the right.
    static func split() -> Result<Void, WindowFailure> {
        guard AXIsProcessTrusted() else { return .failure(.noPermission) }
        let windows = frontWindows(limit: 2)
        let all = screens()
        let candidates = windows.map { pair in
            let w = AXMovableWindow(pair)
            return SplitScreen.Candidate(app: w.appName, frame: w.frame ?? .zero, isFullScreen: w.isFullScreen)
        }
        let choice: SplitScreen.Choice
        switch SplitScreen.choose(candidates, displays: all.map(\.frame)) {
        case .success(let c): choice = c
        case .failure(let f): return .failure(f)
        }
        let screen = all[choice.display]
        return arrange([windows[choice.left], windows[choice.right]], .leftAndRight, in: screen.visible, gap: gap(),
                       displayName: screen.name).map { .failure($0) } ?? .success(())
    }

    /// Windows in their places on `visible`, first window first. macOS's own Arrange item when
    /// every window is already on that display (in front, in order) and the app has the item,
    /// checked once it has landed; otherwise, or when it did not land, Glasspad brings the
    /// windows over and sizes them itself. nil when it worked.
    static func arrange(_ pairs: [Pair], _ arrangement: WindowArrangement, in visible: CGRect, gap: CGFloat,
                        displayName: String) -> WindowFailure? {
        let windows = pairs.map(AXMovableWindow.init)
        let all = screens()
        let arranger = arranger(all)
        for w in windows where !arranger.leaveFullScreen(w) { return .fullScreen(w.appName) }
        if tryNative(windows, arrangement, in: visible, screens: all) { return nil }
        let failure = withoutEnhancedUI(pairs.map(\.app)) {
            arranger.arrange(windows, arrangement, in: visible, gap: gap, displayName: displayName)
        }
        // Bring them forward, the last first, so none is left behind other windows.
        for w in windows.reversed() { bringForward((w.app, w.window)) }
        return failure
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

    /// Moves one window to `target` the way that works across displays (`WindowArranger`),
    /// remembering where it was for Return to Previous Size. True once it is there, or as
    /// close as its own minimum or maximum size allows.
    static func set(_ window: AXUIElement, app: AXUIElement, to target: CGRect) -> Bool {
        withoutEnhancedUI([app]) {
            arranger(screens()).place(AXMovableWindow(app: app, window: window), to: target).frame != nil
        }
    }

    // MARK: macOS's own Arrange

    /// macOS's Arrange item for the windows, when it can do exactly this: true once every
    /// window sits in its place.
    private static func tryNative(_ windows: [AXMovableWindow], _ arrangement: WindowArrangement, in visible: CGRect,
                                  screens all: [TilingScreen]) -> Bool {
        let frames = all.map(\.frame)
        guard let target = DisplayGeometry.displayIndex(for: visible, in: frames) else { return false }
        let ids = windows.compactMap(\.windowID)
        let displays = windows.map { $0.frame.flatMap { DisplayGeometry.displayIndex(for: $0, in: frames) } }
        func fits() -> Bool {
            ArrangementLayout.nativeFits(arrangement, windowDisplays: displays, target: target,
                                         frontOrder: frontWindowIDs(limit: windows.count), windows: ids)
        }
        guard ids.count == windows.count,
              ArrangementLayout.nativeFits(arrangement, windowDisplays: displays, target: target,
                                           frontOrder: ids, windows: ids) else { return false }
        if !fits() {
            // In front, in order: the last first.
            for w in windows.reversed() { bringForward((w.app, w.window)) }
            guard wait(0.5, until: fits) else { return false }
        }
        guard let item = arrangeItem(arrangement, app: windows[0].app) else { return false }
        for w in windows { WindowHistory.shared.remember(w) }
        guard AXUI.press(item) else { return false }
        // macOS animates there.
        return wait(0.8) {
            let now = windows.compactMap(\.frame)
            return now.count == windows.count && ArrangementLayout.looksArranged(arrangement, frames: now, in: visible)
        }
    }

    /// Window > Move & Resize > Arrange > this arrangement, found by its shortcut (Quarters, which
    /// has none, by its place after the others). nil when the app does not have it or it is off.
    private static func arrangeItem(_ arrangement: WindowArrangement, app: AXUIElement) -> AXUIElement? {
        guard let menu = moveResizeMenu(app) else { return nil }
        let entries = menu.items.map(entry)
        let index = arrangement == .quarters
            ? MoveResizeMenu.quartersArrangeIndex(in: entries)
            : entries.firstIndex { $0.shortcut.flatMap(MoveResizeMenu.arrangement) == arrangement }
        guard let index, AXUI.bool(menu.items[index], kAXEnabledAttribute) != false else { return nil }
        return menu.items[index]
    }

    // MARK: Menus

    /// The app's Move & Resize items, and the Window menu's items with Move & Resize's index
    /// among them, found from the Left half item by its shortcut.
    static func moveResizeMenu(_ app: AXUIElement) -> (items: [AXUIElement], window: [AXUIElement], index: Int)? {
        guard let bar = AXUI.element(app, kAXMenuBarAttribute) else { return nil }
        let left = AXUI.first(in: bar, maxDepth: 6, budget: 3000) { e in
            guard AXUI.string(e, kAXRoleAttribute) == kAXMenuItemRole as String, let s = shortcut(e) else { return false }
            return MoveResizeMenu.matches(s, .left)
        }
        guard let left, let menu = AXUI.element(left, kAXParentAttribute), let item = AXUI.element(menu, kAXParentAttribute),
              let windowMenu = AXUI.element(item, kAXParentAttribute) else { return nil }
        let windowItems = AXUI.children(windowMenu)
        guard let index = windowItems.firstIndex(where: { CFEqual($0, item) }) else { return nil }
        return (AXUI.children(menu), windowItems, index)
    }

    static func shortcut(_ e: AXUIElement) -> MoveResizeMenu.Shortcut? {
        let char = AXUI.string(e, kAXMenuItemCmdCharAttribute), key = AXUI.int(e, kAXMenuItemCmdVirtualKeyAttribute)
        let glyph = AXUI.int(e, kAXMenuItemCmdGlyphAttribute)
        guard char != nil || key != nil || glyph != nil, let mods = AXUI.int(e, kAXMenuItemCmdModifiersAttribute) else { return nil }
        return MoveResizeMenu.Shortcut(char: char, virtualKey: key, glyph: glyph, modifiers: mods)
    }

    static func entry(_ e: AXUIElement) -> MoveResizeMenu.Entry {
        let submenu = AXUI.children(e).first { AXUI.string($0, kAXRoleAttribute) == kAXMenuRole as String }
        return MoveResizeMenu.Entry(AXUI.string(e, kAXTitleAttribute) ?? "", shortcut(e),
                                    submenu: submenu.map { !AXUI.children($0).isEmpty } ?? false)
    }

    /// Window > Move & Resize > the item for this placement: by its shortcut, a quarter by its place.
    private static func pressMenuItem(_ placement: WindowPlacement, app: AXUIElement) -> Bool {
        guard let menu = moveResizeMenu(app) else { return false }
        let entries = menu.items.map(entry)
        let index: Int?
        switch placement {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: index = MoveResizeMenu.quarterIndex(placement, in: entries)
        default: index = entries.firstIndex { $0.shortcut.map { MoveResizeMenu.matches($0, placement) } ?? false }
        }
        guard let index, AXUI.bool(menu.items[index], kAXEnabledAttribute) != false else { return false }
        return AXUI.press(menu.items[index])
    }

    private static func pressReturnToPreviousSize(app: AXUIElement) -> Bool {
        guard let menu = moveResizeMenu(app) else { return false }
        guard let item = menu.items.first(where: { shortcut($0).map(MoveResizeMenu.isReturnToPreviousSize) ?? false }),
              AXUI.bool(item, kAXEnabledAttribute) != false else { return false }
        return AXUI.press(item)
    }

    // MARK: Private

    /// "Enhanced user interface", which some apps turn on for assistive tools, animates every
    /// change and makes sizes land wrong, so it is off while moving.
    static func withoutEnhancedUI<T>(_ apps: [AXUIElement], _ body: () -> T) -> T {
        let enhanced = apps.filter { AXUI.bool($0, "AXEnhancedUserInterface") == true }
        for app in enhanced { AXUI.set(app, "AXEnhancedUserInterface", false) }
        defer { for app in enhanced { AXUI.set(app, "AXEnhancedUserInterface", true) } }
        return body()
    }

    /// Reads until `done` or `seconds` pass (macOS animates moves and activation).
    static func wait(_ seconds: TimeInterval, until done: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if done() { return true }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return done()
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

    /// Ordinary windows on screen, any app, front to back, as the window server lists them
    /// (minimized ones are not on screen).
    private static func onScreen() -> [(pid: pid_t, id: CGWindowID, bounds: CGRect)] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let wid = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= 120, bounds.height >= 80 else { return nil }
            return (pid, wid, bounds)
        }
    }

    private static func frontWindowIDs(limit: Int) -> [UInt32] { onScreen().prefix(limit).map(\.id) }

    /// The front `limit` ordinary windows on screen, any app, front to back.
    private static func frontWindows(limit: Int) -> [Pair] {
        var out: [Pair] = []
        var apps: [pid_t: AXUIElement] = [:]
        for w in onScreen() {
            let app = apps[w.pid] ?? AXUIElementCreateApplication(w.pid)
            AXUIElementSetMessagingTimeout(app, 1)
            apps[w.pid] = app
            let candidates = AXUI.elements(app, kAXWindowsAttribute)
            let match = candidates.first { windowID($0) == w.id }
                ?? candidates.first { AXUI.frame($0).map { WindowTiling.isClose($0, w.bounds) } ?? false }
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
    static func bringForward(_ w: Pair) {
        // Through Accessibility: a menu bar app can't take activation from the app in front.
        AXUI.set(w.app, kAXFrontmostAttribute, true)
        AXUIElementPerformAction(w.window, kAXRaiseAction as CFString)
    }
}
