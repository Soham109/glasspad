import AppKit
import ApplicationServices
import GlasspadKit

/// Where a tiling button puts the front window.
public enum WindowPlacement: String, Sendable, CaseIterable {
    case left, right, top, bottom, fill, center, topLeft, topRight, bottomLeft, bottomRight

    public init?(_ action: DeckSystemAction) {
        switch action {
        case .windowLeft: self = .left
        case .windowRight: self = .right
        case .windowTop: self = .top
        case .windowBottom: self = .bottom
        case .windowFill: self = .fill
        case .windowCenter: self = .center
        case .windowTopLeft: self = .topLeft
        case .windowTopRight: self = .topRight
        case .windowBottomLeft: self = .bottomLeft
        case .windowBottomRight: self = .bottomRight
        default: return nil
        }
    }

    /// The half or quarter it fills; nil for Fill and Center.
    public var slot: WindowSlot? {
        switch self {
        case .left: .left
        case .right: .right
        case .top: .top
        case .bottom: .bottom
        case .topLeft: .topLeft
        case .topRight: .topRight
        case .bottomLeft: .bottomLeft
        case .bottomRight: .bottomRight
        case .fill, .center: nil
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
        if let slot = placement.slot { return DisplayGeometry.frame(of: slot, in: visible, gap: gap) }
        return DisplayGeometry.tile(placement == .fill ? .fill : .center, window: window, in: visible, gap: gap)
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

/// Finds an app's Window > Move & Resize items by the action each one sends (its Accessibility
/// identifier, such as `_zoomLeft:`), which is the same in every language. An app whose items
/// do not say falls back to the shortcuts (fn control plus an arrow, F, C or R since macOS 15;
/// shift for Arrange, option and shift for "& Quarters"), and the items without one (the single
/// quarters, Arrange > Quarters) to where they sit next to those, only when the menu is laid
/// out exactly as macOS 15 and later lay it out.
public enum MoveResizeMenu {
    /// What the Accessibility API says about a menu item's shortcut.
    public struct Shortcut: Equatable, Sendable {
        public var char: String?
        public var virtualKey: Int?
        public var glyph: Int?
        /// `AXMenuItemCmdModifiers`: shift 1, option 2, control 4, no command 8 (fn adds 16).
        public var modifiers: Int

        public init(char: String? = nil, virtualKey: Int? = nil, glyph: Int? = nil, modifiers: Int) {
            self.char = char
            self.virtualKey = virtualKey
            self.glyph = glyph
            self.modifiers = modifiers
        }

        /// Control and no command key, as every Move & Resize shortcut has.
        var isControl: Bool { modifiers & 4 != 0 && modifiers & 8 != 0 }
        var shift: Bool { modifiers & 1 != 0 }
        var option: Bool { modifiers & 2 != 0 }

        /// Which arrow key, if any: left, right, up, down.
        var arrow: WindowSlot? {
            for (slot, key, glyph, char) in [(WindowSlot.left, 123, 0x64, 0xF702), (.right, 124, 0x65, 0xF703),
                                              (.top, 126, 0x68, 0xF700), (.bottom, 125, 0x6A, 0xF701)] {
                if virtualKey == key || self.glyph == glyph { return slot }
                if self.char?.unicodeScalars.first.map({ Int($0.value) == char }) ?? false { return slot }
            }
            return nil
        }
    }

    /// One item of a menu, as read: its title (empty for a separator), its shortcut (nil
    /// without one), and whether it opens a submenu.
    public struct Entry: Equatable, Sendable {
        public var title: String
        public var shortcut: Shortcut?
        public var hasSubmenu: Bool
        /// The action it sends, as the Accessibility API names it (`_zoomLeft:`).
        public var identifier: String?

        public init(_ title: String, _ shortcut: Shortcut? = nil, submenu: Bool = false, id: String? = nil) {
            self.title = title
            self.shortcut = shortcut
            self.hasSubmenu = submenu
            self.identifier = id
        }

        var isSeparator: Bool { title.isEmpty && shortcut == nil && !hasSubmenu }
        /// A plain item: a title, no shortcut, no submenu.
        var isPlain: Bool { !title.isEmpty && shortcut == nil && !hasSubmenu }
    }

    /// The action of each placement's item, as AppKit names it (macOS 15 and later).
    public static func identifier(_ placement: WindowPlacement) -> String {
        switch placement {
        case .left: "_zoomLeft:"
        case .right: "_zoomRight:"
        case .top: "_zoomTop:"
        case .bottom: "_zoomBottom:"
        case .fill: "_zoomFill:"
        case .center: "_zoomCenter:"
        case .topLeft: "_zoomTopLeft:"
        case .topRight: "_zoomTopRight:"
        case .bottomLeft: "_zoomBottomLeft:"
        case .bottomRight: "_zoomBottomRight:"
        }
    }

    /// The action of each Arrange item; nil for Split View, which is not one.
    public static func identifier(_ arrangement: WindowArrangement) -> String? {
        switch arrangement {
        case .leftAndRight: "_zoomLeftAndRight:"
        case .rightAndLeft: "_zoomRightAndLeft:"
        case .topAndBottom: "_zoomTopAndBottom:"
        case .bottomAndTop: "_zoomBottomAndTop:"
        case .leftAndQuarters: "_zoomLeftThreeUp:"
        case .rightAndQuarters: "_zoomRightThreeUp:"
        case .topAndQuarters: "_zoomTopThreeUp:"
        case .bottomAndQuarters: "_zoomBottomThreeUp:"
        case .quarters: "_zoomQuarters:"
        case .fullScreen: nil
        }
    }

    /// Return to Previous Size's action.
    public static let returnIdentifier = "_zoomUntile:"

    /// True when the items say which Move & Resize action they send (Zoom's own `_zoom:` aside):
    /// then an item that does not is not one, whatever its shortcut.
    static func namesActions(_ items: [Entry]) -> Bool {
        items.contains { ($0.identifier?.hasPrefix("_zoom") ?? false) && $0.identifier != "_zoom:" }
    }

    /// True for a menu holding Move & Resize items (the Window menu, or Move & Resize itself).
    public static func isTilingMenu(_ items: [Entry]) -> Bool {
        namesActions(items) || items.contains { $0.shortcut.map { matches($0, .left) } ?? false }
    }

    /// Where a placement's item is: by its action, else by its shortcut or, for a quarter, its place.
    public static func index(_ placement: WindowPlacement, in items: [Entry]) -> Int? {
        if let i = items.firstIndex(where: { $0.identifier == identifier(placement) }) { return i }
        guard !namesActions(items) else { return nil }
        switch placement {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return quarterIndex(placement, in: items)
        default: return items.firstIndex { $0.shortcut.map { matches($0, placement) } ?? false }
        }
    }

    /// Where an Arrange item is: by its action, else by its shortcut (Quarters by its place).
    public static func index(_ arrangement: WindowArrangement, in items: [Entry]) -> Int? {
        guard let id = identifier(arrangement) else { return nil }
        if let i = items.firstIndex(where: { $0.identifier == id }) { return i }
        guard !namesActions(items) else { return nil }
        if arrangement == .quarters { return quartersArrangeIndex(in: items) }
        return items.firstIndex { $0.shortcut.flatMap(self.arrangement) == arrangement }
    }

    /// Where Return to Previous Size is: by its action, else by fn control R.
    public static func returnIndex(in items: [Entry]) -> Int? {
        if let i = items.firstIndex(where: { $0.identifier == returnIdentifier }) { return i }
        guard !namesActions(items) else { return nil }
        return items.firstIndex { $0.shortcut.map(isReturnToPreviousSize) ?? false }
    }

    /// True for Arrange > Left & Right: shift, control and the left arrow, no command or option.
    /// macOS puts the front window on the left and the one behind it on the right.
    public static func isLeftAndRight(_ s: Shortcut) -> Bool { arrangement(s) == .leftAndRight }

    /// The Arrange item a shortcut belongs to: shift and control with an arrow for the pairs,
    /// option as well for "& Quarters". nil for anything else.
    public static func arrangement(_ s: Shortcut) -> WindowArrangement? {
        guard s.isControl, s.shift, let arrow = s.arrow else { return nil }
        switch arrow {
        case .left: return s.option ? .leftAndQuarters : .leftAndRight
        case .right: return s.option ? .rightAndQuarters : .rightAndLeft
        case .top: return s.option ? .topAndQuarters : .topAndBottom
        default: return s.option ? .bottomAndQuarters : .bottomAndTop
        }
    }

    /// True when the shortcut is the one macOS gives this placement (the quarters have none).
    public static func matches(_ s: Shortcut, _ placement: WindowPlacement) -> Bool {
        guard s.isControl, !s.shift, !s.option else { return false }
        switch placement {
        case .left, .right, .top, .bottom: return s.arrow != nil && s.arrow == placement.slot
        case .fill: return s.char?.uppercased() == "F"
        case .center: return s.char?.uppercased() == "C"
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return false
        }
    }

    /// True for Return to Previous Size: fn control R.
    public static func isReturnToPreviousSize(_ s: Shortcut) -> Bool {
        s.isControl && !s.shift && !s.option && s.char?.uppercased() == "R"
    }

    /// Where Arrange > Quarters is in the Move & Resize menu: the plain item straight after the
    /// last Arrange item with a shortcut, ending its section.
    public static func quartersArrangeIndex(in items: [Entry]) -> Int? {
        guard let last = items.lastIndex(where: { $0.shortcut.flatMap(arrangement) != nil }) else { return nil }
        let i = last + 1
        guard items.indices.contains(i), items[i].isPlain, !items.indices.contains(i + 1) || items[i + 1].isSeparator else { return nil }
        return i
    }

    /// Where a single quarter is: the section after the halves (Bottom ends them) is a heading
    /// and exactly four plain items, top left, top right, bottom left, bottom right.
    public static func quarterIndex(_ placement: WindowPlacement, in items: [Entry]) -> Int? {
        let order: [WindowPlacement] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        guard let offset = order.firstIndex(of: placement),
              let bottom = items.firstIndex(where: { $0.shortcut.map { matches($0, .bottom) } ?? false }) else { return nil }
        let first = bottom + 3
        guard items.indices.contains(first + 3), items[bottom + 1].isSeparator, items[bottom + 2].isPlain,
              items[first...(first + 3)].allSatisfy(\.isPlain),
              !items.indices.contains(first + 4) || items[first + 4].isSeparator else { return nil }
        return first + offset
    }

    /// Full-Screen Tile's Left of Screen and Right of Screen: the submenu straight after Move &
    /// Resize in the Window menu, while it holds just those two plain items (with a window
    /// already tiled it offers other things instead).
    public static func fullScreenTileIndices(windowMenu: [Entry], moveResize: Int, tile: [Entry]) -> (left: Int, right: Int)? {
        guard windowMenu.indices.contains(moveResize + 1), windowMenu[moveResize + 1].hasSubmenu, tile.count == 2,
              tile.allSatisfy({ !$0.title.isEmpty && $0.shortcut == nil && !$0.hasSubmenu }) else { return nil }
        return (0, 1)
    }
}

/// Stage Manager keeps a strip of recent apps at the side of the display; tiled windows leave
/// room for it, as macOS's own tiling does.
public enum StageManager {
    /// The strip's width in points, as macOS leaves it beside tiled windows.
    public static let stripWidth: CGFloat = 190

    /// Where tiled windows go: `visible` without the strip while Stage Manager is on and shows
    /// recent apps. The strip is on the left, or the right when the Dock is on the left.
    public static func tilingArea(_ visible: CGRect, enabled: Bool, recentAppsHidden: Bool, dockOnLeft: Bool) -> CGRect {
        guard enabled, !recentAppsHidden, visible.width > stripWidth * 3 else { return visible }
        if dockOnLeft { return CGRect(x: visible.minX, y: visible.minY, width: visible.width - stripWidth, height: visible.height) }
        return CGRect(x: visible.minX + stripWidth, y: visible.minY, width: visible.width - stripWidth, height: visible.height)
    }
}

