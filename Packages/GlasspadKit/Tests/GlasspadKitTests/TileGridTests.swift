import Foundation
import Testing
@testable import GlasspadKit

@Suite struct BalancedRowsTests {
    @Test func rowsAreBalancedWithNoLonelyTile() {
        #expect(BalancedRows.counts(items: 7, maxPerRow: 4) == [4, 3])
        #expect(BalancedRows.counts(items: 6, maxPerRow: 4) == [3, 3])
        #expect(BalancedRows.counts(items: 8, maxPerRow: 4) == [4, 4])
        #expect(BalancedRows.counts(items: 9, maxPerRow: 4) == [3, 3, 3])
        #expect(BalancedRows.counts(items: 10, maxPerRow: 4) == [4, 3, 3])
        #expect(BalancedRows.counts(items: 5, maxPerRow: 4) == [3, 2])
        #expect(BalancedRows.counts(items: 1, maxPerRow: 4) == [1])
        #expect(BalancedRows.counts(items: 0, maxPerRow: 4).isEmpty)
        #expect(BalancedRows.counts(items: 3, maxPerRow: 0) == [1, 1, 1])
    }

    @Test(arguments: 1...40)
    func everyCountKeepsRowsWithinOneAndFewestRows(n: Int) {
        for perRow in 1...8 {
            let rows = BalancedRows.counts(items: n, maxPerRow: perRow)
            #expect(rows.reduce(0, +) == n)
            #expect(rows.max()! - rows.min()! <= 1)
            #expect(rows.max()! <= perRow)
            #expect(rows.count == (n + perRow - 1) / perRow)
            #expect(rows == rows.sorted(by: >))
        }
    }
}

@Suite struct TileGridTests {
    /// Full phone portrait and landscape, a landscape half, half and third panes, and a
    /// split-screen sliver.
    static let widths = [370.0, 842.0, 400.0, 330.0, 250.0, 180.0, 120.0, 1000.0]

    @Test(arguments: widths)
    func tilesAreTappableNeverHugeAndRowsFitTheWidth(width: Double) {
        for preferred in [64.0, 76.0, 99.0] {
            for n in 1...24 {
                let m = TileGridMetrics.fit(count: n, width: width, preferred: preferred)
                #expect(m.tile >= TileGridMetrics.minimumTile, "n \(n) width \(width)")
                #expect(m.tile <= preferred * 1.3 + 0.001)
                #expect(m.rows.reduce(0, +) == n)
                for row in m.rows { #expect(m.rowWidth(row) <= width + 0.001) }
            }
        }
    }

    @Test func phoneCountsMakeSymmetricBlocks() {
        // iPhone portrait content width: 4 columns at the preferred size.
        #expect(TileGridMetrics.fit(count: 8, width: 370, preferred: 76).rows == [4, 4])
        #expect(TileGridMetrics.fit(count: 7, width: 370, preferred: 76).rows == [4, 3])
        let six = TileGridMetrics.fit(count: 6, width: 370, preferred: 76)
        #expect(six.rows == [3, 3])
        // Short rows let tiles grow, but only so far.
        #expect(six.tile > TileGridMetrics.fit(count: 8, width: 370, preferred: 76).tile)
        #expect(six.tile <= 76 * 1.3)
        #expect(TileGridMetrics.fit(count: 9, width: 370, preferred: 76).rows == [3, 3, 3])
    }

    @Test func rowsAreCentred() {
        let m = TileGridMetrics.fit(count: 7, width: 370, preferred: 76)
        let first = m.origin(of: 0), lastRow = m.origin(of: 4)
        // The full row spans the width; the short row has equal room on both sides.
        #expect(abs(first.x - (370 - m.rowWidth(4)) / 2) <= 1)
        let leftGap = lastRow.x
        let rightGap = 370 - (lastRow.x + m.rowWidth(3))
        #expect(abs(leftGap - rightGap) <= 1)
        #expect(lastRow.y == m.tile + m.spacing)
        #expect(m.height == 2 * m.tile + m.spacing)
    }

    @Test func narrowPanesUseFewerColumnsNotTinyTiles() {
        let third = TileGridMetrics.fit(count: 8, width: 120, preferred: 76)
        #expect(third.columns == 2)
        #expect(third.rows == [2, 2, 2, 2])
        let wide = TileGridMetrics.fit(count: 8, width: 842, preferred: 76)
        #expect(wide.rows == [8])
        // A pane narrower than one tile still draws one whole tile.
        #expect(TileGridMetrics.fit(count: 3, width: 40, preferred: 76).columns == 1)
    }

    @Test func unboundedOrBadWidthsNeverCrash() {
        for w in [Double.infinity, -.infinity, .nan, -20, 0, 1e9] {
            let m = TileGridMetrics.fit(count: 5, width: w, preferred: 76)
            #expect(m.columns >= 1)
            #expect(m.rows.reduce(0, +) == 5)
            #expect(m.tile.isFinite)
            #expect(TileGridMetrics.packed(width: w, preferred: 76).columns >= 1)
        }
    }

    @Test func packedGridsUseTheFullColumnCount() {
        let m = TileGridMetrics.packed(width: 370, preferred: 76)
        #expect(m.columns == 4)
        #expect(abs(Double(m.columns) * m.tile + Double(m.columns - 1) * m.spacing - 370) < 1)
    }
}
