import CoreGraphics
import Foundation

// The Displays screen (SPEC section 8): the Mac's displays drawn the way System Settings draws
// them, with the windows on each. Every frame is in macOS global display coordinates as Quartz,
// window lists and the Accessibility API use them: points, origin at the top-left corner of the
// main display, y growing downwards. A `CGRect` travels as `[[x, y], [width, height]]`.

/// One of the Mac's displays.
public struct MacDisplay: Codable, Equatable, Sendable, Hashable, Identifiable {
    /// The display's `CGDirectDisplayID`.
    public var id: UInt32
    /// "Built-in Retina Display", "Studio Display".
    public var name: String
    /// The whole display.
    public var frame: CGRect
    /// Without the menu bar and the Dock: where windows go.
    public var visibleFrame: CGRect
    /// Has the menu bar (its origin is 0, 0).
    public var isMain: Bool
    public var isBuiltIn: Bool
    /// Width in points of the camera housing at the top of the display, nil without one.
    public var notchWidth: Double?
    /// The display this one shows the same picture as, nil when it shows its own.
    public var mirrorOf: UInt32?
    /// 0...1, nil when Glasspad cannot change it (most other makers' displays).
    public var brightness: Double?
    /// The "Looks like" sizes macOS offers for it, smallest first. Empty when there is no choice.
    public var resolutions: [DisplayResolution]
    /// The one in use, when it is among `resolutions`.
    public var resolutionID: Int32?

    public init(id: UInt32, name: String, frame: CGRect, visibleFrame: CGRect, isMain: Bool, isBuiltIn: Bool = false,
                notchWidth: Double? = nil, mirrorOf: UInt32? = nil, brightness: Double? = nil, resolutions: [DisplayResolution] = [],
                resolutionID: Int32? = nil) {
        self.id = id
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isMain = isMain
        self.isBuiltIn = isBuiltIn
        self.notchWidth = notchWidth
        self.mirrorOf = mirrorOf
        self.brightness = brightness
        self.resolutions = resolutions
        self.resolutionID = resolutionID
    }

    /// The menu bar's height, read from what it leaves of the display (main display only).
    public var menuBarHeight: CGFloat {
        guard isMain else { return 0 }
        return max(0, visibleFrame.minY - frame.minY)
    }

    /// The resolution in use.
    public var resolution: DisplayResolution? { resolutions.first { $0.id == resolutionID } }
}

/// One "Looks like" choice: the size in points the desktop gets.
public struct DisplayResolution: Codable, Equatable, Sendable, Hashable, Identifiable {
    /// The display mode's id on the Mac.
    public var id: Int32
    public var width: Int
    public var height: Int
    /// The one macOS picks for this display.
    public var isDefault: Bool

    public init(id: Int32, width: Int, height: Int, isDefault: Bool = false) {
        self.id = id
        self.width = width
        self.height = height
        self.isDefault = isDefault
    }

    /// "1512 × 982".
    public var title: String { "\(width) × \(height)" }
}

/// One window on screen. Names come from the Accessibility API, so the Mac never needs
/// Screen Recording; `title` is nil when the app does not say.
public struct MacWindow: Codable, Equatable, Sendable, Hashable, Identifiable {
    /// The window server's `CGWindowID`.
    public var id: UInt32
    public var bundleID: String?
    public var appName: String
    public var title: String?
    public var frame: CGRect

    public init(id: UInt32, bundleID: String?, appName: String, title: String? = nil, frame: CGRect) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.frame = frame
    }

    /// The title when there is one, else the app's name.
    public var label: String {
        guard let title, !title.isEmpty else { return appName }
        return title
    }
}

/// A display change waiting for "Keep" (a new resolution or mirroring), like macOS's own
/// "Keep these display settings?". The Mac undoes it by itself when time runs out, so a
/// display left blank comes back even if the phone has gone.
public struct PendingDisplayChange: Codable, Equatable, Sendable, Hashable {
    /// What changed, in words: "Studio Display looks like 2560 × 1440".
    public var summary: String
    /// Whole seconds left when the Mac sent this state.
    public var secondsLeft: Int

    public init(summary: String, secondsLeft: Int) {
        self.summary = summary
        self.secondsLeft = secondsLeft
    }
}

/// Everything the Displays screen shows.
public struct DisplaysState: Codable, Equatable, Sendable {
    public var displays: [MacDisplay]
    /// Ordinary windows on screen, front to back.
    public var windows: [MacWindow]
    /// Night Shift on now; nil when the Mac cannot tell.
    public var nightShift: Bool?
    /// False without the Accessibility permission: windows show but cannot be moved.
    public var canArrangeWindows: Bool
    /// The gap macOS leaves around tiled windows ("Tiled windows have margins"), in points.
    public var tileMargin: Double
    public var pending: PendingDisplayChange?
    /// The arrangements this Mac takes in `WindowCommand.arrange` (`WindowArrangement` raw
    /// values, kept as text so a newer Mac's are skipped). nil from a Mac from before them,
    /// which splits two windows only.
    public var arrangements: [String]?

    public init(displays: [MacDisplay], windows: [MacWindow], nightShift: Bool? = nil, canArrangeWindows: Bool = true,
                tileMargin: Double = 0, pending: PendingDisplayChange? = nil, arrangements: [String]? = nil) {
        self.displays = displays
        self.windows = windows
        self.nightShift = nightShift
        self.canArrangeWindows = canArrangeWindows
        self.tileMargin = tileMargin
        self.pending = pending
        self.arrangements = arrangements
    }

    /// The arrangements the Mac takes that this build knows; empty for an older Mac.
    public var offeredArrangements: [WindowArrangement] {
        (arrangements ?? []).compactMap(WindowArrangement.init(rawValue:))
    }

    /// Displays with a picture of their own (mirrors are drawn as the display they copy).
    public var shownDisplays: [MacDisplay] { displays.filter { $0.mirrorOf == nil } }

    public func display(_ id: UInt32) -> MacDisplay? { displays.first { $0.id == id } }

    public func window(_ id: UInt32) -> MacWindow? { windows.first { $0.id == id } }

    /// The display showing most of the window.
    public func display(of window: MacWindow) -> MacDisplay? {
        let shown = shownDisplays
        return DisplayGeometry.displayIndex(for: window.frame, in: shown.map(\.frame)).map { shown[$0] }
    }
}

/// Where Left Half, Fill and the rest put a window, as in Window > Move & Resize.
public enum WindowTile: String, Codable, Sendable, CaseIterable, Hashable {
    case leftHalf, rightHalf, topHalf, bottomHalf, fill, center

    public var title: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .fill: "Fill"
        case .center: "Center"
        }
    }

    public var symbol: String {
        switch self {
        case .leftHalf: "rectangle.lefthalf.filled"
        case .rightHalf: "rectangle.righthalf.filled"
        case .topHalf: "rectangle.tophalf.filled"
        case .bottomHalf: "rectangle.bottomhalf.filled"
        case .fill: "rectangle.inset.filled"
        case .center: "rectangle.center.inset.filled"
        }
    }
}

/// Something to do to one window.
public enum WindowCommand: Codable, Equatable, Sendable, Hashable {
    /// Bring it to the front, with its app.
    case raise
    case tile(WindowTile)
    /// This window on the left half of its display, `with` on the right.
    case split(with: UInt32)
    /// To `display`. With `origin` nil it keeps where it sits and how much of the display it
    /// covers (a left half stays a left half); otherwise its top-left corner goes to `origin`,
    /// kept inside the display.
    case move(display: UInt32, origin: CGPoint?)
    case minimize
    case close
    case fullScreen
    /// These windows (this one first) arranged on `display`, each in its place in order.
    /// Only for a Mac that lists the arrangement in `DisplaysState.arrangements`.
    case arrange(WindowArrangement, windows: [UInt32], display: UInt32)
}

/// Where one display sits in the arrangement.
public struct DisplayOrigin: Codable, Equatable, Sendable, Hashable {
    public var display: UInt32
    public var origin: CGPoint

    public init(display: UInt32, origin: CGPoint) {
        self.display = display
        self.origin = origin
    }
}

/// A change to the displays themselves.
public enum DisplayCommand: Codable, Equatable, Sendable, Hashable {
    case brightness(display: UInt32, value: Double)
    /// One of the display's `resolutions`. Waits for `keepChanges`.
    case resolution(display: UInt32, id: Int32)
    /// Show the same picture as `of`, or its own again with nil. Waits for `keepChanges`.
    case mirror(display: UInt32, of: UInt32?)
    /// Give it the menu bar.
    case makeMain(display: UInt32)
    /// Every display's place; the main one stays at 0, 0.
    case arrange([DisplayOrigin])
    /// Keep or undo the change in `DisplaysState.pending`.
    case keepChanges
    case revertChanges
}
