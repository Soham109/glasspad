import AppKit
import ApplicationServices
import GlasspadKit

/// Split View: two windows side by side in full screen, as Window > Full-Screen Tile does.
/// The first window goes to the left of the screen with macOS's own item; macOS then waits for
/// a window to take the right, and Glasspad picks the second one. If that does not take, the
/// first window comes back out of full screen so nothing is left half done.
///
/// Kept apart from the rest of tiling: the second step has not been tried on every macOS yet.
@MainActor
public protocol SplitViewSteps {
    /// Presses Window > Full-Screen Tile > Left of Screen for this window. False when the app
    /// has no such item or it is off.
    func tileLeft(_ w: MovableWindow) async -> Bool
    /// Makes this window the one on the right of the Split View that is waiting for it.
    func pickPartner(_ w: MovableWindow) async -> Bool
}

@MainActor
public struct FullScreenSplit {
    public var steps: SplitViewSteps
    public var arranger: WindowArranger

    /// How long macOS gets to go into full screen, for each window.
    public static let enterTime: TimeInterval = 3
    /// The pause after the first window is in full screen, while macOS shows the other windows.
    public static let pickerTime: TimeInterval = 0.6

    public init(steps: SplitViewSteps, arranger: WindowArranger) {
        self.steps = steps
        self.arranger = arranger
    }

    /// `left` and `right` side by side in full screen on the display `left` is on. nil when
    /// it worked.
    public func fullScreenSplit(left: MovableWindow, right: MovableWindow) async -> WindowFailure? {
        for w in [left, right] {
            guard await arranger.leaveFullScreen(w) else { return .fullScreen(w.appName) }
        }
        guard await steps.tileLeft(left), await waitUntil({ left.isFullScreen }) else { return .noSplitView(left.appName) }
        await arranger.pause(Self.pickerTime)
        if await steps.pickPartner(right), await waitUntil({ right.isFullScreen && sideBySide(left, right) }) { return nil }
        // Back to how they were: neither left alone in full screen.
        for w in [right, left] where w.isFullScreen { _ = await arranger.leaveFullScreen(w) }
        return .splitViewUnfinished
    }

    /// True when both windows fill their halves of one display, left and right.
    func sideBySide(_ left: MovableWindow, _ right: MovableWindow) -> Bool {
        guard let l = left.frame, let r = right.frame else { return false }
        let displays = arranger.displays
        guard let d = DisplayGeometry.displayIndex(for: l, in: displays), DisplayGeometry.displayIndex(for: r, in: displays) == d else {
            return false
        }
        return l.midX < displays[d].midX && r.midX > displays[d].midX
    }

    private func waitUntil(_ done: () -> Bool) async -> Bool {
        var waited: TimeInterval = 0
        while !done() {
            guard waited < Self.enterTime else { return false }
            await arranger.pause(WindowArranger.readInterval)
            waited += WindowArranger.readInterval
        }
        return true
    }
}

/// The live steps, through each app's Window menu and the window picker macOS shows.
/// UNVERIFIED on a real Mac: how the second window joins (see `pickPartner`).
@MainActor
struct LiveSplitViewSteps: SplitViewSteps {
    func tileLeft(_ w: MovableWindow) async -> Bool {
        guard let w = w as? AXMovableWindow else { return false }
        WindowMover.bringForward((w.app, w.window))
        // The app's menu acts on its front window once it is active.
        _ = await WindowMover.wait(0.5) { AXUI.bool(w.app, kAXFrontmostAttribute) == true }
        guard let items = Self.tileItems(w.app) else { return false }
        return AXUI.press(items.left)
    }

    /// First the window as macOS offers it on the free half (an element in the Dock's picker
    /// named like the window); else the window's own Full-Screen Tile > Right of Screen.
    func pickPartner(_ w: MovableWindow) async -> Bool {
        guard let w = w as? AXMovableWindow else { return false }
        if let title = w.title, !title.isEmpty, let dock = AXUI.app("com.apple.dock") {
            // Never a Dock icon: an app named like the window would only open.
            let tile = AXUI.first(in: dock, maxDepth: 8, budget: 1500) { e in
                AXUI.string(e, kAXRoleAttribute) != "AXDockItem"
                    && (AXUI.string(e, kAXTitleAttribute) == title || AXUI.string(e, kAXDescriptionAttribute) == title)
            }
            if let tile, AXUI.press(tile) { return true }
        }
        WindowMover.bringForward((w.app, w.window))
        _ = await WindowMover.wait(0.5) { AXUI.bool(w.app, kAXFrontmostAttribute) == true }
        guard let items = Self.tileItems(w.app) else { return false }
        return AXUI.press(items.right)
    }

    /// Window > Full-Screen Tile > Left of Screen and Right of Screen, while enabled.
    static func tileItems(_ app: AXUIElement) -> (left: AXUIElement, right: AXUIElement)? {
        guard let menu = WindowMover.tilingMenu(app), menu.window.indices.contains(menu.moveResize + 1) else { return nil }
        let tile = menu.window[menu.moveResize + 1]
        let items = AXUI.children(tile).first.map(AXUI.children) ?? []
        guard let found = MoveResizeMenu.fullScreenTileIndices(windowMenu: menu.window.map(WindowMover.entry),
                                                               moveResize: menu.moveResize, tile: items.map(WindowMover.entry)),
              AXUI.bool(items[found.left], kAXEnabledAttribute) != false else { return nil }
        return (items[found.left], items[found.right])
    }
}

extension WindowMover {
    /// Split View for two windows (`FullScreenSplit`). nil when it worked.
    static func fullScreenSplit(left: Pair, right: Pair) async -> WindowFailure? {
        let split = FullScreenSplit(steps: LiveSplitViewSteps(), arranger: arranger(screens()))
        return await split.fullScreenSplit(left: AXMovableWindow(left), right: AXMovableWindow(right))
    }
}
