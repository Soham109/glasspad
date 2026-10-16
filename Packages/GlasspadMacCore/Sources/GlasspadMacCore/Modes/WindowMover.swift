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
/// refuses to be set directly. Every wait is a task sleep, so the main thread (and the menu
/// bar icon) never stops while windows animate.
@MainActor
enum WindowMover {
    typealias Pair = (app: AXUIElement, window: AXUIElement)

    /// Every display, Quartz coordinates. `visible` leaves room for Stage Manager's strip.
    static func screens() -> [TilingScreen] {
        let all = NSScreen.screens
        guard let main = all.first else { return [] }
        let h = main.frame.height
        return all.map {
            TilingScreen(frame: WindowTiling.quartz($0.frame, mainHeight: h),
                         visible: tilingArea(WindowTiling.quartz($0.visibleFrame, mainHeight: h)), name: $0.localizedName)
        }
    }

    /// The gap from "Tiled windows have margins" (on unless the user turned it off).
    static func gap() -> CGFloat {
        CFPreferencesAppSynchronize("com.apple.WindowManager" as CFString)
        let on = CFPreferencesCopyAppValue("EnableTiledWindowMargins" as CFString, "com.apple.WindowManager" as CFString) as? Bool
        return on ?? true ? WindowTiling.margin : 0
    }

    /// `visible` without Stage Manager's strip while it is on and shows recent apps.
    static func tilingArea(_ visible: CGRect) -> CGRect {
        let wm = "com.apple.WindowManager" as CFString, dock = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(wm)
        CFPreferencesAppSynchronize(dock)
        let on = CFPreferencesCopyAppValue("GloballyEnabled" as CFString, wm) as? Bool ?? false
        let hidden = CFPreferencesCopyAppValue("AutoHide" as CFString, wm) as? Bool ?? false
        let dockSide = CFPreferencesCopyAppValue("orientation" as CFString, dock) as? String
        return StageManager.tilingArea(visible, enabled: on, recentAppsHidden: hidden, dockOnLeft: dockSide == "left")
    }

    static func arranger(_ screens: [TilingScreen]) -> WindowArranger {
        WindowArranger(displays: screens.map(\.frame), history: .shared) { try? await Task.sleep(for: .seconds($0)) }
    }

    static func place(_ placement: WindowPlacement) async -> Result<Void, WindowFailure> {
        guard AXIsProcessTrusted() else { return .failure(.noPermission) }
        guard let (app, window) = frontWindow() else { return .failure(.noWindow) }
        let w = AXMovableWindow(app: app, window: window)
        let all = screens()
        if !(await arranger(all).leaveFullScreen(w)) { return .failure(.fullScreen(w.appName)) }
        guard let current = w.frame, let i = WindowTiling.screenIndex(for: current, in: all) else { return .failure(.noWindow) }
        let target = WindowTiling.frame(placement, window: current, in: all[i].visible, gap: gap())
        if await set(window, app: app, to: target) { return .success(()) }
        WindowHistory.shared.remember(w)
        return press(app, { MoveResizeMenu.index(placement, in: $0) }) ? .success(()) : .failure(.refused(w.appName))
    }

    /// Return to Previous Size: back where Glasspad found the front window before it last
    /// moved it, else macOS's own item (for a window macOS tiled).
    static func returnToPreviousSize() async -> Result<Void, WindowFailure> {
        guard AXIsProcessTrusted() else { return .failure(.noPermission) }
        guard let (app, window) = frontWindow() else { return .failure(.noWindow) }
        let w = AXMovableWindow(app: app, window: window)
        let failure = await withoutEnhancedUI([app]) { await arranger(screens()).returnToPreviousSize(w) }
        if failure == .noPreviousSize, press(app, MoveResizeMenu.returnIndex) { return .success(()) }
        return failure.map { .failure($0) } ?? .success(())
    }

    /// The front window on the left half of its display and the one behind it on the right.
    static func split() async -> Result<Void, WindowFailure> {
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
        let failure = await arrange([windows[choice.left], windows[choice.right]], .leftAndRight, in: screen.visible, gap: gap(),
                                    displayName: screen.name)
        return failure.map { .failure($0) } ?? .success(())
    }

    /// Windows in their places on `visible`, first window first. macOS's own Arrange item when
    /// every window is already on that display (in front, in order) and the app has the item,
    /// checked once it has landed; otherwise, or when it did not land, Glasspad brings the
    /// windows over and sizes them itself. nil when it worked.
    static func arrange(_ pairs: [Pair], _ arrangement: WindowArrangement, in visible: CGRect, gap: CGFloat,
                        displayName: String) async -> WindowFailure? {
        let windows = pairs.map(AXMovableWindow.init)
        let all = screens()
        let arranger = arranger(all)
        for w in windows {
            guard await arranger.leaveFullScreen(w) else { return .fullScreen(w.appName) }
        }
        if await tryNative(windows, arrangement, in: visible, screens: all) { return nil }
        let failure = await withoutEnhancedUI(pairs.map(\.app)) {
            await arranger.arrange(windows, arrangement, in: visible, gap: gap, displayName: displayName)
        }
        // Bring them forward, the last first, so none is left behind other windows.
        for w in windows.reversed() { bringForward((w.app, w.window)) }
        return failure
    }

    static func toNextScreen() async -> Result<Void, WindowFailure> {
        guard AXIsProcessTrusted() else { return .failure(.noPermission) }
        let all = screens()
        guard all.count > 1 else { return .failure(.oneScreen) }
        guard let (app, window) = frontWindow() else { return .failure(.noWindow) }
        let w = AXMovableWindow(app: app, window: window)
        if !(await arranger(all).leaveFullScreen(w)) { return .failure(.fullScreen(w.appName)) }
        guard let current = w.frame, let i = WindowTiling.screenIndex(for: current, in: all),
              let next = WindowTiling.nextScreenIndex(after: i, in: all) else { return .failure(.noWindow) }
        let target = WindowTiling.moved(current, from: all[i].visible, to: all[next].visible)
        return await set(window, app: app, to: target) ? .success(()) : .failure(.refused(w.appName))
    }

    /// Moves one window to `target` the way that works across displays (`WindowArranger`),
    /// remembering where it was for Return to Previous Size. True once it is there, or as
    /// close as its own minimum or maximum size allows.
    static func set(_ window: AXUIElement, app: AXUIElement, to target: CGRect) async -> Bool {
        await withoutEnhancedUI([app]) {
            await arranger(screens()).place(AXMovableWindow(app: app, window: window), to: target).frame != nil
        }
    }

    // MARK: macOS's own Arrange

    /// macOS's Arrange item for the windows, when it can do exactly this: true once every
    /// window sits in its place.
    private static func tryNative(_ windows: [AXMovableWindow], _ arrangement: WindowArrangement, in visible: CGRect,
                                  screens all: [TilingScreen]) async -> Bool {
        let frames = all.map(\.frame)
        guard let target = DisplayGeometry.displayIndex(for: visible, in: frames) else { return false }
        let ids = windows.compactMap(\.windowID)
        let displays = windows.map { $0.frame.flatMap { DisplayGeometry.displayIndex(for: $0, in: frames) } }
        func fits(_ order: [UInt32]) -> Bool {
            ArrangementLayout.nativeFits(arrangement, windowDisplays: displays, target: target, frontOrder: order, windows: ids)
        }
        guard ids.count == windows.count, fits(ids) else { return false }
        if !fits(frontWindowIDs(limit: windows.count)) {
            // In front, in order: the last first.
            for w in windows.reversed() { bringForward((w.app, w.window)) }
            guard await wait(0.5, until: { fits(frontWindowIDs(limit: windows.count)) }) else { return false }
        }
        guard let menu = tilingMenu(windows[0].app), let i = MoveResizeMenu.index(arrangement, in: menu.entries),
              AXUI.bool(menu.items[i], kAXEnabledAttribute) != false else { return false }
        for w in windows { WindowHistory.shared.remember(w) }
        guard AXUI.press(menu.items[i]) else { return false }
        // macOS animates there.
        return await wait(0.8) {
            let now = windows.compactMap(\.frame)
            return now.count == windows.count && ArrangementLayout.looksArranged(arrangement, frames: now, in: visible)
        }
    }

    // MARK: Menus

    /// The app's Window menu and Move & Resize items together (Fill and Center sit in the
    /// first, the rest in the second), and the Window menu alone with Move & Resize's index.
    /// The Window menu is found from the right of the menu bar, where it always is, by what
    /// its items do, so no menu is walked further than needed.
    static func tilingMenu(_ app: AXUIElement) -> (items: [AXUIElement], entries: [MoveResizeMenu.Entry],
                                                   window: [AXUIElement], moveResize: Int)? {
        guard let bar = AXUI.element(app, kAXMenuBarAttribute) else { return nil }
        for top in AXUI.children(bar).reversed() {
            guard let menu = AXUI.children(top).first else { continue }
            let items = AXUI.children(menu)
            for (i, item) in items.enumerated() {
                guard let sub = AXUI.children(item).first else { continue }
                let subItems = AXUI.children(sub)
                let subEntries = subItems.map(entry)
                guard MoveResizeMenu.isTilingMenu(subEntries) else { continue }
                return (items + subItems, items.map(entry) + subEntries, items, i)
            }
        }
        return nil
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
                                    submenu: submenu.map { !AXUI.children($0).isEmpty } ?? false, id: AXUI.identifier(e))
    }

    /// Presses the item `find` picks, while it is enabled.
    private static func press(_ app: AXUIElement, _ find: ([MoveResizeMenu.Entry]) -> Int?) -> Bool {
        guard let menu = tilingMenu(app), let i = find(menu.entries), AXUI.bool(menu.items[i], kAXEnabledAttribute) != false
        else { return false }
        return AXUI.press(menu.items[i])
    }

    // MARK: Private

    /// "Enhanced user interface", which some apps turn on for assistive tools, animates every
    /// change and makes sizes land wrong, so it is off while moving.
    static func withoutEnhancedUI<T>(_ apps: [AXUIElement], _ body: () async -> T) async -> T {
        let enhanced = apps.filter { AXUI.bool($0, "AXEnhancedUserInterface") == true }
        for app in enhanced { AXUI.set(app, "AXEnhancedUserInterface", false) }
        let result = await body()
        for app in enhanced { AXUI.set(app, "AXEnhancedUserInterface", true) }
        return result
    }

    /// Reads until `done` or `seconds` pass (macOS animates moves and activation), sleeping a
    /// task in between.
    static func wait(_ seconds: TimeInterval, until done: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if done() { return true }
            try? await Task.sleep(for: .milliseconds(50))
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
