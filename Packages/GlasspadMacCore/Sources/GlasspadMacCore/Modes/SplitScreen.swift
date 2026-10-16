import CoreGraphics
import Foundation
import GlasspadKit

/// Why a window button or Split Screen did not work, in plain words that say what to do.
public enum WindowFailure: Error, Equatable, Sendable {
    case noPermission
    case noWindow
    case noSecondWindow
    case oneScreen
    case closed
    /// The app's name.
    case fullScreen(String)
    /// The app would not move or resize its window.
    case refused(String)
    /// The window will not get narrow enough for half the display.
    case tooWide(String)
    /// Neither window gets narrow enough to share the display.
    case bothTooWide(String, String, display: String)
    /// The window will not get short enough for half the display.
    case tooTall(String)
    /// Neither window gets short enough to share the display top and bottom.
    case bothTooTall(String, String, display: String)
    /// These apps' windows will not get small enough for their quarters.
    case tooBigForQuarters([String], display: String)
    /// Return to Previous Size with nothing to return to.
    case noPreviousSize
    /// The window's earlier place is on a display that is not connected any more.
    case previousDisplayGone
    /// The app has no Full-Screen Tile for this window.
    case noSplitView(String)
    /// Split View did not take the second window; the first is back on the desktop.
    case splitViewUnfinished

    public var message: String {
        switch self {
        case .noPermission: AXUI.permissionHint
        case .noWindow: "No window to move"
        case .noSecondWindow: "Open a second window to split the screen."
        case .oneScreen: "Only one display is connected"
        case .closed: "That window has closed."
        case .fullScreen(let app): "\(app) would not leave full screen. Try again in a moment."
        case .refused(let app): "\(app) won't let Glasspad move its window. Try again, or drag it into place."
        case .tooWide(let app): "\(app) can't be resized that small. Try a wider display."
        case .bothTooWide(let a, let b, let display):
            "\(a == b ? "These \(a) windows" : "\(a) and \(b)") can't both fit on \(display). Try a wider display."
        case .tooTall(let app): "\(app) can't be made short enough for Top & Bottom. Try Left & Right."
        case .bothTooTall(let a, let b, let display):
            "\(a == b ? "These \(a) windows" : "\(a) and \(b)") can't both fit on \(display), one above the other. Try Left & Right."
        case .tooBigForQuarters(let apps, let display):
            switch apps.count {
            case 0, 1: "\(apps.first ?? "This window") can't be made small enough for a quarter of \(display). Try Left & Right."
            case 2: "\(apps[0]) and \(apps[1]) can't both fit in quarters on \(display). Try Left & Right."
            default: "\(apps.dropLast().joined(separator: ", ")) and \(apps[apps.count - 1]) can't all fit in quarters on \(display). Try Left & Right."
            }
        case .noPreviousSize: "This window has no previous size to return to."
        case .previousDisplayGone: "This window's previous place is on a display that isn't connected."
        case .noSplitView(let app): "\(app) can't tile this window in full screen. Try Left & Right."
        case .splitViewUnfinished: "Couldn't finish Split View. Pick the second window on your Mac."
        }
    }
}

/// Split Screen's decisions, apart from the Mac so tests drive them: which two windows, which
/// display, and where each one goes.
public enum SplitScreen {
    /// A window as Split Screen sees it, front to back.
    public struct Candidate: Equatable, Sendable {
        public var app: String
        public var frame: CGRect
        public var isMinimized: Bool
        public var isFullScreen: Bool

        public init(app: String, frame: CGRect, isMinimized: Bool = false, isFullScreen: Bool = false) {
            self.app = app
            self.frame = frame
            self.isMinimized = isMinimized
            self.isFullScreen = isFullScreen
        }
    }

    /// The two windows (indexes into the candidates) and the display (an index into the displays).
    public struct Choice: Equatable, Sendable {
        public var left: Int
        public var right: Int
        public var display: Int
    }

    /// The front window on the left and the one behind it on the right, on the front window's
    /// display. Minimized windows are skipped; a window in full screen is taken out of it when
    /// the split runs.
    public static func choose(_ windows: [Candidate], displays: [CGRect]) -> Result<Choice, WindowFailure> {
        let usable = windows.indices.filter { !windows[$0].isMinimized }
        guard let left = usable.first else { return .failure(.noWindow) }
        guard usable.count > 1 else { return .failure(.noSecondWindow) }
        let right = usable[1]
        guard let display = DisplayGeometry.displayIndex(for: windows[left].frame, in: displays) else { return .failure(.noWindow) }
        return .success(Choice(left: left, right: right, display: display))
    }

    /// The two halves of `visible`, widened for a window that will not get narrower than its
    /// minimum (0 when not known): it keeps its own edge of the display and the other window gets
    /// the rest. nil when the two cannot share the display.
    public static func halves(in visible: CGRect, gap: CGFloat = 0, leftMinimum: CGFloat = 0,
                              rightMinimum: CGFloat = 0) -> (left: CGRect, right: CGRect)? {
        let minimums = [CGSize(width: leftMinimum, height: 0), CGSize(width: rightMinimum, height: 0)]
        guard let f = ArrangementLayout.frames(.leftAndRight, in: visible, gap: gap, minimums: minimums) else { return nil }
        return (f[0], f[1])
    }

    /// Why two windows with these minimum widths (0 when they fit their half) cannot share.
    static func tooWide(left: String, right: String, leftMinimum: CGFloat, rightMinimum: CGFloat, display: String) -> WindowFailure {
        if leftMinimum > 0 && rightMinimum > 0 { return .bothTooWide(left, right, display: display) }
        return .tooWide(leftMinimum > 0 ? left : right)
    }

    /// True when the two windows sit side by side on `visible`, as macOS's own Left & Right
    /// leaves them (its margins may differ from ours, so only which side each is on counts).
    public static func looksSplit(left: CGRect, right: CGRect, in visible: CGRect) -> Bool {
        let tolerance: CGFloat = 24
        return visible.insetBy(dx: -tolerance, dy: -tolerance).contains(left) && visible.insetBy(dx: -tolerance, dy: -tolerance).contains(right)
            && left.maxX <= visible.midX + tolerance && right.minX >= visible.midX - tolerance
            && left.width >= visible.width / 2 - 3 * tolerance && right.width >= visible.width / 2 - 3 * tolerance
    }
}

// MARK: - Moving windows

/// A window that can be moved. The live one goes through the Accessibility API; tests use fakes
/// that behave the way apps do (minimum sizes, sizes limited by the display a window is on, a
/// move that lands a moment later).
@MainActor
public protocol MovableWindow: AnyObject {
    var appName: String { get }
    /// nil once the window has gone.
    var frame: CGRect? { get }
    var isFullScreen: Bool { get }
    /// The window server's id, for Return to Previous Size; nil when not known.
    var windowID: UInt32? { get }
    /// Asks the window to leave full screen. False when it refuses.
    @discardableResult func exitFullScreen() -> Bool
    @discardableResult func setPosition(_ origin: CGPoint) -> Bool
    @discardableResult func setSize(_ size: CGSize) -> Bool
}

/// Moves windows in the order that works across displays: onto the target display first (an
/// app keeps a window no larger than the display it is on, so sizing it before it arrives
/// leaves it short), then the size, then the place, then reads it back until it settles.
@MainActor
public struct WindowArranger {
    /// Every display's whole frame.
    public var displays: [CGRect]
    /// Waits this long (the live one sleeps; tests move a fake clock).
    public var pause: (TimeInterval) -> Void
    /// Where each window was before Glasspad last moved it; nil keeps no record.
    public var history: WindowHistory?

    /// How long a window gets to land after it was moved, and how often it is read meanwhile.
    public static let settleTime: TimeInterval = 0.3
    public static let readInterval: TimeInterval = 0.05

    public init(displays: [CGRect], history: WindowHistory? = nil, pause: @escaping (TimeInterval) -> Void) {
        self.displays = displays
        self.history = history
        self.pause = pause
    }

    /// Where a move left the window.
    public enum Landing: Equatable, Sendable {
        /// Exactly at the target.
        case placed(CGRect)
        /// At the target's corner, but its own minimum or maximum size won: as close as it gets.
        case closest(CGRect)
        case refused
        case gone

        public var frame: CGRect? {
            switch self {
            case .placed(let f), .closest(let f): f
            case .refused, .gone: nil
            }
        }
    }

    public func move(_ w: MovableWindow, to target: CGRect) -> Landing {
        guard let start = w.frame else { return .gone }
        let display = DisplayGeometry.displayIndex(for: target, in: displays)
        if display != nil, DisplayGeometry.displayIndex(for: start, in: displays) != display {
            guard w.setPosition(target.origin) else { return .refused }
            _ = settle(w) { DisplayGeometry.displayIndex(for: $0, in: displays) == display }
        }
        let sized = w.setSize(target.size)
        let moved = w.setPosition(target.origin)
        guard sized || moved else { return .refused }
        var now = settle(w) { WindowTiling.isClose($0, target) }
        if let f = now, !WindowTiling.isClose(f, target) {
            // A new size near a display's edge can make macOS nudge the window: once more.
            w.setSize(target.size)
            w.setPosition(target.origin)
            now = settle(w) { WindowTiling.isClose($0, target) }
        }
        guard let f = now else { return .gone }
        if WindowTiling.isClose(f, target) { return .placed(f) }
        if abs(f.minX - target.minX) <= 2 { return .closest(f) }
        return .refused
    }

    /// Side by side on `visible`, `left` on the left. nil when it worked.
    public func split(left: MovableWindow, right: MovableWindow, in visible: CGRect, gap: CGFloat,
                      displayName: String) -> WindowFailure? {
        arrange([left, right], .leftAndRight, in: visible, gap: gap, displayName: displayName)
    }

    /// The windows in their places on `visible`, in order, the last first (each may come from
    /// another display). A window that will not get as small as its place keeps its size and
    /// its neighbours get the rest. Split View is not done here (`FullScreenSplit`). nil when
    /// it worked.
    public func arrange(_ windows: [MovableWindow], _ arrangement: WindowArrangement, in visible: CGRect, gap: CGFloat,
                        displayName: String) -> WindowFailure? {
        guard windows.count >= 2, windows.count <= arrangement.slots.count else { return .noSecondWindow }
        // Out of full screen first, as macOS does when a full-screen window is tiled.
        for w in windows where !leaveFullScreen(w) { return .fullScreen(w.appName) }
        for w in windows { history?.remember(w) }
        var minimums = [CGSize](repeating: .zero, count: windows.count)
        // Each pass learns every window that stayed larger than its place; four settle any grid.
        for _ in 0..<4 {
            guard let frames = ArrangementLayout.frames(arrangement, in: visible, gap: gap, minimums: minimums) else { break }
            var landings = [Landing](repeating: .refused, count: windows.count)
            for i in windows.indices.reversed() { landings[i] = move(windows[i], to: frames[i]) }
            for i in windows.indices.reversed() {
                if landings[i] == .gone { return .closed }
                if landings[i] == .refused { return .refused(windows[i].appName) }
            }
            var learned = false
            for i in windows.indices {
                guard let f = landings[i].frame else { continue }
                if f.width > frames[i].width + 2 { minimums[i].width = f.width; learned = true }
                if f.height > frames[i].height + 2 { minimums[i].height = f.height; learned = true }
            }
            if !learned { return nil }
        }
        return ArrangementLayout.failure(arrangement, apps: windows.map(\.appName), minimums: minimums, display: displayName)
    }

    /// One window to `target`, remembered for Return to Previous Size first.
    public func place(_ w: MovableWindow, to target: CGRect) -> Landing {
        history?.remember(w)
        return move(w, to: target)
    }

    /// Back where the window was before Glasspad last moved it. nil when it worked.
    public func returnToPreviousSize(_ w: MovableWindow) -> WindowFailure? {
        guard let id = w.windowID, let previous = history?.previous(id) else { return .noPreviousSize }
        guard displays.contains(where: { $0.intersects(previous.insetBy(dx: 40, dy: 40)) }) else {
            history?.forget(id)
            return .previousDisplayGone
        }
        guard leaveFullScreen(w) else { return .fullScreen(w.appName) }
        switch move(w, to: previous) {
        case .gone: return .closed
        case .refused: return .refused(w.appName)
        case .placed, .closest:
            history?.forget(id)
            return nil
        }
    }

    /// How long macOS gets to play its leave-full-screen animation, and the pause after it
    /// before the window takes new frames.
    public static let fullScreenExitTime: TimeInterval = 2.0
    public static let afterFullScreen: TimeInterval = 0.35

    /// Takes the window out of full screen, as macOS does when you tile a full-screen window,
    /// and waits until it is back on the desktop. True when it is not in full screen.
    public func leaveFullScreen(_ w: MovableWindow) -> Bool {
        guard w.isFullScreen else { return true }
        guard w.exitFullScreen() else { return false }
        var waited: TimeInterval = 0
        while w.isFullScreen && waited < Self.fullScreenExitTime {
            pause(Self.readInterval)
            waited += Self.readInterval
        }
        guard !w.isFullScreen else { return false }
        pause(Self.afterFullScreen)
        return true
    }

    /// Reads the frame until `done` or the settle time is up (some apps land a move later).
    private func settle(_ w: MovableWindow, until done: (CGRect) -> Bool) -> CGRect? {
        var waited: TimeInterval = 0
        while true {
            guard let f = w.frame else { return nil }
            if done(f) || waited >= Self.settleTime - 0.0001 { return f }
            pause(Self.readInterval)
            waited += Self.readInterval
        }
    }
}
