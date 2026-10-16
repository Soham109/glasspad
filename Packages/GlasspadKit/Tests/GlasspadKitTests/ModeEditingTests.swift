import Foundation
import Testing
@testable import GlasspadKit

@Suite struct DockGridTests {
    /// iPhone 18 Pro: 402 pt portrait, 874 pt landscape; minus 16 pt margins (and the landscape
    /// safe areas, about 62 pt a side).
    @Test(arguments: [370.0, 330.0, 250.0, 718.0, 842.0, 1000.0])
    func gridFillsTheWidthExactly(width: Double) {
        for density in DockDensity.allCases {
            for scale in [0.8, 1, 1.25] {
                let m = DockGridMetrics.fit(width: width, density: density, scale: scale)
                let used = Double(m.columns) * m.cellWidth + Double(m.columns - 1) * m.spacing
                #expect(abs(used - width) < 0.001, "density \(density) scale \(scale)")
                #expect(m.iconSize >= DockGridMetrics.minimumIcon)
                #expect(m.iconSize <= m.cellWidth)   // never clipped
                #expect(m.columns >= 3)
            }
        }
    }

    @Test func landscapeShowsMoreColumnsAndDensityChangesSize() {
        let portrait = DockGridMetrics.fit(width: 370, density: .regular)
        let landscape = DockGridMetrics.fit(width: 718, density: .regular)
        #expect(landscape.columns > portrait.columns)
        #expect(DockGridMetrics.fit(width: 370, density: .compact).columns > DockGridMetrics.fit(width: 370, density: .large).columns)
        #expect(DockGridMetrics.fit(width: 370, density: .large).iconSize > DockGridMetrics.fit(width: 370, density: .compact).iconSize)
    }

    @Test func tinyWidthStillDrawsWholeIcons() {
        let m = DockGridMetrics.fit(width: 100, density: .large)
        #expect(m.columns == 1)
        #expect(m.iconSize >= DockGridMetrics.minimumIcon && m.iconSize <= m.cellWidth)
    }
}

@Suite struct DockArrangementTests {
    private func app(_ id: String, recent: Bool = false, running: Bool = false) -> DockApp {
        DockApp(bundleID: id, name: id.capitalized, running: running, active: false, iconKey: "\(id)@1", recent: recent)
    }

    @Test func userOrderThenMacOrderAndRecentApart() {
        let mac = [app("finder"), app("safari"), app("word", running: true), app("notes", recent: true)]
        var a = DockArrangement()
        #expect(a.arrange(mac).apps.map(\.bundleID) == ["finder", "safari", "word"])
        #expect(a.arrange(mac).recent.map(\.bundleID) == ["notes"])
        #expect(a.arrange(mac, showRecent: false).recent.isEmpty)
        a.move("word", before: "finder", shown: ["finder", "safari", "word"])
        #expect(a.arrange(mac).apps.map(\.bundleID) == ["word", "finder", "safari"])
        // A new Mac app that the user never ordered goes after the ordered ones.
        #expect(a.arrange(mac + [app("maps")]).apps.map(\.bundleID) == ["word", "finder", "safari", "maps"])
        a.move("finder", before: nil, shown: ["word", "finder", "safari", "maps"])
        #expect(a.order == ["word", "safari", "maps", "finder"])
    }

    @Test func hiddenAppsDisappearAndComeBack() {
        let mac = [app("finder"), app("safari")]
        var a = DockArrangement()
        a.hide("safari")
        #expect(a.arrange(mac).apps.map(\.bundleID) == ["finder"])
        a.unhide("safari")
        #expect(a.arrange(mac).apps.count == 2)
    }

    @Test func keptAppsStayWhenTheMacStopsListingThem() {
        var a = DockArrangement()
        a.setKept(app("word", running: true), true)
        #expect(a.isKept("word"))
        let arranged = a.arrange([app("finder")])
        #expect(arranged.apps.map(\.bundleID) == ["finder", "word"])
        #expect(arranged.apps.last?.running == false)
        #expect(arranged.apps.last?.iconKey == "word@1")
        // Listed only as recent: shown in the grid, not twice.
        let both = a.arrange([app("finder"), app("word", recent: true)])
        #expect(both.apps.map(\.bundleID) == ["finder", "word"])
        #expect(both.recent.isEmpty)
        a.hide("word")
        #expect(!a.isKept("word"))
        a.setKept(app("word"), false)
        #expect(a.arrange([app("finder")]).apps.map(\.bundleID) == ["finder"])
    }

    @Test func searchRanksPrefixThenWordThenAnywhere() {
        let apps = [DockApp(bundleID: "1", name: "Microsoft Word", running: false, active: false),
                    DockApp(bundleID: "2", name: "WordPad", running: false, active: false),
                    DockApp(bundleID: "3", name: "Passwords", running: false, active: false),
                    DockApp(bundleID: "4", name: "Café Notes", running: false, active: false),
                    DockApp(bundleID: "2", name: "WordPad dup", running: false, active: false)]
        #expect(DockArrangement.search("word", in: apps).map(\.bundleID) == ["2", "1", "3"])
        #expect(DockArrangement.search("cafe", in: apps).map(\.bundleID) == ["4"])
        #expect(DockArrangement.search("  ", in: apps).isEmpty)
        #expect(DockArrangement.search("zzz", in: apps).isEmpty)
    }

    @Test func arrangementSurvivesCoding() throws {
        var a = DockArrangement()
        a.move("x", before: nil, shown: ["y"])
        a.hide("z")
        a.setKept(app("k"), true)
        let back = try JSONDecoder().decode(DockArrangement.self, from: JSONEncoder().encode(a))
        #expect(back == a)
    }
}

@Suite struct DeckEditingTests {
    private func layout() -> (DeckLayout, folder: UUID, inner: UUID, top: [UUID]) {
        let inner = DeckButton(title: "In", symbol: "a", action: .typeText("x"))
        let folder = DeckButton(title: "F", symbol: "folder", action: .folder, children: [inner])
        let a = DeckButton(title: "A", symbol: "a", action: .system(.mute))
        let b = DeckButton(title: "B", symbol: "b", action: .system(.playPause))
        let l = DeckLayout(pages: [DeckPage(title: "Main", buttons: [a, folder, b]),
                                   DeckPage(title: "Safari", appBundleIDs: ["com.apple.Safari"], buttons: [])])
        return (l, folder.id, inner.id, [a.id, folder.id, b.id])
    }

    @Test func addMoveReplaceRemove() {
        var (l, folder, inner, top) = layout()
        let c = DeckButton(title: "C", symbol: "c", action: .system(.lockScreen))
        l.add(c, page: 0)
        #expect(l.buttons(page: 0).map(\.title) == ["A", "F", "B", "C"])
        l.move(id: c.id, to: 0, page: 0)
        #expect(l.buttons(page: 0).map(\.title) == ["C", "A", "F", "B"])
        l.move(id: top[0], to: 99, page: 0)
        #expect(l.buttons(page: 0).map(\.title) == ["C", "F", "B", "A"])

        let d = DeckButton(title: "D", symbol: "d", action: .typeText("d"))
        l.add(d, page: 0, folder: folder)
        #expect(l.buttons(page: 0, folder: folder).map(\.title) == ["In", "D"])
        l.move(id: d.id, to: 0, page: 0, folder: folder)
        #expect(l.buttons(page: 0, folder: folder).map(\.title) == ["D", "In"])

        var renamed = l.button(id: inner)!
        renamed.title = "Inner"
        l.replace(renamed)
        #expect(l.button(id: inner)?.title == "Inner")

        l.remove(id: inner)
        #expect(l.button(id: inner) == nil)
        l.remove(id: folder)
        #expect(l.button(id: d.id) == nil)   // a folder goes with its contents
        #expect(l.buttons(page: 0).map(\.title) == ["C", "B", "A"])
        // Out-of-range pages are ignored.
        l.add(c, page: 9)
        #expect(l.allButtons.count == 3)
    }

    @Test func pagesFollowTheFrontmostApp() {
        var (l, _, _, _) = layout()
        #expect(l.pageIndex(forFrontmost: "com.apple.Safari") == 1)
        #expect(l.pageIndex(forFrontmost: "com.apple.Notes") == nil)
        #expect(l.pageIndex(forFrontmost: nil) == nil)
        l.movePage(from: 1, to: 0)
        #expect(l.pages.map(\.title) == ["Safari", "Main"])
        #expect(l.pageIndex(forFrontmost: "com.apple.Safari") == 0)
    }
}

@Suite struct DeckPackingTests {
    @Test func mixedSizesPackWithoutOverlapAndFillGaps() {
        // regular, large, regular, regular, wide on 4 columns
        let spans = [(1, 1), (2, 2), (1, 1), (1, 1), (2, 1)].map { (columns: $0.0, rows: $0.1) }
        let (cells, rows) = DeckGridPacking.place(spans, columns: 4)
        #expect(cells[0] == .init(column: 0, row: 0, columns: 1, rows: 1))
        #expect(cells[1] == .init(column: 1, row: 0, columns: 2, rows: 2))
        #expect(cells[2] == .init(column: 3, row: 0, columns: 1, rows: 1))
        #expect(cells[3] == .init(column: 0, row: 1, columns: 1, rows: 1))   // fills the gap beside the large tile
        #expect(cells[4] == .init(column: 0, row: 2, columns: 2, rows: 1))
        #expect(rows == 3)
        var seen = Set<String>()
        for c in cells { for x in c.column..<(c.column + c.columns) { for y in c.row..<(c.row + c.rows) {
            #expect(seen.insert("\(x),\(y)").inserted)
        } } }
    }

    @Test func spansShrinkToNarrowGrids() {
        let (cells, rows) = DeckGridPacking.place([(columns: 2, rows: 2)], columns: 1)
        #expect(cells == [.init(column: 0, row: 0, columns: 1, rows: 2)])
        #expect(rows == 2)
        #expect(DeckGridPacking.place([], columns: 3).rows == 0)
        #expect(DeckButtonSize.large.span == (2, 2))
    }
}

@Suite struct ModeListLayoutTests {
    let known = ModeListLayout.defaultOrder

    @Test func defaultIsFiveModes() {
        #expect(ModeListLayout().visible(known: known) == ["trackpad", "keys", "media", "dock", "actions"])
    }

    @Test func splittingBringsTheFourToolsBackAndNothingIsLost() {
        let split = ModeListLayout(splitActions: true)
        #expect(split.visible(known: known) == ["trackpad", "keys", "media", "dock", "deck", "macros", "clipboard", "present"])
        #expect(split.replacement(for: "actions", known: known) == "deck")
        #expect(ModeListLayout().replacement(for: "present", known: known) == "actions")
        #expect(ModeListLayout().replacement(for: "dock", known: known) == "dock")
    }

    @Test func hidingAndReorderingButTrackpadStays() {
        var l = ModeListLayout(hidden: ["media", "trackpad", "remote"])
        l.move("actions", before: "keys")
        #expect(l.visible(known: known) == ["trackpad", "actions", "keys", "dock"])
        #expect(l.replacement(for: "media", known: known) == "trackpad")
        l.move("trackpad", before: nil)
        #expect(l.visible(known: known).last == "trackpad")
    }

    @Test func newModesAppearAndUnknownOnesGo() {
        let l = ModeListLayout(order: ["keys", "gone"])
        #expect(l.visible(known: ["trackpad", "keys"]) == ["keys", "trackpad"])
    }
}

@Suite struct DeckGridFitTests {
    private func spans(_ n: Int, wide: Int = 0) -> [(columns: Int, rows: Int)] {
        Array(repeating: (columns: 2, rows: 1), count: wide) + Array(repeating: (columns: 1, rows: 1), count: n)
    }

    @Test func fewButtonsGetBigTilesThatStillFit() {
        let f = DeckGridFit.best(spans: spans(4), width: 370, height: 600)
        #expect(f.fits && f.columns == 3)
        #expect(f.cellWidth <= 120)
    }

    @Test func theMacPageFillsPortraitAndLandscapeWithoutScrolling() {
        for (w, h) in [(370.0, 600.0), (718.0, 300.0)] {
            let f = DeckGridFit.best(spans: spans(19, wide: 1), width: w, height: h)
            #expect(f.fits)
            let rows = DeckGridPacking.place(spans(19, wide: 1), columns: f.columns).rows
            let used = Double(rows) * f.cellHeight + Double(rows - 1) * 8
            #expect(used <= h + 0.001)
            #expect(h - used < f.cellHeight)            // no empty row's worth left over
            #expect(f.cellHeight <= f.cellWidth * 1.25 + 0.001)
        }
    }

    @Test func tooManyFallsBackToScrollingAtTheChosenSize() {
        let f = DeckGridFit.best(spans: spans(200), width: 370, height: 500, fallbackCell: 76)
        #expect(!f.fits)
        #expect(f.cellWidth == f.cellHeight)
        #expect(f.columns == 4)
    }
}
