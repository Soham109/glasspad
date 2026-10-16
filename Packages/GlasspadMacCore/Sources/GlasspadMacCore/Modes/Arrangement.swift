import CoreGraphics
import Foundation
import GlasspadKit

/// Where an arrangement puts each window once some of them turned out not to shrink as far as
/// their place: a two by two grid whose column and row lines move so a window that keeps its
/// size gets it and its neighbours the rest, as Split Screen does for two. Pure, so tests drive it.
public enum ArrangementLayout {
    /// One stretch of a line: where it starts and how long it is.
    struct Span: Equatable {
        var start: CGFloat
        var length: CGFloat
        var end: CGFloat { start + length }
    }

    /// Two neighbouring spans (`a` before `b`, `gap` between), widened for one whose minimum
    /// (0 when not known) is more than it has: it keeps its outer edge and the other gets the
    /// rest. nil when they cannot both fit.
    static func divide(_ a: Span, _ b: Span, gap: CGFloat, minA: CGFloat, minB: CGFloat) -> (Span, Span)? {
        let wideA = minA.rounded(.up) > a.length, wideB = minB.rounded(.up) > b.length
        if !wideA && !wideB { return (a, b) }
        if wideA && wideB { return nil }
        // Room for both, between their outer edges.
        let room = b.end - a.start - gap
        if wideA {
            let la = minA.rounded(.up), lb = room - la
            guard lb > 0, lb >= minB else { return nil }
            return (Span(start: a.start, length: la), Span(start: b.end - lb, length: lb))
        }
        let lb = minB.rounded(.up), la = room - lb
        guard la > 0, la >= minA else { return nil }
        return (Span(start: a.start, length: la), Span(start: b.end - lb, length: lb))
    }

    /// The frames of the first `minimums.count` places of `arrangement` on `visible`, `gap`
    /// around and between them; `minimums` are each window's smallest size learned so far
    /// (zero when it fit). nil when they cannot all fit.
    public static func frames(_ arrangement: WindowArrangement, in visible: CGRect, gap: CGFloat,
                              minimums: [CGSize]) -> [CGRect]? {
        let slots = Array(arrangement.slots.prefix(minimums.count))
        func even(_ s: WindowSlot) -> CGRect { DisplayGeometry.frame(of: s, in: visible, gap: gap) }
        let tl = even(.topLeft), br = even(.bottomRight), whole = (even(.top), even(.left))
        var columns = [Span(start: tl.minX, length: tl.width), Span(start: br.minX, length: br.width)]
        var rows = [Span(start: tl.minY, length: tl.height), Span(start: br.minY, length: br.height)]
        let across = Span(start: whole.0.minX, length: whole.0.width), down = Span(start: whole.1.minY, length: whole.1.height)
        var columnMinimum: [CGFloat] = [0, 0], rowMinimum: [CGFloat] = [0, 0]
        for (slot, m) in zip(slots, minimums) {
            if slot.columns.count == 1 {
                columnMinimum[slot.columns.lowerBound] = max(columnMinimum[slot.columns.lowerBound], m.width)
            } else if m.width.rounded(.up) > across.length {
                return nil
            }
            if slot.rows.count == 1 {
                rowMinimum[slot.rows.lowerBound] = max(rowMinimum[slot.rows.lowerBound], m.height)
            } else if m.height.rounded(.up) > down.length {
                return nil
            }
        }
        if slots.contains(where: { $0.columns.count == 1 }) {
            guard let (a, b) = divide(columns[0], columns[1], gap: gap, minA: columnMinimum[0], minB: columnMinimum[1]) else { return nil }
            columns = [a, b]
        }
        if slots.contains(where: { $0.rows.count == 1 }) {
            guard let (a, b) = divide(rows[0], rows[1], gap: gap, minA: rowMinimum[0], minB: rowMinimum[1]) else { return nil }
            rows = [a, b]
        }
        return slots.map { s in
            let x = s.columns.count == 1 ? columns[s.columns.lowerBound] : across
            let y = s.rows.count == 1 ? rows[s.rows.lowerBound] : down
            return CGRect(x: x.start, y: y.start, width: x.length, height: y.length)
        }
    }

    /// Why windows with these learned minimum sizes (zero when they fit) cannot share the
    /// display in this arrangement, naming the ones that stayed too large.
    public static func failure(_ arrangement: WindowArrangement, apps: [String], minimums: [CGSize],
                               display: String) -> WindowFailure {
        let slots = Array(arrangement.slots.prefix(apps.count))
        func app(_ slot: WindowSlot) -> (name: String, minimum: CGSize) {
            guard let i = slots.firstIndex(of: slot) else { return ("", .zero) }
            return (apps[i], minimums[i])
        }
        if arrangement.isSideBySide {
            let l = app(.left), r = app(.right)
            return SplitScreen.tooWide(left: l.name, right: r.name, leftMinimum: l.minimum.width,
                                       rightMinimum: r.minimum.width, display: display)
        }
        if arrangement.isStacked {
            let t = app(.top), b = app(.bottom)
            if t.minimum.height > 0 && b.minimum.height > 0 { return .bothTooTall(t.name, b.name, display: display) }
            return .tooTall(t.minimum.height > 0 ? t.name : b.name)
        }
        var names: [String] = []
        for (name, m) in zip(apps, minimums) where m != .zero && !names.contains(name) { names.append(name) }
        return .tooBigForQuarters(names.isEmpty ? Array(apps.prefix(1)) : names, display: display)
    }

    /// True when every window sits in its place on `visible`, as macOS's own Arrange leaves
    /// them (its margins may differ from ours, so only where each one is counts).
    public static func looksArranged(_ arrangement: WindowArrangement, frames: [CGRect], in visible: CGRect) -> Bool {
        let tolerance: CGFloat = 24
        let places = arrangement.slots.prefix(frames.count).map { DisplayGeometry.frame(of: $0, in: visible) }
        guard places.count == frames.count else { return false }
        return zip(frames, places).allSatisfy { f, place in
            place.insetBy(dx: -tolerance, dy: -tolerance).contains(f)
                && f.width >= place.width - 3 * tolerance && f.height >= place.height - 3 * tolerance
        }
    }

    /// True when macOS's own Arrange item can do it: every window already on the target
    /// display (it arranges there), and the windows are the front ones in order (it takes the
    /// front window and the ones behind it). Quarters takes four.
    public static func nativeFits(_ arrangement: WindowArrangement, windowDisplays: [Int?], target: Int,
                                  frontOrder: [UInt32], windows: [UInt32]) -> Bool {
        guard arrangement != .fullScreen, windows.count == arrangement.slots.count,
              windowDisplays.count == windows.count, windowDisplays.allSatisfy({ $0 == target }) else { return false }
        return Array(frontOrder.prefix(windows.count)) == windows
    }
}

/// Where each window was before Glasspad last moved it, for Return to Previous Size. Kept in
/// memory only: after Glasspad restarts, macOS's own Return to Previous Size takes over.
@MainActor
public final class WindowHistory {
    public static let shared = WindowHistory()

    private var frames: [UInt32: CGRect] = [:]
    /// Enough for every window anyone has open; the oldest go first past it.
    static let limit = 200
    private var order: [UInt32] = []

    public init() {}

    /// Remembers where the window is now, before a move.
    public func remember(_ w: MovableWindow) {
        guard let id = w.windowID, let f = w.frame else { return }
        remember(id, f)
    }

    public func remember(_ id: UInt32, _ frame: CGRect) {
        frames[id] = frame
        order.removeAll { $0 == id }
        order.append(id)
        while order.count > Self.limit { frames[order.removeFirst()] = nil }
    }

    public func previous(_ id: UInt32) -> CGRect? { frames[id] }

    public func forget(_ id: UInt32) {
        frames[id] = nil
        order.removeAll { $0 == id }
    }
}
