import Foundation

// Pure helpers the phone uses on mode payloads: Dock grid sizing, the phone's own Dock
// arrangement (order, hidden, kept apps, search) and Deck editing. They live next to the
// types they work on so they are unit tested with the rest of the protocol.

// MARK: - Dock grid

/// How big Dock tiles are and how many fit across.
public enum DockDensity: String, Codable, Sendable, CaseIterable {
    case compact, regular, large

    /// The icon size this density aims for, in points.
    public var preferredIcon: Double {
        switch self {
        case .compact: 52
        case .regular: 64
        case .large: 80
        }
    }
}

/// A grid that fills the available width exactly: whole columns, equal gaps, and icons never
/// smaller than `minimumIcon` or wider than their cell.
public struct DockGridMetrics: Equatable, Sendable {
    public var columns: Int
    public var iconSize: Double
    public var cellWidth: Double
    public var spacing: Double

    public static let minimumIcon = 44.0
    /// Icon width as a share of the cell, leaving room for the name under it.
    public static let iconShare = 0.8

    public init(columns: Int, iconSize: Double, cellWidth: Double, spacing: Double) {
        self.columns = columns
        self.iconSize = iconSize
        self.cellWidth = cellWidth
        self.spacing = spacing
    }

    /// `width` is the content width (inside the side margins). `scale` multiplies the density's
    /// icon size (the "Icon size" slider, 0.8...1.25).
    public static func fit(width: Double, density: DockDensity, scale: Double = 1, spacing: Double = 8) -> DockGridMetrics {
        let target = max(minimumIcon, density.preferredIcon * min(1.25, max(0.8, scale)))
        let cellTarget = target / iconShare
        let w = width.isFinite ? min(max(width, minimumIcon), 10_000) : minimumIcon
        var columns = max(1, Int(((w + spacing) / (cellTarget + spacing)).rounded(.down)))
        columns = max(columns, w >= 3 * (minimumIcon / iconShare) + 2 * spacing ? 3 : 1)
        var cell = (w - Double(columns - 1) * spacing) / Double(columns)
        // Too many columns for the smallest icon: drop one until icons fit.
        while columns > 1, cell * iconShare < minimumIcon {
            columns -= 1
            cell = (w - Double(columns - 1) * spacing) / Double(columns)
        }
        let icon = min(cell * iconShare, target * 1.15)
        return DockGridMetrics(columns: columns, iconSize: icon.rounded(.down), cellWidth: cell, spacing: spacing)
    }
}

// MARK: - The phone's own Dock

/// An app the user kept in the phone's Dock even when the Mac no longer lists it.
public struct KeptDockApp: Codable, Equatable, Sendable, Hashable {
    public var bundleID: String
    public var name: String
    public var iconKey: String?
    public init(bundleID: String, name: String, iconKey: String? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.iconKey = iconKey
    }
}

/// Order, hidden apps and kept apps, stored on the phone.
public struct DockArrangement: Codable, Equatable, Sendable {
    /// Bundle ids in the user's order. Apps not listed follow in the Mac's order.
    public var order: [String]
    public var hidden: Set<String>
    public var kept: [KeptDockApp]

    public init(order: [String] = [], hidden: Set<String> = [], kept: [KeptDockApp] = []) {
        self.order = order
        self.hidden = hidden
        self.kept = kept
    }

    public struct Arranged: Equatable, Sendable {
        /// The Dock grid: user order, then Mac order, kept apps included.
        public var apps: [DockApp]
        /// Recently used apps, shown in their own row.
        public var recent: [DockApp]
    }

    public func isKept(_ bundleID: String) -> Bool { kept.contains { $0.bundleID == bundleID } }

    public func arrange(_ macList: [DockApp], showRecent: Bool = true) -> Arranged {
        var main = macList.filter { $0.recent != true && !hidden.contains($0.bundleID) }
        let listed = Set(macList.map(\.bundleID))
        for k in kept where !listed.contains(k.bundleID) && !hidden.contains(k.bundleID) {
            main.append(DockApp(bundleID: k.bundleID, name: k.name, running: false, active: false, iconKey: k.iconKey))
        }
        // Kept apps that the Mac only lists as recent belong in the main grid.
        for app in macList where app.recent == true && isKept(app.bundleID) && !hidden.contains(app.bundleID) {
            var a = app
            a.recent = false
            main.append(a)
        }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let macIndex = Dictionary(main.enumerated().map { ($1.bundleID, $0) }, uniquingKeysWith: { a, _ in a })
        main.sort { a, b in
            switch (rank[a.bundleID], rank[b.bundleID]) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return macIndex[a.bundleID]! < macIndex[b.bundleID]!
            }
        }
        let inMain = Set(main.map(\.bundleID))
        let recent = showRecent
            ? macList.filter { $0.recent == true && !inMain.contains($0.bundleID) && !hidden.contains($0.bundleID) }
            : []
        return Arranged(apps: main, recent: recent)
    }

    /// Moves `bundleID` to just before `before` (nil = the end), freezing the shown order.
    public mutating func move(_ bundleID: String, before: String?, shown: [String]) {
        var list = shown.filter { $0 != bundleID }
        if let before, let i = list.firstIndex(of: before) {
            list.insert(bundleID, at: i)
        } else {
            list.append(bundleID)
        }
        order = list
    }

    public mutating func hide(_ bundleID: String) {
        hidden.insert(bundleID)
        kept.removeAll { $0.bundleID == bundleID }
    }

    public mutating func unhide(_ bundleID: String) { hidden.remove(bundleID) }

    public mutating func setKept(_ app: DockApp, _ on: Bool) {
        kept.removeAll { $0.bundleID == app.bundleID }
        if on {
            kept.append(KeptDockApp(bundleID: app.bundleID, name: app.name, iconKey: app.iconKey))
            hidden.remove(app.bundleID)
        }
    }

    /// Apps whose name matches the query, best matches first: name starts with it, then a word
    /// starts with it, then it appears anywhere. Ignores case and accents.
    public static func search(_ query: String, in apps: [DockApp]) -> [DockApp] {
        let q = query.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !q.isEmpty else { return [] }
        var seen = Set<String>()
        let scored: [(Int, Int, DockApp)] = apps.enumerated().compactMap { index, app in
            guard seen.insert(app.bundleID).inserted else { return nil }
            let name = app.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let score: Int
            if name.hasPrefix(q) { score = 0 }
            else if name.split(whereSeparator: { $0 == " " || $0 == "-" }).contains(where: { $0.hasPrefix(q) }) { score = 1 }
            else if name.contains(q) { score = 2 }
            else { return nil }
            return (score, index, app)
        }
        return scored.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map(\.2)
    }
}

// MARK: - Deck editing

extension DeckLayout {
    /// The page to show for the Mac's frontmost app, if one is linked to it.
    public func pageIndex(forFrontmost bundleID: String?) -> Int? {
        guard let bundleID else { return nil }
        return pages.firstIndex { $0.appBundleIDs?.contains(bundleID) == true }
    }

    /// The buttons of a page, or of a folder inside it.
    public func buttons(page: Int, folder: UUID? = nil) -> [DeckButton] {
        guard pages.indices.contains(page) else { return [] }
        guard let folder else { return pages[page].buttons }
        return pages[page].buttons.flattenedDeck.first { $0.id == folder }?.children ?? []
    }

    /// Adds a button at the end of a page or folder.
    public mutating func add(_ button: DeckButton, page: Int, folder: UUID? = nil) {
        guard pages.indices.contains(page) else { return }
        guard let folder else {
            pages[page].buttons.append(button)
            return
        }
        pages[page].buttons = Self.editing(pages[page].buttons, folder: folder) { $0.append(button) }
    }

    /// Replaces the button with the same id, wherever it is.
    public mutating func replace(_ button: DeckButton) {
        for p in pages.indices { pages[p].buttons = Self.replacing(pages[p].buttons, with: button) }
    }

    /// Removes the button (and a folder's contents) wherever it is.
    public mutating func remove(id: UUID) {
        for p in pages.indices { pages[p].buttons = Self.removing(pages[p].buttons, id: id) }
    }

    /// Moves a button within its page or folder to `index` (clamped).
    public mutating func move(id: UUID, to index: Int, page: Int, folder: UUID? = nil) {
        guard pages.indices.contains(page) else { return }
        func reorder(_ list: inout [DeckButton]) {
            guard let from = list.firstIndex(where: { $0.id == id }) else { return }
            let b = list.remove(at: from)
            list.insert(b, at: min(max(0, index), list.count))
        }
        guard let folder else {
            reorder(&pages[page].buttons)
            return
        }
        pages[page].buttons = Self.editing(pages[page].buttons, folder: folder, reorder)
    }

    /// Moves a page to `index` (clamped).
    public mutating func movePage(from: Int, to index: Int) {
        guard pages.indices.contains(from) else { return }
        let p = pages.remove(at: from)
        pages.insert(p, at: min(max(0, index), pages.count))
    }

    private static func editing(_ list: [DeckButton], folder: UUID, _ change: (inout [DeckButton]) -> Void) -> [DeckButton] {
        list.map { b in
            var b = b
            if b.id == folder {
                var kids = b.children ?? []
                change(&kids)
                b.children = kids
            } else if let kids = b.children {
                b.children = editing(kids, folder: folder, change)
            }
            return b
        }
    }

    private static func replacing(_ list: [DeckButton], with new: DeckButton) -> [DeckButton] {
        list.map { b in
            if b.id == new.id { return new }
            var b = b
            if let kids = b.children { b.children = replacing(kids, with: new) }
            return b
        }
    }

    private static func removing(_ list: [DeckButton], id: UUID) -> [DeckButton] {
        list.filter { $0.id != id }.map { b in
            var b = b
            if let kids = b.children { b.children = removing(kids, id: id) }
            return b
        }
    }
}

// MARK: - Deck grid packing

extension DeckButtonSize {
    /// Columns and rows the size covers.
    public var span: (columns: Int, rows: Int) {
        switch self {
        case .regular: (1, 1)
        case .wide: (2, 1)
        case .large: (2, 2)
        }
    }
}

/// Places tiles of mixed sizes on a grid in reading order, each in the first free spot that
/// fits (so a small tile can fill a gap a big one left). Spans wider than the grid shrink.
public enum DeckGridPacking {
    public struct Cell: Equatable, Sendable {
        public var column: Int, row: Int, columns: Int, rows: Int
        public init(column: Int, row: Int, columns: Int, rows: Int) {
            self.column = column; self.row = row; self.columns = columns; self.rows = rows
        }
    }

    public static func place(_ spans: [(columns: Int, rows: Int)], columns: Int) -> (cells: [Cell], rows: Int) {
        let cols = max(1, columns)
        var taken: [[Bool]] = []
        func free(_ c: Int, _ r: Int, _ w: Int, _ h: Int) -> Bool {
            guard c + w <= cols else { return false }
            for y in r..<(r + h) where y < taken.count {
                for x in c..<(c + w) where taken[y][x] { return false }
            }
            return true
        }
        var cells: [Cell] = []
        for span in spans {
            let w = min(max(1, span.columns), cols), h = max(1, span.rows)
            var r = 0
            search: while true {
                for c in 0..<cols where free(c, r, w, h) {
                    while taken.count < r + h { taken.append(Array(repeating: false, count: cols)) }
                    for y in r..<(r + h) { for x in c..<(c + w) { taken[y][x] = true } }
                    cells.append(Cell(column: c, row: r, columns: w, rows: h))
                    break search
                }
                r += 1
            }
        }
        return (cells, taken.count)
    }
}

// MARK: - Which modes the phone shows

/// The phone's mode list: order, hidden modes, and whether Actions is one mode or split back
/// into Deck, Macros, Clipboard and Present. Works on mode names so the phone's own enum can
/// change without touching this.
public struct ModeListLayout: Codable, Equatable, Sendable {
    /// The four tools that Actions combines.
    public static let actionParts = ["deck", "macros", "clipboard", "present"]
    public static let actions = "actions"
    /// Never hidden: the app is a trackpad first.
    public static let alwaysShown = "trackpad"
    public static let defaultOrder = ["trackpad", "keys", "media", "dock", "actions", "deck", "macros", "clipboard", "present", "remote"]
    /// Modes that start hidden, so the default pill stays at five. They still open from the
    /// mode menu's tools until Settings turns them on.
    public static let hiddenAtFirst: Set<String> = ["remote"]

    public var order: [String]
    public var hidden: Set<String>
    public var splitActions: Bool

    public init(order: [String] = ModeListLayout.defaultOrder, hidden: Set<String> = ModeListLayout.hiddenAtFirst,
                splitActions: Bool = false) {
        self.order = order
        self.hidden = hidden
        self.splitActions = splitActions
    }

    private enum CodingKeys: String, CodingKey { case order, hidden, splitActions }

    /// A list saved before a mode in `hiddenAtFirst` existed gets that mode added, hidden.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = try c.decode([String].self, forKey: .order)
        hidden = try c.decode(Set<String>.self, forKey: .hidden)
        splitActions = try c.decode(Bool.self, forKey: .splitActions)
        for name in Self.defaultOrder where Self.hiddenAtFirst.contains(name) && !order.contains(name) {
            order.append(name)
            hidden.insert(name)
        }
    }

    /// Modes in the switcher, in order. Unknown names are dropped; known ones missing from
    /// `order` are added at the end so a new mode is never lost.
    public func visible(known: [String]) -> [String] {
        let full = order.filter { known.contains($0) } + known.filter { !order.contains($0) }
        return full.filter { name in
            if name == Self.alwaysShown { return true }
            if hidden.contains(name) { return false }
            if name == Self.actions { return !splitActions }
            if Self.actionParts.contains(name) { return splitActions }
            return true
        }
    }

    /// The mode to open when `name` is not shown (for example Deck after Actions was merged).
    public func replacement(for name: String, known: [String]) -> String {
        let shown = visible(known: known)
        if shown.contains(name) { return name }
        if Self.actionParts.contains(name), shown.contains(Self.actions) { return Self.actions }
        if name == Self.actions, let part = Self.actionParts.first(where: shown.contains) { return part }
        return shown.first ?? Self.alwaysShown
    }

    public mutating func move(_ name: String, before: String?) {
        var list = order.filter { $0 != name }
        if let before, let i = list.firstIndex(of: before) { list.insert(name, at: i) } else { list.append(name) }
        order = list
    }
}

/// Tile size for a Deck page that should fill the screen: the fewest columns (so the biggest
/// tiles) whose packed rows fit the height, with rows stretched up to `maxAspect` taller than
/// wide to use leftover height. When nothing fits, `fallbackCell` sets the column count and
/// the page scrolls.
public struct DeckGridFit: Equatable, Sendable {
    public var columns: Int
    public var cellWidth: Double
    public var cellHeight: Double
    /// True when every row is on screen without scrolling.
    public var fits: Bool

    public static func best(spans: [(columns: Int, rows: Int)], width: Double, height: Double, spacing: Double = 8,
                            minColumns: Int = 3, maxColumns: Int = 10, maxCell: Double = 120,
                            fallbackCell: Double = 76, maxAspect: Double = 1.25) -> DeckGridFit {
        func cell(_ c: Int) -> Double { (width - Double(c - 1) * spacing) / Double(c) }
        for c in minColumns...max(minColumns, maxColumns) {
            let w = cell(c)
            guard w <= maxCell || c == maxColumns else { continue }
            let rows = DeckGridPacking.place(spans, columns: c).rows
            guard rows > 0 else { return DeckGridFit(columns: c, cellWidth: w, cellHeight: w, fits: true) }
            let needed = Double(rows) * w + Double(rows - 1) * spacing
            if needed <= height {
                let stretched = min(w * maxAspect, (height - Double(rows - 1) * spacing) / Double(rows))
                return DeckGridFit(columns: c, cellWidth: w, cellHeight: max(w, stretched), fits: true)
            }
        }
        let c = Int(min(64, max(Double(minColumns), ((width + spacing) / (fallbackCell + spacing)).rounded(.down))))
        return DeckGridFit(columns: c, cellWidth: cell(c), cellHeight: cell(c), fits: false)
    }
}
