import CoreGraphics
import Foundation

/// What the phone's Split Screen sheet shows and then asks for: one window on the left half,
/// one on the right, on one display.
public struct SplitSelection: Equatable, Sendable, Hashable {
    public var left: UInt32
    public var right: UInt32
    public var display: UInt32
    /// The person chose the display; until then it follows the left window.
    public var displayPicked: Bool

    public init(left: UInt32, right: UInt32, display: UInt32, displayPicked: Bool = false) {
        self.left = left
        self.right = right
        self.display = display
        self.displayPicked = displayPicked
    }

    /// The other way round, on the same display.
    public var swapped: SplitSelection {
        SplitSelection(left: right, right: left, display: display, displayPicked: displayPicked)
    }
}

extension DisplaysState {
    /// How many windows the sheet offers for a side, front to back.
    public static let splitChoices = 12

    /// Where the sheet starts: `left` (the front window when nil) on the left, the window behind
    /// it on the right, on the left window's display. nil without two windows.
    public func defaultSplit(left id: UInt32? = nil) -> SplitSelection? {
        guard let left = id.flatMap(window) ?? windows.first,
              let right = windows.first(where: { $0.id != left.id }),
              let display = display(of: left) else { return nil }
        return SplitSelection(left: left.id, right: right.id, display: display.id)
    }

    /// The windows offered for a side: the front ones, with the chosen one always among them.
    public func splitChoices(keeping id: UInt32) -> [MacWindow] {
        var list = Array(windows.prefix(Self.splitChoices))
        if !list.contains(where: { $0.id == id }), let w = window(id) { list.append(w) }
        return list
    }

    /// `window` on one side. The window already on the other side swaps over, on the same
    /// display; a new left window brings its display along until the person picks one.
    public func choosing(_ id: UInt32, left: Bool, in s: SplitSelection) -> SplitSelection {
        if id == (left ? s.right : s.left) { return s.swapped }
        var next = s
        if left { next.left = id } else { next.right = id }
        if left, !next.displayPicked, let w = window(id), let d = display(of: w) { next.display = d.id }
        return next
    }

    /// The selection against newer windows and displays: a window that closed is replaced by
    /// the next one, a display that went away by the left window's. nil without two windows.
    public func refreshed(_ s: SplitSelection) -> SplitSelection? {
        guard windows.count > 1 else { return nil }
        var next = s
        if window(next.left) == nil {
            guard let w = windows.first(where: { $0.id != next.right }) else { return nil }
            next.left = w.id
        }
        if window(next.right) == nil || next.right == next.left {
            guard let w = windows.first(where: { $0.id != next.left }) else { return nil }
            next.right = w.id
        }
        if next.displayPicked, !shownDisplays.contains(where: { $0.id == next.display }) { next.displayPicked = false }
        if !next.displayPicked, let w = window(next.left), let d = display(of: w) { next.display = d.id }
        return next
    }

    /// What the phone sends, in order. The Mac splits on the left window's display, so a left
    /// window on another display goes over first; the Mac then brings the right one to it.
    /// nil when a window or the display is gone. Every Mac with Displays understands these.
    public func commands(for s: SplitSelection) -> [(window: UInt32, command: WindowCommand)]? {
        guard s.left != s.right, let left = window(s.left), window(s.right) != nil,
              shownDisplays.contains(where: { $0.id == s.display }) else { return nil }
        var out: [(window: UInt32, command: WindowCommand)] = []
        if display(of: left)?.id != s.display { out.append((s.left, .move(display: s.display, origin: nil))) }
        out.append((s.left, .split(with: s.right)))
        return out
    }

    /// Where the two windows land, for the sheet's picture: the halves of the display.
    public func splitFrames(for s: SplitSelection) -> (left: CGRect, right: CGRect)? {
        guard let d = shownDisplays.first(where: { $0.id == s.display }) else { return nil }
        return DisplayGeometry.split(in: d.visibleFrame, gap: CGFloat(tileMargin))
    }

    /// "Safari and Notes, side by side on Studio Display." (the display named only when there
    /// is more than one).
    public func splitSummary(_ s: SplitSelection) -> String? {
        guard let l = window(s.left), let r = window(s.right) else { return nil }
        let names = l.appName == r.appName ? "Two \(l.appName) windows" : "\(l.appName) and \(r.appName)"
        guard shownDisplays.count > 1, let d = shownDisplays.first(where: { $0.id == s.display }) else {
            return "\(names), side by side."
        }
        return "\(names), side by side on \(d.name)."
    }
}
