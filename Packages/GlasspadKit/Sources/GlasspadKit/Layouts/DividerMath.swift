import Foundation

/// How a dragged divider moves and where it settles. Everything is in points along the split,
/// so the feel is the same on any screen: panes stop at a sensible minimum, a pane dragged
/// past the edge folds away, and the line rests on thirds or the middle when near them.
public enum DividerMath {
    /// The shares the line rests on when released near them.
    public static let snapPoints: [Double] = [1.0 / 3, 0.5, 2.0 / 3]
    /// Smallest pane worth keeping open, in points.
    public static let minimumPane: Double = 120
    /// Within this many points of a snap point, the line jumps to it.
    public static let snapDistance: Double = 22
    /// Pull this far past the minimum toward an edge and the pane folds away on release.
    public static let foldDistance: Double = 56

    /// Where the line sits while the finger is down: free between the minimums, then with
    /// growing resistance past them, so a fold always feels deliberate. `position` is where
    /// the finger has dragged the line to, from the start of the span; `length` is the span.
    /// A line pulled out of a folded edge moves freely, so it does not jump on first touch.
    public static func tracking(_ position: Double, length: Double, resists: Bool = true) -> Double {
        guard length > 0 else { return 0.5 }
        let lower = min(minimumPane, length / 2), upper = max(length - minimumPane, length / 2)
        let p: Double
        if !resists {
            p = position
        } else if position < lower {
            p = lower - rubber(lower - position)
        } else if position > upper {
            p = upper + rubber(position - upper)
        } else {
            p = position
        }
        return min(max(p / length, 0), 1)
    }

    /// Where the line settles on release: folded (0 or 1), on a snap point, or where it is.
    public static func settle(_ position: Double, length: Double) -> Double {
        guard length > 0 else { return 0.5 }
        let lower = min(minimumPane, length / 2), upper = max(length - minimumPane, length / 2)
        if position < lower - foldDistance { return 0 }
        if position > upper + foldDistance { return 1 }
        let clamped = min(max(position, lower), upper)
        if let snap = nearestSnap(clamped, length: length) { return snap }
        return clamped / length
    }

    /// The snap point within reach of `position`, if any.
    public static func nearestSnap(_ position: Double, length: Double) -> Double? {
        guard length > 0 else { return nil }
        let best = snapPoints.min { abs($0 * length - position) < abs($1 * length - position) }
        guard let best, abs(best * length - position) <= snapDistance else { return nil }
        return best
    }

    /// Whether a release here would fold a pane away, for showing it before the finger lifts.
    public static func wouldFold(_ position: Double, length: Double) -> Bool {
        let s = settle(position, length: length)
        return s == 0 || s == 1
    }

    /// Diminishing travel past a limit: about a third of the drag, never more than the fold distance plus a bit.
    private static func rubber(_ overshoot: Double) -> Double {
        let limit = foldDistance * 1.6
        return limit * (1 - 1 / (overshoot * 0.55 / limit + 1))
    }
}
