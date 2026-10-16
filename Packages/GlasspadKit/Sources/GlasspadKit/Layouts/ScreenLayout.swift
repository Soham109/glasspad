import CoreGraphics
import Foundation

/// Which way a layout splits the screen.
public enum SplitDirection: String, Codable, Sendable, CaseIterable {
    /// Side by side in landscape, one above the other in portrait.
    case automatic
    case sideBySide
    case stacked

    /// Whether the main split runs side by side on a screen of this shape.
    public func isSideBySide(landscape: Bool) -> Bool {
        switch self {
        case .automatic: landscape
        case .sideBySide: true
        case .stacked: false
        }
    }
}

/// A screen made of one to three panes, each showing one of the phone's modes.
///
/// Two panes share the screen along the main split. A third pane splits the second one the
/// other way, so the first pane keeps a whole side (a trackpad on the left, Media over Actions
/// on the right). Modes are stored by name (`AppMode.rawValue` on the phone) so the model
/// stays independent of the app, and a mode a newer build added survives an older one.
public struct ScreenLayout: Codable, Identifiable, Equatable, Hashable, Sendable {
    public static let maxPanes = 3

    public var id: UUID
    public var name: String
    /// Mode names, one per pane, in reading order. Never empty, never more than three, no repeats.
    public private(set) var panes: [String]
    public var direction: SplitDirection
    /// The first pane's share of the main split. 0 or 1 means one side is folded away.
    public var split: Double
    /// With three panes: the second pane's share of the other half.
    public var innerSplit: Double

    public init(id: UUID = UUID(), name: String, panes: [String], direction: SplitDirection = .automatic,
                split: Double = 0.5, innerSplit: Double = 0.5) {
        self.id = id
        self.name = name
        self.panes = Self.cleaned(panes)
        self.direction = direction
        self.split = Self.clampShare(split)
        self.innerSplit = Self.clampShare(innerSplit)
    }

    // MARK: Editing

    /// Puts `mode` in pane `index`. If another pane already shows it, the two swap, so a mode
    /// is never on screen twice (two trackpads, or two keyboards fighting over typing).
    public mutating func setMode(_ mode: String, at index: Int) {
        guard panes.indices.contains(index), panes[index] != mode else { return }
        if let other = panes.firstIndex(of: mode) {
            panes.swapAt(index, other)
        } else {
            panes[index] = mode
        }
    }

    /// Swaps two panes' modes. Sizes stay where they are.
    public mutating func swapPanes(_ a: Int, _ b: Int) {
        guard panes.indices.contains(a), panes.indices.contains(b) else { return }
        panes.swapAt(a, b)
    }

    /// Adds a pane showing `mode` (the first of `candidates` not already on screen when nil).
    /// Returns false when the layout is full or nothing is left to show.
    @discardableResult
    public mutating func addPane(_ mode: String? = nil, candidates: [String] = []) -> Bool {
        guard panes.count < Self.maxPanes else { return false }
        guard let next = mode.flatMap({ panes.contains($0) ? nil : $0 })
                ?? candidates.first(where: { !panes.contains($0) }) else { return false }
        panes.append(next)
        if panes.count == 2 { split = 0.5 } else { innerSplit = 0.5 }
        if split == 0 || split == 1 { split = 0.5 }
        return true
    }

    /// Removes a pane. The last pane always stays.
    public mutating func removePane(at index: Int) {
        guard panes.count > 1, panes.indices.contains(index) else { return }
        panes.remove(at: index)
        if panes.count == 1 { split = 0.5 }
        innerSplit = 0.5
        if split == 0 || split == 1 { split = 0.5 }
    }

    /// Back to even shares.
    public mutating func resetSizes() {
        split = 0.5
        innerSplit = 0.5
    }

    /// Panes that are not folded away.
    public var visiblePaneIndices: [Int] {
        switch panes.count {
        case 1: return [0]
        case 2: return split <= 0 ? [1] : split >= 1 ? [0] : [0, 1]
        default:
            let inner: [Int] = innerSplit <= 0 ? [2] : innerSplit >= 1 ? [1] : [1, 2]
            return split <= 0 ? inner : split >= 1 ? [0] : [0] + inner
        }
    }

    /// The modes on screen right now, in pane order.
    public var visibleModes: [String] { visiblePaneIndices.map { panes[$0] } }

    // MARK: Geometry

    /// Where each pane and divider goes on a screen of `size`. Folded panes get no frame; their
    /// divider stays at the edge so it can be pulled back out.
    public func arrangement(in size: CGSize, gap: CGFloat) -> Arrangement {
        let landscape = size.width > size.height
        let across = direction.isSideBySide(landscape: landscape)
        let whole = CGRect(origin: .zero, size: size)
        guard panes.count > 1 else {
            return Arrangement(panes: [PaneFrame(index: 0, rect: whole)], dividers: [])
        }
        var frames: [PaneFrame] = []
        var dividers: [DividerFrame] = []
        let (first, rest, line) = Self.cut(whole, share: split, across: across, gap: gap)
        dividers.append(DividerFrame(level: .main, rect: line, sideBySide: across, span: whole, share: split))
        if let first { frames.append(PaneFrame(index: 0, rect: first)) }
        if let rest {
            if panes.count == 2 {
                frames.append(PaneFrame(index: 1, rect: rest))
            } else {
                let (second, third, innerLine) = Self.cut(rest, share: innerSplit, across: !across, gap: gap)
                dividers.append(DividerFrame(level: .inner, rect: innerLine, sideBySide: !across, span: rest, share: innerSplit))
                if let second { frames.append(PaneFrame(index: 1, rect: second)) }
                if let third { frames.append(PaneFrame(index: 2, rect: third)) }
            }
        }
        return Arrangement(panes: frames, dividers: dividers)
    }

    /// Splits `rect` at `share` with a `gap` wide line between. A share of 0 or 1 folds that
    /// side away and leaves the line at the edge.
    private static func cut(_ rect: CGRect, share: Double, across: Bool, gap: CGFloat)
        -> (CGRect?, CGRect?, CGRect) {
        let length = across ? rect.width : rect.height
        if share <= 0 || share >= 1 {
            let atStart = share <= 0
            let line = across
                ? CGRect(x: atStart ? rect.minX : rect.maxX - gap, y: rect.minY, width: gap, height: rect.height)
                : CGRect(x: rect.minX, y: atStart ? rect.minY : rect.maxY - gap, width: rect.width, height: gap)
            return atStart ? (nil, rect, line) : (rect, nil, line)
        }
        let firstLength = max(0, (length - gap) * share)
        let secondLength = max(0, length - gap - firstLength)
        if across {
            return (CGRect(x: rect.minX, y: rect.minY, width: firstLength, height: rect.height),
                    CGRect(x: rect.minX + firstLength + gap, y: rect.minY, width: secondLength, height: rect.height),
                    CGRect(x: rect.minX + firstLength, y: rect.minY, width: gap, height: rect.height))
        }
        return (CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: firstLength),
                CGRect(x: rect.minX, y: rect.minY + firstLength + gap, width: rect.width, height: secondLength),
                CGRect(x: rect.minX, y: rect.minY + firstLength, width: rect.width, height: gap))
    }

    public struct Arrangement: Equatable, Sendable {
        public var panes: [PaneFrame]
        public var dividers: [DividerFrame]
    }

    public struct PaneFrame: Equatable, Sendable {
        public var index: Int
        public var rect: CGRect
    }

    public struct DividerFrame: Equatable, Sendable {
        public enum Level: Sendable { case main, inner }
        public var level: Level
        public var rect: CGRect
        /// The line runs top to bottom between panes side by side.
        public var sideBySide: Bool
        /// The area this divider shares out, for turning a drag into a share.
        public var span: CGRect
        public var share: Double
    }

    // MARK: Cleaning

    static func cleaned(_ modes: [String]) -> [String] {
        var seen = Set<String>()
        let unique = modes.filter { !$0.isEmpty && seen.insert($0).inserted }
        return Array((unique.isEmpty ? ["trackpad"] : unique).prefix(maxPanes))
    }

    static func clampShare(_ value: Double) -> Double {
        guard value.isFinite else { return 0.5 }
        return min(max(value, 0), 1)
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey { case id, name, panes, direction, split, innerSplit }

    /// Tolerant on purpose: a missing or unknown field falls back to a sensible value rather
    /// than losing the person's layout.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Layout"
        panes = Self.cleaned((try? c.decodeIfPresent([String].self, forKey: .panes)) ?? [])
        let rawDirection = (try? c.decodeIfPresent(String.self, forKey: .direction)) ?? nil
        direction = rawDirection.flatMap(SplitDirection.init(rawValue:)) ?? .automatic
        split = Self.clampShare((try? c.decodeIfPresent(Double.self, forKey: .split)) ?? 0.5)
        innerSplit = Self.clampShare((try? c.decodeIfPresent(Double.self, forKey: .innerSplit)) ?? 0.5)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(panes, forKey: .panes)
        try c.encode(direction, forKey: .direction)
        try c.encode(split, forKey: .split)
        try c.encode(innerSplit, forKey: .innerSplit)
    }
}

/// Everything saved about layouts: the person's own, in their order, and which one is open.
public struct LayoutLibrary: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var layouts: [ScreenLayout]
    /// The layout on screen when the app last closed; nil when a single mode was.
    public var activeID: UUID?

    public init(layouts: [ScreenLayout] = [], activeID: UUID? = nil) {
        version = Self.currentVersion
        self.layouts = layouts
        self.activeID = activeID
    }

    private enum CodingKeys: String, CodingKey { case version, layouts, activeID }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 0
        // One unreadable layout must not take the others with it.
        let loose = (try? c.decodeIfPresent([Lossy].self, forKey: .layouts)) ?? []
        var seen = Set<UUID>()
        layouts = loose.compactMap(\.value).filter { seen.insert($0.id).inserted }
        let active = (try? c.decodeIfPresent(UUID.self, forKey: .activeID)) ?? nil
        activeID = active.flatMap { id in layouts.contains { $0.id == id } ? id : nil }
        version = Self.currentVersion
    }

    private struct Lossy: Decodable {
        let value: ScreenLayout?
        init(from decoder: Decoder) throws {
            value = try? ScreenLayout(from: decoder)
        }
    }

    // MARK: Editing

    public func layout(_ id: UUID) -> ScreenLayout? { layouts.first { $0.id == id } }

    /// Adds a new layout or replaces the one with the same id.
    public mutating func save(_ layout: ScreenLayout) {
        if let i = layouts.firstIndex(where: { $0.id == layout.id }) {
            layouts[i] = layout
        } else {
            layouts.append(layout)
        }
    }

    /// A copy right after the original, named "<name> Copy".
    @discardableResult
    public mutating func duplicate(_ id: UUID) -> ScreenLayout? {
        guard let i = layouts.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = layouts[i]
        copy.id = UUID()
        copy.name = uniqueName("\(layouts[i].name) Copy")
        layouts.insert(copy, at: i + 1)
        return copy
    }

    public mutating func delete(_ id: UUID) {
        layouts.removeAll { $0.id == id }
        if activeID == id { activeID = nil }
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { layouts[$0] }
        var rest = layouts
        for i in source.sorted(by: >) { rest.remove(at: i) }
        let before = source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: min(rest.count, destination - before))
        layouts = rest
    }

    /// `base`, or `base 2`, `base 3`... whichever no layout uses yet.
    public func uniqueName(_ base: String, ignoring id: UUID? = nil) -> String {
        let taken = Set(layouts.filter { $0.id != id }.map { $0.name.lowercased() })
        if !taken.contains(base.lowercased()) { return base }
        var n = 2
        while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }
}
