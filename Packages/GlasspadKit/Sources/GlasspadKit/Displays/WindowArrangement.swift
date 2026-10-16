import CoreGraphics
import Foundation

/// Several windows on one display at once, as in Window > Move & Resize > Arrange, and Split
/// View (Window > Full-Screen Tile). The windows of an arrangement come in order: the first
/// goes to the first place its name says ("Right & Left" puts the first window on the right),
/// as macOS does with the front window and the ones behind it.
public enum WindowArrangement: String, Codable, Sendable, CaseIterable, Hashable {
    case leftAndRight, rightAndLeft, topAndBottom, bottomAndTop
    /// One window on a half, the next two in the quarters of the other half.
    case leftAndQuarters, rightAndQuarters, topAndQuarters, bottomAndQuarters
    /// Up to four windows: top left, top right, bottom left, bottom right.
    case quarters
    /// Split View: two windows side by side in full screen.
    case fullScreen

    /// As macOS names it in the Window menu.
    public var title: String {
        switch self {
        case .leftAndRight: "Left & Right"
        case .rightAndLeft: "Right & Left"
        case .topAndBottom: "Top & Bottom"
        case .bottomAndTop: "Bottom & Top"
        case .leftAndQuarters: "Left & Quarters"
        case .rightAndQuarters: "Right & Quarters"
        case .topAndQuarters: "Top & Quarters"
        case .bottomAndQuarters: "Bottom & Quarters"
        case .quarters: "Quarters"
        case .fullScreen: "Full Screen"
        }
    }

    /// Where each window goes, in order.
    public var slots: [WindowSlot] {
        switch self {
        case .leftAndRight, .fullScreen: [.left, .right]
        case .rightAndLeft: [.right, .left]
        case .topAndBottom: [.top, .bottom]
        case .bottomAndTop: [.bottom, .top]
        case .leftAndQuarters: [.left, .topRight, .bottomRight]
        case .rightAndQuarters: [.right, .topLeft, .bottomLeft]
        case .topAndQuarters: [.top, .bottomLeft, .bottomRight]
        case .bottomAndQuarters: [.bottom, .topLeft, .topRight]
        case .quarters: [.topLeft, .topRight, .bottomLeft, .bottomRight]
        }
    }

    /// The fewest windows it takes. Quarters works with three, leaving a quarter empty.
    public var minimumWindows: Int { self == .quarters ? 3 : slots.count }

    /// Two windows side by side (left and right halves).
    public var isSideBySide: Bool { self == .leftAndRight || self == .rightAndLeft || self == .fullScreen }

    /// One window above the other.
    public var isStacked: Bool { self == .topAndBottom || self == .bottomAndTop }
}

/// One place in an arrangement: a half or a quarter of the display.
public enum WindowSlot: String, Codable, Sendable, CaseIterable, Hashable {
    case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight

    /// The columns (0 left, 1 right) and rows (0 top, 1 bottom) of a two by two grid it covers.
    public var columns: ClosedRange<Int> {
        switch self {
        case .left, .topLeft, .bottomLeft: 0...0
        case .right, .topRight, .bottomRight: 1...1
        case .top, .bottom: 0...1
        }
    }

    public var rows: ClosedRange<Int> {
        switch self {
        case .top, .topLeft, .topRight: 0...0
        case .bottom, .bottomLeft, .bottomRight: 1...1
        case .left, .right: 0...1
        }
    }
}

extension DisplayGeometry {
    /// Where a slot puts a window within `visible`, `gap` points around it and between
    /// neighbours, as macOS tiles: the halves match `tile(_:)`, the quarters split them again.
    public static func frame(of slot: WindowSlot, in visible: CGRect, gap: CGFloat = 0) -> CGRect {
        let area = visible.insetBy(dx: gap, dy: gap)
        let halfW = (area.width - gap) / 2, halfH = (area.height - gap) / 2
        let left = area.minX, right = area.maxX - halfW, top = area.minY, bottom = area.maxY - halfH
        let r: CGRect
        switch slot {
        case .left: r = CGRect(x: left, y: top, width: halfW, height: area.height)
        case .right: r = CGRect(x: right, y: top, width: halfW, height: area.height)
        case .top: r = CGRect(x: left, y: top, width: area.width, height: halfH)
        case .bottom: r = CGRect(x: left, y: bottom, width: area.width, height: halfH)
        case .topLeft: r = CGRect(x: left, y: top, width: halfW, height: halfH)
        case .topRight: r = CGRect(x: right, y: top, width: halfW, height: halfH)
        case .bottomLeft: r = CGRect(x: left, y: bottom, width: halfW, height: halfH)
        case .bottomRight: r = CGRect(x: right, y: bottom, width: halfW, height: halfH)
        }
        return r.wholePoints(inside: visible)
    }

    /// Every window's place in an arrangement, in order: on `visible` with margins, or for
    /// Split View on the whole display (`frame`), edge to edge with no menu bar.
    public static func frames(for arrangement: WindowArrangement, display frame: CGRect, visible: CGRect,
                              gap: CGFloat = 0) -> [CGRect] {
        if arrangement == .fullScreen { return arrangement.slots.map { self.frame(of: $0, in: frame) } }
        return arrangement.slots.map { self.frame(of: $0, in: visible, gap: gap) }
    }
}
