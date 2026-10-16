import Foundation

// Pure grid arithmetic for the phone's tile grids (Actions, Pinned, folders, the Library's
// preview, Dock). Everything works from the size of the container the grid sits in, never
// the screen, because a mode can be shown in a pane of any size.

/// Splits items into rows that look balanced: as few rows as the width allows, row lengths
/// that differ by at most one, longer rows first. So 7 across 4 is 4 + 3 (never 4 + 3 with a
/// lonely tile on a third row), 6 across 4 is 3 + 3 and 9 across 4 is 3 + 3 + 3.
public enum BalancedRows {
    public static func counts(items: Int, maxPerRow: Int) -> [Int] {
        guard items > 0 else { return [] }
        let perRow = max(1, maxPerRow)
        let rows = (items + perRow - 1) / perRow
        let base = items / rows, extra = items % rows
        return (0..<rows).map { $0 < extra ? base + 1 : base }
    }
}

/// Where tiles go: column count, tile size and rows, chosen from the container width and how
/// many tiles there are.
///
/// - Tiles stay close to the preferred size, never under `minimumTile` (a comfortable finger
///   target) unless the container itself is narrower, and never over `preferred * maxGrowth`.
/// - Rows are balanced (`BalancedRows`) and every row is centred, so a short row sits in the
///   middle instead of hanging off the left edge.
/// - When balancing leaves rows shorter than the width allows, tiles grow (up to the cap) to
///   use the room, so 6 tiles on a phone are a 3 by 2 block of bigger tiles.
public struct TileGridMetrics: Equatable, Sendable {
    /// Width of the container the grid is centred in.
    public var containerWidth: Double
    /// The most tiles a row can hold at this size.
    public var columns: Int
    /// Side of a regular (one cell) tile.
    public var tile: Double
    public var spacing: Double
    /// Tiles in each row, top to bottom.
    public var rows: [Int]

    public static let minimumTile = 44.0

    public init(containerWidth: Double, columns: Int, tile: Double, spacing: Double, rows: [Int]) {
        self.containerWidth = containerWidth
        self.columns = columns
        self.tile = tile
        self.spacing = spacing
        self.rows = rows
    }

    /// Columns for a width at a preferred tile size: the count whose tiles, filling the width
    /// exactly, come closest to `preferred` (in ratio), without going under the minimum.
    public static func columns(width: Double, preferred: Double, spacing: Double, minimum: Double = minimumTile) -> Int {
        let w = max(0, width)
        let floorTile = max(minimum, preferred * 0.7)
        let most = max(1, Int(((w + spacing) / (floorTile + spacing)).rounded(.down)))
        var best = 1, bestCost = Double.infinity
        for c in 1...most {
            let t = (w - Double(c - 1) * spacing) / Double(c)
            guard t > 0 else { break }
            let cost = abs(log(t / preferred))
            if cost < bestCost - 1e-9 { best = c; bestCost = cost }
        }
        return best
    }

    /// The grid for `count` regular tiles.
    public static func fit(count: Int, width: Double, preferred: Double, spacing: Double = 10,
                           maxGrowth: Double = 1.3, minimum: Double = minimumTile) -> TileGridMetrics {
        let w = max(0, width)
        let cols = columns(width: w, preferred: preferred, spacing: spacing, minimum: minimum)
        let rows = BalancedRows.counts(items: count, maxPerRow: cols)
        let widest = max(1, rows.max() ?? cols)
        func fill(_ n: Int) -> Double { max(0, (w - Double(n - 1) * spacing) / Double(n)) }
        let cap = preferred * maxGrowth
        // The size every row could have at the full column count, then grown for short rows.
        var tile = min(fill(cols), cap)
        if widest < cols { tile = max(tile, min(fill(widest), cap)) }
        return TileGridMetrics(containerWidth: w, columns: cols, tile: tile.rounded(.down), spacing: spacing, rows: rows)
    }

    /// The grid for tiles of mixed spans (wide and large tiles): packed on the full column
    /// count (`DeckGridPacking`), the block centred. `rows` is left empty.
    public static func packed(width: Double, preferred: Double, spacing: Double = 10,
                              maxGrowth: Double = 1.3, minimum: Double = minimumTile) -> TileGridMetrics {
        let w = max(0, width)
        let cols = columns(width: w, preferred: preferred, spacing: spacing, minimum: minimum)
        let tile = min(max(0, (w - Double(cols - 1) * spacing) / Double(cols)), preferred * maxGrowth)
        return TileGridMetrics(containerWidth: w, columns: cols, tile: tile.rounded(.down), spacing: spacing, rows: [])
    }

    /// Width of a row of `n` tiles.
    public func rowWidth(_ n: Int) -> Double { n <= 0 ? 0 : Double(n) * tile + Double(n - 1) * spacing }

    /// Height of the balanced grid.
    public var height: Double { rows.isEmpty ? 0 : Double(rows.count) * tile + Double(rows.count - 1) * spacing }

    /// Top-left corner of tile `index` in a balanced grid, each row centred in the container.
    public func origin(of index: Int) -> (x: Double, y: Double) {
        var i = max(0, index)
        for (r, n) in rows.enumerated() {
            if i < n {
                let left = ((containerWidth - rowWidth(n)) / 2).rounded(.down)
                return (max(0, left) + Double(i) * (tile + spacing), Double(r) * (tile + spacing))
            }
            i -= n
        }
        return (0, height)
    }
}
