import CoreGraphics
import Foundation

/// The frame math behind Displays, on both sides: which display a window is on, where a tile
/// puts it, how it keeps its place on another display, and how displays snap together when
/// rearranged. Pure, so it is tested without moving anything.
///
/// Frames are global display coordinates as Quartz uses them (origin top-left of the main
/// display, y down). AppKit's screen frames have their origin at the bottom-left of the main
/// display with y up; `quartz(_:mainHeight:)` turns one into the other.
public enum DisplayGeometry {
    /// The gap macOS leaves around tiled windows when "Tiled windows have margins" is on.
    public static let tileMargin: CGFloat = 8

    /// An AppKit screen rectangle (y up from the bottom of the main display) in Quartz
    /// coordinates. `mainHeight` is the main display's height. It is its own inverse.
    public static func quartz(_ cocoa: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: cocoa.minX, y: mainHeight - cocoa.maxY, width: cocoa.width, height: cocoa.height)
    }

    /// The display showing most of the window; the nearest one when it is on none.
    public static func displayIndex(for window: CGRect, in displays: [CGRect]) -> Int? {
        guard !displays.isEmpty else { return nil }
        let areas = displays.map { d -> CGFloat in
            let i = d.intersection(window)
            return i.isNull ? 0 : i.width * i.height
        }
        if let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 { return best }
        return displayIndex(at: CGPoint(x: window.midX, y: window.midY), in: displays)
    }

    /// The display under `point`, or the nearest one.
    public static func displayIndex(at point: CGPoint, in displays: [CGRect]) -> Int? {
        if let inside = displays.firstIndex(where: { $0.contains(point) }) { return inside }
        func distance(_ r: CGRect) -> CGFloat {
            let dx = max(r.minX - point.x, 0, point.x - r.maxX), dy = max(r.minY - point.y, 0, point.y - r.maxY)
            return dx * dx + dy * dy
        }
        return displays.indices.min { distance(displays[$0]) < distance(displays[$1]) }
    }

    /// Where a tile puts the window within `visible` (the display without menu bar and Dock),
    /// with `gap` points around it and between halves. Whole points, like macOS itself.
    public static func tile(_ tile: WindowTile, window: CGRect, in visible: CGRect, gap: CGFloat = 0) -> CGRect {
        let area = visible.insetBy(dx: gap, dy: gap)
        let halfW = (area.width - gap) / 2, halfH = (area.height - gap) / 2
        let r: CGRect
        switch tile {
        case .leftHalf: r = CGRect(x: area.minX, y: area.minY, width: halfW, height: area.height)
        case .rightHalf: r = CGRect(x: area.maxX - halfW, y: area.minY, width: halfW, height: area.height)
        case .topHalf: r = CGRect(x: area.minX, y: area.minY, width: area.width, height: halfH)
        case .bottomHalf: r = CGRect(x: area.minX, y: area.maxY - halfH, width: area.width, height: halfH)
        case .fill: r = area
        case .center:
            let w = min(window.width, area.width), h = min(window.height, area.height)
            r = CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
        }
        return r.wholePoints(inside: visible)
    }

    /// Split: the first window on the left half, the second on the right.
    public static func split(in visible: CGRect, gap: CGFloat = 0) -> (left: CGRect, right: CGRect) {
        (tile(.leftHalf, window: .zero, in: visible, gap: gap), tile(.rightHalf, window: .zero, in: visible, gap: gap))
    }

    /// The window moved from one display's visible area to another's, keeping where it sits
    /// and how much of the display it covers (a left half stays a left half).
    public static func moved(_ window: CGRect, from: CGRect, to: CGRect) -> CGRect {
        guard from.width > 0, from.height > 0 else { return tile(.center, window: window, in: to) }
        let sx = to.width / from.width, sy = to.height / from.height
        let r = CGRect(x: to.minX + (window.minX - from.minX) * sx, y: to.minY + (window.minY - from.minY) * sy,
                       width: window.width * sx, height: window.height * sy)
        return r.clamped(inside: to).wholePoints(inside: to)
    }

    /// The window with its top-left corner at `origin`, same size, kept inside `visible`.
    public static func placed(_ window: CGRect, origin: CGPoint, in visible: CGRect) -> CGRect {
        CGRect(origin: origin, size: window.size).clamped(inside: visible).wholePoints(inside: visible)
    }

    /// The display after `index`, left to right (then top to bottom), wrapping around.
    public static func nextDisplayIndex(after index: Int, in displays: [CGRect]) -> Int? {
        guard displays.count > 1, displays.indices.contains(index) else { return nil }
        let order = displays.indices.sorted {
            let a = displays[$0], b = displays[$1]
            return a.minX != b.minX ? a.minX < b.minX : a.minY < b.minY
        }
        guard let at = order.firstIndex(of: index) else { return nil }
        return order[(at + 1) % order.count]
    }

    // MARK: Arrangement

    /// Every display's origin with `main` moved to 0, 0, which is how macOS gives a display
    /// the menu bar. The others keep their place next to it.
    public static func origins(makingMain main: UInt32, _ displays: [(id: UInt32, frame: CGRect)]) -> [DisplayOrigin] {
        guard let m = displays.first(where: { $0.id == main })?.frame.origin else { return [] }
        return displays.map { DisplayOrigin(display: $0.id, origin: CGPoint(x: $0.frame.minX - m.x, y: $0.frame.minY - m.y)) }
    }

    /// Where a display dragged to `proposed` lands, the way System Settings snaps it: touching
    /// an edge of another display and sharing part of that edge, lined up with its top, bottom,
    /// left or right when close, and never on top of any display. `others` are the rest, which
    /// stay where they are.
    public static func snap(_ proposed: CGRect, to others: [CGRect]) -> CGPoint {
        guard !others.isEmpty else { return proposed.origin.rounded }
        let w = proposed.width, h = proposed.height
        // How close (in points) counts as lined up, and how much edge two displays must share.
        let align = max(w, h) * 0.06
        var candidates: [CGPoint] = []
        for o in others {
            let shareY = min(h, o.height) / 8, shareX = min(w, o.width) / 8
            func alongY(_ y: CGFloat) -> CGFloat {
                var v = min(max(y, o.minY - h + shareY), o.maxY - shareY)
                for edge in [o.minY, o.maxY - h, o.midY - h / 2] where abs(v - edge) <= align { v = edge; break }
                return v
            }
            func alongX(_ x: CGFloat) -> CGFloat {
                var v = min(max(x, o.minX - w + shareX), o.maxX - shareX)
                for edge in [o.minX, o.maxX - w, o.midX - w / 2] where abs(v - edge) <= align { v = edge; break }
                return v
            }
            candidates.append(CGPoint(x: o.minX - w, y: alongY(proposed.minY)))
            candidates.append(CGPoint(x: o.maxX, y: alongY(proposed.minY)))
            candidates.append(CGPoint(x: alongX(proposed.minX), y: o.minY - h))
            candidates.append(CGPoint(x: alongX(proposed.minX), y: o.maxY))
        }
        let free = candidates.filter { c in
            let r = CGRect(origin: c, size: proposed.size).insetBy(dx: 0.5, dy: 0.5)
            return !others.contains { $0.intersects(r) }
        }
        func distance(_ p: CGPoint) -> CGFloat { hypot(p.x - proposed.minX, p.y - proposed.minY) }
        return (free.min { distance($0) < distance($1) } ?? proposed.origin).rounded
    }

    /// The arrangement moved so `main` sits at 0, 0 (the dragged display may have been the main one).
    public static func normalized(_ origins: [DisplayOrigin], main: UInt32) -> [DisplayOrigin] {
        guard let m = origins.first(where: { $0.display == main })?.origin else { return origins }
        return origins.map { DisplayOrigin(display: $0.display, origin: CGPoint(x: $0.origin.x - m.x, y: $0.origin.y - m.y)) }
    }
}

/// Maps global display coordinates to a miniature drawn in a view and back, the way System
/// Settings fits every display into its arrangement box: the same scale for all, centred.
public struct DisplayMiniature: Equatable, Sendable {
    /// Every display together, global coordinates.
    public let bounds: CGRect
    /// View points per display point.
    public let scale: CGFloat
    /// Where `bounds.origin` lands in the view.
    public let origin: CGPoint

    /// Fits `frames` into `size`, leaving `padding` on every side.
    public init(frames: [CGRect], fitting size: CGSize, padding: CGFloat = 0) {
        let union = frames.reduce(CGRect.null) { $0.union($1) }
        bounds = union.isNull ? CGRect(x: 0, y: 0, width: 1, height: 1) : union
        let room = CGSize(width: max(1, size.width - padding * 2), height: max(1, size.height - padding * 2))
        scale = min(room.width / bounds.width, room.height / bounds.height)
        origin = CGPoint(x: (size.width - bounds.width * scale) / 2, y: (size.height - bounds.height * scale) / 2)
    }

    public func toView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + (p.x - bounds.minX) * scale, y: origin.y + (p.y - bounds.minY) * scale)
    }

    public func toView(_ r: CGRect) -> CGRect {
        CGRect(origin: toView(r.origin), size: CGSize(width: r.width * scale, height: r.height * scale))
    }

    public func toGlobal(_ p: CGPoint) -> CGPoint {
        CGPoint(x: bounds.minX + (p.x - origin.x) / scale, y: bounds.minY + (p.y - origin.y) / scale)
    }

    /// A distance in the view as display points.
    public func toGlobal(length: CGFloat) -> CGFloat { length / scale }
}

private extension CGPoint {
    var rounded: CGPoint { CGPoint(x: x.rounded(), y: y.rounded()) }
}

private extension CGRect {
    /// No larger than `bounds`, moved inside it.
    func clamped(inside bounds: CGRect) -> CGRect {
        var r = self
        r.size.width = Swift.min(r.width, bounds.width)
        r.size.height = Swift.min(r.height, bounds.height)
        r.origin.x = Swift.min(Swift.max(r.minX, bounds.minX), bounds.maxX - r.width)
        r.origin.y = Swift.min(Swift.max(r.minY, bounds.minY), bounds.maxY - r.height)
        return r
    }

    /// Rounded to whole points without spilling outside `bounds`.
    func wholePoints(inside bounds: CGRect) -> CGRect {
        var x = minX.rounded(), y = minY.rounded()
        let w = width.rounded(), h = height.rounded()
        x = Swift.max(x, bounds.minX.rounded(.up))
        y = Swift.max(y, bounds.minY.rounded(.up))
        return CGRect(x: x, y: y, width: Swift.max(0, Swift.min(w, bounds.maxX.rounded(.down) - x)),
                      height: Swift.max(0, Swift.min(h, bounds.maxY.rounded(.down) - y)))
    }
}
