import Foundation
import Testing
@testable import GlasspadKit

/// SwiftUI can propose any width to a layout, including huge or odd ones while it measures.
/// Turning such a width straight into a column count trapped and took the app down (seen in
/// the Actions grid: TileGridMetrics.columns). Every grid must answer something sane instead.
@Suite struct GridRobustnessTests {
    static let widths: [Double] = [.greatestFiniteMagnitude, 1e300, 1e19, 1e12, .infinity, -.infinity, .nan,
                                   -1, 0, 0.5, 44, 390]

    @Test func tileGridsSurviveAnyWidth() {
        for w in Self.widths {
            let fit = TileGridMetrics.fit(count: 12, width: w, preferred: 76)
            #expect(fit.columns >= 1 && fit.columns <= 64, "\(w)")
            #expect(fit.tile.isFinite && fit.tile >= 0, "\(w)")
            let packed = TileGridMetrics.packed(width: w, preferred: 76)
            #expect(packed.columns >= 1 && packed.columns <= 64, "\(w)")
            #expect(TileGridMetrics.columns(width: w, preferred: 76, spacing: 10) <= 64)
        }
    }

    @Test func dockAndDeckGridsSurviveAnyWidth() {
        for w in Self.widths {
            for density in DockDensity.allCases {
                let dock = DockGridMetrics.fit(width: w, density: density)
                #expect(dock.columns >= 1 && dock.columns < 1000, "\(w) \(density)")
                #expect(dock.cellWidth.isFinite, "\(w) \(density)")
            }
            let deck = DeckGridFit.best(spans: Array(repeating: (columns: 1, rows: 1), count: 30), width: w, height: 500)
            #expect(deck.columns >= 1 && deck.columns <= 64, "\(w)")
        }
        // Ordinary widths are unchanged by the guard.
        #expect(DeckGridFit.best(spans: Array(repeating: (columns: 1, rows: 1), count: 200), width: 370, height: 500,
                                 fallbackCell: 76).columns == 4)
    }
}
