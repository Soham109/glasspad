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

    public var message: String {
        switch self {
        case .noPermission: AXUI.permissionHint
        case .noWindow: "No window to move"
        case .noSecondWindow: "Open a second window to split the screen."
        case .oneScreen: "Only one display is connected"
        case .closed: "That window has closed."
        case .fullScreen(let app): "\(app) is in full screen. Exit full screen first."
        case .refused(let app): "\(app) won't let Glasspad move its window. Try again, or drag it into place."
        case .tooWide(let app): "\(app) can't be resized that small. Try a wider display."
        case .bothTooWide(let a, let b, let display):
            "\(a == b ? "These \(a) windows" : "\(a) and \(b)") can't both fit on \(display). Try a wider display."
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
    /// display. Minimized windows are skipped; a window in full screen is refused, since macOS
    /// keeps it in a space of its own.
    public static func choose(_ windows: [Candidate], displays: [CGRect]) -> Result<Choice, WindowFailure> {
        let usable = windows.indices.filter { !windows[$0].isMinimized }
        guard let left = usable.first else { return .failure(.noWindow) }
        guard usable.count > 1 else { return .failure(.noSecondWindow) }
        let right = usable[1]
        for i in [left, right] where windows[i].isFullScreen { return .failure(.fullScreen(windows[i].app)) }
        guard let display = DisplayGeometry.displayIndex(for: windows[left].frame, in: displays) else { return .failure(.noWindow) }
        return .success(Choice(left: left, right: right, display: display))
    }

    /// The two halves of `visible`, widened for a window that will not get narrower than its
    /// minimum (0 when not known): it keeps its own edge of the display and the other window gets
    /// the rest. nil when the two cannot share the display.
    public static func halves(in visible: CGRect, gap: CGFloat = 0, leftMinimum: CGFloat = 0,
                              rightMinimum: CGFloat = 0) -> (left: CGRect, right: CGRect)? {
        let even = DisplayGeometry.split(in: visible, gap: gap)
        let wideLeft = leftMinimum.rounded(.up) > even.left.width, wideRight = rightMinimum.rounded(.up) > even.right.width
        if !wideLeft && !wideRight { return even }
        if wideLeft && wideRight { return nil }
        // Room for both, between the outer edges of the halves.
        let room = even.right.maxX - even.left.minX - gap
        if wideLeft {
            let lw = leftMinimum.rounded(.up), rw = room - lw
            guard rw > 0, rw >= rightMinimum else { return nil }
            return (CGRect(x: even.left.minX, y: even.left.minY, width: lw, height: even.left.height),
                    CGRect(x: even.right.maxX - rw, y: even.right.minY, width: rw, height: even.right.height))
        }
        let rw = rightMinimum.rounded(.up), lw = room - rw
        guard lw > 0, lw >= leftMinimum else { return nil }
        return (CGRect(x: even.left.minX, y: even.left.minY, width: lw, height: even.left.height),
                CGRect(x: even.right.maxX - rw, y: even.right.minY, width: rw, height: even.right.height))
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

    /// How long a window gets to land after it was moved, and how often it is read meanwhile.
    public static let settleTime: TimeInterval = 0.3
    public static let readInterval: TimeInterval = 0.05

    public init(displays: [CGRect], pause: @escaping (TimeInterval) -> Void) {
        self.displays = displays
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

    /// Side by side on `visible`: `right` first (it may come from another display), then
    /// `left`. A window that will not get as narrow as its half keeps its width and the other
    /// gets the rest. nil when it worked.
    public func split(left: MovableWindow, right: MovableWindow, in visible: CGRect, gap: CGFloat,
                      displayName: String) -> WindowFailure? {
        for w in [left, right] where w.isFullScreen { return .fullScreen(w.appName) }
        var leftMinimum: CGFloat = 0, rightMinimum: CGFloat = 0
        // Each pass can learn one more minimum width; three passes settle any pair.
        for _ in 0..<3 {
            guard let halves = SplitScreen.halves(in: visible, gap: gap, leftMinimum: leftMinimum, rightMinimum: rightMinimum) else {
                break
            }
            let r = move(right, to: halves.right), l = move(left, to: halves.left)
            for (landing, w) in [(r, right), (l, left)] {
                if landing == .gone { return .closed }
                if landing == .refused { return .refused(w.appName) }
            }
            var learned = false
            if let f = l.frame, f.width > halves.left.width + 2 { leftMinimum = f.width; learned = true }
            if let f = r.frame, f.width > halves.right.width + 2 { rightMinimum = f.width; learned = true }
            if !learned { return nil }
        }
        return SplitScreen.tooWide(left: left.appName, right: right.appName, leftMinimum: leftMinimum,
                                   rightMinimum: rightMinimum, display: displayName)
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
