import AppKit
import CoreGraphics

/// Which display the laser dot belongs on: the one the slides are playing on. Pure, so the rule
/// is tested; `LaserScreen.read` feeds it the front app's windows and the displays.
///
/// All rectangles are in Core Graphics global coordinates (origin at the top left of the main
/// display, y down).
public enum LaserScreenPicker {
    /// A window this close to a display's edges still covers it (some apps' full-screen
    /// windows sit a point inside).
    public static let tolerance: CGFloat = 2

    public static func pick(frontWindows: [CGRect], screens: [(frame: CGRect, builtIn: Bool)],
                            main: CGRect) -> CGRect {
        // 1. Displays a window of the front app covers entirely: a slideshow (or presenter view).
        let covered = screens.filter { screen in frontWindows.contains { covers($0, screen.frame) } }
        // 2. Keynote and PowerPoint put presenter view full screen on the other display: the
        //    slides go to the projector, which is the external one.
        if let external = covered.first(where: { !$0.builtIn }) { return external.frame }
        if let only = covered.first { return only.frame }
        // 3. The display holding the front app's largest window.
        if let largest = frontWindows.max(by: { area($0) < area($1) }),
           let holder = screens.max(by: { area($0.frame.intersection(largest)) < area($1.frame.intersection(largest)) }),
           area(holder.frame.intersection(largest)) > 0 {
            return holder.frame
        }
        // 4. The main display, as before.
        return main
    }

    static func covers(_ window: CGRect, _ screen: CGRect) -> Bool {
        window.minX <= screen.minX + tolerance && window.minY <= screen.minY + tolerance
            && window.maxX >= screen.maxX - tolerance && window.maxY >= screen.maxY - tolerance
    }

    private static func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }

    /// A Core Graphics rectangle (top-left origin) as an AppKit one (bottom-left origin), given
    /// the main display's height.
    public static func appKitFrame(_ cg: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: cg.minX, y: mainHeight - cg.maxY, width: cg.width, height: cg.height)
    }
}

/// Reads what `LaserScreenPicker` needs from the window server. Bounds only (no Accessibility),
/// and off the main thread: the window list can take a moment with many windows open.
enum LaserScreen {
    /// The AppKit frame of the display to draw on, for the app with `pid` in front.
    nonisolated static func read(pid: pid_t) -> CGRect {
        var windows: [CGRect] = []
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width >= 50, rect.height >= 50 else { continue }
            windows.append(rect)
        }
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let screens = ids.prefix(Int(count)).map { (frame: CGDisplayBounds($0), builtIn: CGDisplayIsBuiltin($0) != 0) }
        let main = CGDisplayBounds(CGMainDisplayID())
        let picked = LaserScreenPicker.pick(frontWindows: windows, screens: screens, main: main)
        return LaserScreenPicker.appKitFrame(picked, mainHeight: main.height)
    }
}
