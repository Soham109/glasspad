import CoreGraphics
import Foundation

/// What the phone's Arrange sheet shows and then asks for: an arrangement, the windows in its
/// places in order, and the display.
public struct ArrangeSelection: Equatable, Sendable, Hashable {
    public var arrangement: WindowArrangement
    /// One per place, in the arrangement's order. Quarters may leave the last place empty.
    public var windows: [UInt32]
    public var display: UInt32
    /// The person chose the display; until then it follows the first window.
    public var displayPicked: Bool

    public init(_ arrangement: WindowArrangement, windows: [UInt32], display: UInt32, displayPicked: Bool = false) {
        self.arrangement = arrangement
        self.windows = windows
        self.display = display
        self.displayPicked = displayPicked
    }

    /// Every window one place on: the other way round for two, clockwise for quarters.
    public var rotated: ArrangeSelection {
        // Clockwise through the places that have a window: top left, top right, bottom right, bottom left.
        let order = (arrangement == .quarters ? [0, 1, 3, 2] : Array(arrangement.slots.indices)).filter { $0 < windows.count }
        guard order.count > 1 else { return self }
        var next = self
        for (k, from) in order.enumerated() { next.windows[order[(k + 1) % order.count]] = windows[from] }
        return next
    }
}

extension DisplaysState {
    /// How many windows the sheet offers for a place, front to back.
    public static let arrangeChoices = 12

    /// The arrangements the sheet offers this Mac, in Apple's order. A Mac from before
    /// arrangements splits two windows left and right only.
    public var sheetArrangements: [WindowArrangement] {
        guard arrangements != nil else { return [.leftAndRight] }
        let offered = offeredArrangements
        return [.leftAndRight, .topAndBottom, .quarters, .fullScreen].filter(offered.contains)
    }

    /// Where the sheet starts: `first` (the front window when nil), then the windows behind it,
    /// on the first window's display. nil without enough windows.
    public func defaultArrangement(_ arrangement: WindowArrangement, first id: UInt32? = nil) -> ArrangeSelection? {
        guard let first = id.flatMap(window) ?? windows.first, let display = display(of: first) else { return nil }
        let rest = windows.filter { $0.id != first.id }.prefix(arrangement.slots.count - 1).map(\.id)
        let ids = [first.id] + rest
        guard ids.count >= arrangement.minimumWindows else { return nil }
        return ArrangeSelection(arrangement, windows: ids, display: display.id)
    }

    /// The same windows in another arrangement: the ones already chosen keep their order, more
    /// come from the front to fill it, and any beyond its places drop off. nil without enough.
    public func switching(_ s: ArrangeSelection, to arrangement: WindowArrangement) -> ArrangeSelection? {
        var ids = Array(s.windows.prefix(arrangement.slots.count))
        for w in windows where ids.count < arrangement.slots.count && !ids.contains(w.id) { ids.append(w.id) }
        guard ids.count >= arrangement.minimumWindows else { return nil }
        var next = s
        next.arrangement = arrangement
        next.windows = ids
        return next
    }

    /// The windows offered for a place: the front ones, with the chosen one always among them.
    /// An empty place offers only windows not placed yet.
    public func arrangeChoices(for place: Int, in s: ArrangeSelection) -> [MacWindow] {
        guard s.windows.indices.contains(place) else {
            return Array(windows.filter { !s.windows.contains($0.id) }.prefix(Self.arrangeChoices))
        }
        let id = s.windows[place]
        var list = Array(windows.prefix(Self.arrangeChoices))
        if !list.contains(where: { $0.id == id }), let w = window(id) { list.append(w) }
        return list
    }

    /// `id` in place `place`. A window already in another place swaps with it; a new first
    /// window brings its display along until the person picks one.
    public func choosing(_ id: UInt32, place: Int, in s: ArrangeSelection) -> ArrangeSelection {
        guard place >= 0, place < s.arrangement.slots.count, window(id) != nil else { return s }
        var next = s
        if let at = s.windows.firstIndex(of: id) {
            // Into an empty place it would leave a gap in the order: only swaps between places.
            guard s.windows.indices.contains(place) else { return s }
            next.windows.swapAt(at, place)
        } else if s.windows.indices.contains(place) {
            next.windows[place] = id
        } else {
            next.windows.append(id)
        }
        if !next.displayPicked, let first = next.windows.first.flatMap(window), let d = display(of: first) { next.display = d.id }
        return next
    }

    /// The selection against newer windows and displays: a window that closed is replaced by
    /// the front one not placed yet, a display that went away by the first window's. nil
    /// without enough windows for the arrangement.
    public func refreshed(_ s: ArrangeSelection) -> ArrangeSelection? {
        var ids: [UInt32] = []
        for id in s.windows {
            if window(id) != nil, !ids.contains(id) {
                ids.append(id)
            } else if let w = windows.first(where: { !ids.contains($0.id) && !s.windows.contains($0.id) }) {
                ids.append(w.id)
            }
        }
        for w in windows where ids.count < s.arrangement.minimumWindows && !ids.contains(w.id) { ids.append(w.id) }
        guard ids.count >= s.arrangement.minimumWindows else { return nil }
        var next = s
        next.windows = ids
        if next.displayPicked, !shownDisplays.contains(where: { $0.id == next.display }) { next.displayPicked = false }
        if !next.displayPicked, let w = window(ids[0]), let d = display(of: w) { next.display = d.id }
        return next
    }

    /// What the phone sends, in order. A Mac that takes the arrangement gets one command; an
    /// older one splits left and right: a first window on another display goes over first, then
    /// the Mac brings the second one to it. nil when a window or the display is gone, or the
    /// Mac cannot do it.
    public func commands(for s: ArrangeSelection) -> [(window: UInt32, command: WindowCommand)]? {
        guard let first = s.windows.first, let firstWindow = window(first), Set(s.windows).count == s.windows.count,
              s.windows.count >= s.arrangement.minimumWindows, s.windows.count <= s.arrangement.slots.count,
              s.windows.allSatisfy({ window($0) != nil }), shownDisplays.contains(where: { $0.id == s.display }) else { return nil }
        if offeredArrangements.contains(s.arrangement) {
            return [(first, .arrange(s.arrangement, windows: s.windows, display: s.display))]
        }
        guard s.arrangement == .leftAndRight, arrangements == nil else { return nil }
        var out: [(window: UInt32, command: WindowCommand)] = []
        if display(of: firstWindow)?.id != s.display { out.append((first, .move(display: s.display, origin: nil))) }
        out.append((first, .split(with: s.windows[1])))
        return out
    }

    /// Where each place is, for the sheet's picture: every place of the arrangement, filled or not.
    public func arrangeFrames(for s: ArrangeSelection) -> [CGRect]? {
        guard let d = shownDisplays.first(where: { $0.id == s.display }) else { return nil }
        return DisplayGeometry.frames(for: s.arrangement, display: d.frame, visible: d.visibleFrame, gap: CGFloat(tileMargin))
    }

    /// What it did, in words: "Safari and Notes, side by side on Studio Display." (the display
    /// named only when there is more than one).
    public func arrangeSummary(_ s: ArrangeSelection) -> String? {
        let placed = s.windows.compactMap(window)
        guard placed.count == s.windows.count, placed.count > 1 else { return nil }
        let apps = placed.map(\.appName)
        let names: String
        if Set(apps).count == 1 {
            names = "\(["Two", "Three", "Four"][min(apps.count, 4) - 2]) \(apps[0]) windows"
        } else {
            names = apps.dropLast().joined(separator: ", ") + " and " + apps[apps.count - 1]
        }
        let how = switch s.arrangement {
        case .leftAndRight, .rightAndLeft: ", side by side"
        case .topAndBottom, .bottomAndTop: ", one above the other"
        case .fullScreen: ", side by side in full screen"
        default: ", in quarters"
        }
        guard shownDisplays.count > 1, let d = shownDisplays.first(where: { $0.id == s.display }) else { return names + how + "." }
        return names + how + " on \(d.name)."
    }
}

extension WindowArrangement {
    /// The Arrange sheet's button: what will happen.
    public var actionTitle: String {
        switch self {
        case .leftAndRight, .rightAndLeft: "Split"
        case .topAndBottom, .bottomAndTop: "Split Top & Bottom"
        case .fullScreen: "Split in Full Screen"
        default: "Arrange in Quarters"
        }
    }

    /// A place's name, for VoiceOver.
    public func placeName(_ place: Int) -> String {
        guard slots.indices.contains(place) else { return "" }
        return switch slots[place] {
        case .left: "Left half"
        case .right: "Right half"
        case .top: "Top half"
        case .bottom: "Bottom half"
        case .topLeft: "Top left quarter"
        case .topRight: "Top right quarter"
        case .bottomLeft: "Bottom left quarter"
        case .bottomRight: "Bottom right quarter"
        }
    }
}
