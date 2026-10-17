import CoreGraphics
import Foundation
import GlasspadKit
import Testing
@testable import GlasspadMacCore

/// Every arrangement on fake windows that behave as apps do: margins, sizes they will not go
/// below, displays at either side or above, Return to Previous Size, and Split View's steps.
@Suite @MainActor struct ArrangeTests {
    nonisolated static let laptop = SplitScreenTests.laptop
    nonisolated static let right = SplitScreenTests.right
    nonisolated static let left = SplitScreenTests.left
    nonisolated static let above = SplitScreenTests.above
    nonisolated static let tiled = WindowArrangement.allCases.filter { $0 != .fullScreen }

    private func arranger(_ screens: [TilingScreen], history: WindowHistory? = nil) -> WindowArranger {
        WindowArranger(displays: screens.map(\.frame), history: history) { _ in }
    }

    private func windows(_ n: Int, on screens: [TilingScreen], at origin: CGPoint = CGPoint(x: 100, y: 100)) -> [FakeWindow] {
        let apps = ["Safari", "Notes", "Mail", "Music"]
        return (0..<n).map { i in
            FakeWindow(apps[i], CGRect(x: origin.x + CGFloat(i) * 30, y: origin.y + CGFloat(i) * 20, width: 600, height: 400),
                       displays: screens.map(\.visible), id: UInt32(10 + i))
        }
    }

    // MARK: Layout

    @Test(arguments: ArrangeTests.tiled)
    func everyArrangementLandsInItsPlacesWithMargins(_ arrangement: WindowArrangement) async {
        for gap: CGFloat in [0, 8] {
            let screens = [Self.laptop]
            let ws = windows(arrangement.slots.count, on: screens)
            let failure = await arranger(screens).arrange(ws, arrangement, in: Self.laptop.visible, gap: gap, displayName: "")
            #expect(failure == nil, "\(arrangement)")
            let places = arrangement.slots.map { DisplayGeometry.frame(of: $0, in: Self.laptop.visible, gap: gap) }
            #expect(ws.map(\.actual) == places, "\(arrangement) gap \(gap)")
        }
    }

    @Test func withoutMinimumsTheLayoutIsTheEvenOne() throws {
        let v = Self.laptop.visible
        for a in Self.tiled {
            let even = a.slots.map { DisplayGeometry.frame(of: $0, in: v, gap: 8) }
            #expect(ArrangementLayout.frames(a, in: v, gap: 8, minimums: Array(repeating: .zero, count: a.slots.count)) == even)
        }
        // Margins all round and between, as macOS leaves them.
        let q = try #require(ArrangementLayout.frames(.quarters, in: v, gap: 8, minimums: Array(repeating: .zero, count: 4)))
        #expect(q[0].minX == v.minX + 8 && q[0].minY == v.minY + 8 && q[3].maxX == v.maxX - 8 && q[3].maxY == v.maxY - 8)
        #expect(q[1].minX - q[0].maxX == 8 && q[2].minY - q[0].maxY == 8)
    }

    @Test func quartersWithThreeWindowsLeaveTheLastQuarterEmpty() async {
        let screens = [Self.laptop]
        let ws = windows(3, on: screens)
        #expect(await arranger(screens).arrange(ws, .quarters, in: Self.laptop.visible, gap: 8, displayName: "") == nil)
        let v = Self.laptop.visible
        #expect(ws.map(\.actual) == [.topLeft, .topRight, .bottomLeft].map { DisplayGeometry.frame(of: $0, in: v, gap: 8) })
        // Too few or too many for it.
        #expect(await arranger(screens).arrange(Array(ws.prefix(1)), .quarters, in: v, gap: 8, displayName: "") == .noSecondWindow)
        #expect(await arranger(screens).arrange(windows(3, on: screens), .leftAndRight, in: v, gap: 8, displayName: "") == .noSecondWindow)
    }

    // MARK: Minimum sizes

    @Test func aWindowThatWillNotShrinkKeepsItsColumnAndTheOthersGetTheRest() async {
        let screens = [Self.laptop]
        let ws = windows(4, on: screens)
        ws[0].minimumWidth = 900
        let v = Self.laptop.visible
        #expect(await arranger(screens).arrange(ws, .quarters, in: v, gap: 8, displayName: "") == nil)
        // The left column is as wide as Safari needs, the right one takes the rest, margins kept.
        #expect(ws[0].actual.width == 900 && ws[2].actual.width == 900 && ws[0].actual.minX == v.minX + 8)
        #expect(ws[1].actual.minX - ws[0].actual.maxX == 8 && ws[1].actual.maxX == v.maxX - 8)
        #expect(ws[3].actual.minX == ws[1].actual.minX && ws[3].actual.width == ws[1].actual.width)
    }

    @Test func topAndBottomGivesATallWindowItsHeight() async {
        let screens = [Self.laptop]
        let ws = windows(2, on: screens)
        ws[1].minimumHeight = 600
        let v = Self.laptop.visible
        #expect(await arranger(screens).arrange(ws, .topAndBottom, in: v, gap: 8, displayName: "") == nil)
        #expect(ws[1].actual.height == 600 && ws[1].actual.maxY == v.maxY - 8)
        #expect(ws[1].actual.minY - ws[0].actual.maxY == 8 && ws[0].actual.minY == v.minY + 8)
    }

    @Test func windowsThatCannotFitSaySoByName() async {
        let screens = [Self.laptop]
        let v = Self.laptop.visible
        let q = windows(4, on: screens)
        q[0].minimumWidth = 900
        q[1].minimumWidth = 800
        let quarters = await arranger(screens).arrange(q, .quarters, in: v, gap: 8, displayName: "Built-in Retina Display")
        #expect(quarters == .tooBigForQuarters(["Safari", "Notes"], display: "Built-in Retina Display"))
        #expect(quarters?.message == "Safari and Notes cannot both fit in quarters on Built-in Retina Display. Try Left & Right.")
        #expect(WindowFailure.tooBigForQuarters(["Xcode"], display: "Studio Display").message
                == "Xcode cannot be made small enough for a quarter of Studio Display. Try Left & Right.")
        #expect(WindowFailure.tooBigForQuarters(["Xcode", "Logic Pro", "Final Cut Pro"], display: "Studio Display").message
                == "Xcode, Logic Pro and Final Cut Pro cannot all fit in quarters on Studio Display. Try Left & Right.")
        let t = windows(2, on: screens)
        t[0].minimumHeight = 500
        t[1].minimumHeight = 500
        let stacked = await arranger(screens).arrange(t, .topAndBottom, in: v, gap: 8, displayName: "Built-in Retina Display")
        #expect(stacked == .bothTooTall("Safari", "Notes", display: "Built-in Retina Display"))
        #expect(stacked?.message == "Safari and Notes cannot both fit on Built-in Retina Display, one above the other. Try Left & Right.")
        #expect(WindowFailure.tooTall("Xcode").message == "Xcode cannot be made short enough for Top & Bottom. Try Left & Right.")
        // Right & Left names the windows by side, as Left & Right does.
        let r = windows(2, on: screens)
        r[0].minimumWidth = 820
        r[1].minimumWidth = 820
        #expect(await arranger(screens).arrange(r, .rightAndLeft, in: v, gap: 8, displayName: "Built-in Retina Display")
                == .bothTooWide("Notes", "Safari", display: "Built-in Retina Display"))
    }

    // MARK: Displays

    @Test(arguments: [("right", ArrangeTests.right), ("left", ArrangeTests.left), ("above", ArrangeTests.above)])
    func windowsFromTheLaptopMoveOverFirstThenAreSized(_ place: String, _ monitor: TilingScreen) async {
        let screens = [Self.laptop, monitor]
        let ws = windows(4, on: screens)
        #expect(await arranger(screens).arrange(ws, .quarters, in: monitor.visible, gap: 8, displayName: monitor.name) == nil, "\(place)")
        let places = WindowArrangement.quarters.slots.map { DisplayGeometry.frame(of: $0, in: monitor.visible, gap: 8) }
        #expect(ws.map(\.actual) == places, "\(place)")
        for (w, p) in zip(ws, places) { #expect(w.log.first == "position \(Int(p.minX)),\(Int(p.minY))", "\(place)") }
    }

    @Test func aOneTimesDisplayBesideTheLaptopUsesWholePoints() async {
        let hd = TilingScreen(frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
                              visible: CGRect(x: 1512, y: 0, width: 1920, height: 1080), name: "HD Display")
        let screens = [Self.laptop, hd]
        let ws = windows(3, on: screens)
        #expect(await arranger(screens).arrange(ws, .leftAndQuarters, in: hd.visible, gap: 8, displayName: hd.name) == nil)
        for w in ws { #expect(w.actual == w.actual.integral && hd.visible.contains(w.actual)) }
        #expect(ws[0].actual.height > ws[1].actual.height)
    }

    @Test func aFullScreenWindowLeavesFullScreenFirst() async {
        let screens = [Self.laptop]
        let ws = windows(4, on: screens)
        ws[2].fullScreen = true
        #expect(await arranger(screens).arrange(ws, .quarters, in: Self.laptop.visible, gap: 8, displayName: "") == nil)
        #expect(ws[2].log.first == "exit full screen")
    }

    // MARK: Return to Previous Size

    @Test func returnToPreviousSizePutsTheWindowBackOnce() async {
        let screens = [Self.laptop, Self.right]
        let history = WindowHistory()
        let a = arranger(screens, history: history)
        let ws = windows(2, on: screens)
        let before = ws.map(\.actual)
        #expect(await a.arrange(ws, .topAndBottom, in: Self.right.visible, gap: 8, displayName: "") == nil)
        #expect(ws[0].actual != before[0])
        #expect(await a.returnToPreviousSize(ws[0]) == nil)
        #expect(ws[0].actual == before[0])
        // Once: then there is nothing to go back to.
        #expect(await a.returnToPreviousSize(ws[0]) == .noPreviousSize)
        #expect(WindowFailure.noPreviousSize.message == "This window has no previous size to return to.")
        // A single tile is remembered too, from where the window was just before it.
        let moved = ws[1].actual
        _ = await a.place(ws[1], to: DisplayGeometry.frame(of: .topLeft, in: Self.laptop.visible, gap: 8))
        #expect(await a.returnToPreviousSize(ws[1]) == nil && ws[1].actual == moved)
        // A window without an id cannot be remembered.
        let anonymous = FakeWindow("Finder", CGRect(x: 10, y: 50, width: 300, height: 300), displays: screens.map(\.visible))
        _ = await a.place(anonymous, to: DisplayGeometry.frame(of: .left, in: Self.laptop.visible))
        #expect(await a.returnToPreviousSize(anonymous) == .noPreviousSize)
    }

    @Test func aPreviousPlaceOnADisplayThatWentAwayIsNotUsed() async {
        let history = WindowHistory()
        let w = FakeWindow("Pages", CGRect(x: 2000, y: -300, width: 800, height: 600), displays: [Self.laptop.visible], id: 7)
        history.remember(w)
        _ = await arranger([Self.laptop], history: history).place(w, to: DisplayGeometry.frame(of: .left, in: Self.laptop.visible))
        history.remember(7, CGRect(x: 2000, y: -300, width: 800, height: 600))
        let failure = await arranger([Self.laptop], history: history).returnToPreviousSize(w)
        #expect(failure == .previousDisplayGone && history.previous(7) == nil)
        #expect(failure?.message == "This window's previous place is on a display that is not connected.")
    }

    @Test func theHistoryKeepsTheNewestWindows() {
        let h = WindowHistory()
        for i in 0..<(WindowHistory.limit + 5) { h.remember(UInt32(i), CGRect(x: i, y: 0, width: 10, height: 10)) }
        #expect(h.previous(0) == nil && h.previous(UInt32(WindowHistory.limit + 4)) != nil)
    }

    // MARK: macOS's own Arrange

    @Test func macOSsOwnItemOnlyWhenEveryWindowIsAlreadyThereInOrder() {
        #expect(ArrangementLayout.nativeFits(.leftAndRight, windowDisplays: [0, 0], target: 0, frontOrder: [1, 2, 3], windows: [1, 2]))
        // One on another display, the wrong order, other windows in between: Glasspad does it.
        #expect(!ArrangementLayout.nativeFits(.leftAndRight, windowDisplays: [0, 1], target: 0, frontOrder: [1, 2], windows: [1, 2]))
        #expect(!ArrangementLayout.nativeFits(.leftAndRight, windowDisplays: [0, 0], target: 0, frontOrder: [2, 1], windows: [1, 2]))
        #expect(!ArrangementLayout.nativeFits(.leftAndRight, windowDisplays: [0, 0], target: 0, frontOrder: [1, 3, 2], windows: [1, 2]))
        // Quarters takes four; Split View is not an Arrange item.
        #expect(!ArrangementLayout.nativeFits(.quarters, windowDisplays: [0, 0, 0], target: 0, frontOrder: [1, 2, 3], windows: [1, 2, 3]))
        #expect(ArrangementLayout.nativeFits(.quarters, windowDisplays: [0, 0, 0, 0], target: 0, frontOrder: [1, 2, 3, 4], windows: [1, 2, 3, 4]))
        #expect(!ArrangementLayout.nativeFits(.fullScreen, windowDisplays: [0, 0], target: 0, frontOrder: [1, 2], windows: [1, 2]))
    }

    @Test func aNativeArrangementCountsOnlyWithEachWindowInItsPlace() {
        let v = Self.laptop.visible
        for a in Self.tiled {
            // macOS's own margins may differ from Glasspad's.
            for gap: CGFloat in [0, 8, 12] {
                #expect(ArrangementLayout.looksArranged(a, frames: a.slots.map { DisplayGeometry.frame(of: $0, in: v, gap: gap) }, in: v))
            }
        }
        let q = WindowArrangement.quarters.slots.map { DisplayGeometry.frame(of: $0, in: v, gap: 8) }
        #expect(!ArrangementLayout.looksArranged(.quarters, frames: [q[1], q[0], q[2], q[3]], in: v))
        #expect(!ArrangementLayout.looksArranged(.quarters, frames: Array(q.prefix(3)) + [CGRect(x: 900, y: 500, width: 200, height: 200)], in: v))
        #expect(!ArrangementLayout.looksArranged(.topAndBottom, frames: [q[0], q[2]], in: v))
    }

    // MARK: Stage Manager

    @Test func stageManagerLeavesRoomForItsStrip() {
        let v = Self.laptop.visible
        #expect(StageManager.tilingArea(v, enabled: false, recentAppsHidden: false, dockOnLeft: false) == v)
        #expect(StageManager.tilingArea(v, enabled: true, recentAppsHidden: true, dockOnLeft: false) == v)
        let on = StageManager.tilingArea(v, enabled: true, recentAppsHidden: false, dockOnLeft: false)
        #expect(on.minX == v.minX + StageManager.stripWidth && on.maxX == v.maxX && on.height == v.height)
        // With the Dock on the left the strip moves to the right.
        let dockLeft = StageManager.tilingArea(v, enabled: true, recentAppsHidden: false, dockOnLeft: true)
        #expect(dockLeft.minX == v.minX && dockLeft.maxX == v.maxX - StageManager.stripWidth)
        // Halves then share what is left.
        let halves = DisplayGeometry.split(in: on, gap: 8)
        #expect(halves.left.minX == on.minX + 8 && halves.right.maxX == v.maxX - 8)
    }

    // MARK: Split View

    @MainActor final class FakeSplitView: SplitViewSteps {
        var tiles = true
        var picks = true
        var log: [String] = []
        func tileLeft(_ w: MovableWindow) -> Bool {
            log.append("left \(w.appName)")
            guard tiles, let f = w as? FakeWindow else { return false }
            f.fullScreen = true
            f.actual = CGRect(x: 0, y: 0, width: 756, height: 982)
            return true
        }
        func pickPartner(_ w: MovableWindow) -> Bool {
            log.append("partner \(w.appName)")
            guard picks, let f = w as? FakeWindow else { return false }
            f.fullScreen = true
            f.actual = CGRect(x: 756, y: 0, width: 756, height: 982)
            return true
        }
    }

    @Test func splitViewTilesTheFirstLeftThenPicksTheSecond() async {
        let screens = [Self.laptop]
        let ws = windows(2, on: screens)
        let steps = FakeSplitView()
        let split = FullScreenSplit(steps: steps, arranger: arranger(screens))
        #expect(await split.fullScreenSplit(left: ws[0], right: ws[1]) == nil)
        #expect(steps.log == ["left Safari", "partner Notes"])
        #expect(ws[0].isFullScreen && ws[1].isFullScreen)
    }

    @Test func aSplitViewThatDoesNotFinishLeavesBothWindowsUsable() async {
        let screens = [Self.laptop]
        let ws = windows(2, on: screens)
        let steps = FakeSplitView()
        steps.picks = false
        let failure = await FullScreenSplit(steps: steps, arranger: arranger(screens)).fullScreenSplit(left: ws[0], right: ws[1])
        #expect(failure == .splitViewUnfinished)
        #expect(failure?.message == "Could not finish Split View. Pick the second window on your Mac.")
        // The first window came back out of full screen rather than waiting alone.
        #expect(ws[0].log.contains("exit full screen") && !ws[0].isFullScreen)
        // An app without Full-Screen Tile: nothing changed.
        let none = FakeSplitView()
        none.tiles = false
        let other = windows(2, on: screens)
        #expect(await FullScreenSplit(steps: none, arranger: arranger(screens)).fullScreenSplit(left: other[0], right: other[1])
                == .noSplitView("Safari"))
        #expect(none.log == ["left Safari"])
        #expect(WindowFailure.noSplitView("Safari").message == "Safari cannot tile this window in full screen. Try Left & Right.")
    }
}

/// The Window menu as macOS 26 builds it (read from Terminal and Finder on this Mac, British
/// English), and as an app without action names would show it.
struct MoveResizeMenuTests {
    typealias S = MoveResizeMenu.Shortcut
    typealias E = MoveResizeMenu.Entry

    static func key(_ vk: Int, _ mods: Int) -> S { S(virtualKey: vk, modifiers: mods) }

    /// Move & Resize's items, with or without their actions.
    static func moveResize(ids: Bool) -> [E] {
        func e(_ title: String, _ s: S? = nil, _ id: String) -> E { E(title, s, id: ids ? id : nil) }
        return [
            E("Halves"), e("Left", key(123, 28), "_zoomLeft:"), e("Right", key(124, 28), "_zoomRight:"),
            e("Top", key(126, 28), "_zoomTop:"), e("Bottom", key(125, 28), "_zoomBottom:"), E(""),
            E("Quarters"), e("Top Left", nil, "_zoomTopLeft:"), e("Top Right", nil, "_zoomTopRight:"),
            e("Bottom Left", nil, "_zoomBottomLeft:"), e("Bottom Right", nil, "_zoomBottomRight:"), E(""),
            E("Arrange"), e("Left & Right", key(123, 29), "_zoomLeftAndRight:"), e("Left & Quarters", key(123, 31), "_zoomLeftThreeUp:"),
            e("Right & Left", key(124, 29), "_zoomRightAndLeft:"), e("Right & Quarters", key(124, 31), "_zoomRightThreeUp:"),
            e("Top & Bottom", key(126, 29), "_zoomTopAndBottom:"), e("Top & Quarters", key(126, 31), "_zoomTopThreeUp:"),
            e("Bottom & Top", key(125, 29), "_zoomBottomAndTop:"), e("Bottom & Quarters", key(125, 31), "_zoomBottomThreeUp:"),
            e("Quarters", nil, "_zoomQuarters:"), E(""),
            e("Return to Previous Size", S(char: "R", modifiers: 28), "_zoomUntile:"),
        ]
    }

    static func window(ids: Bool) -> [E] {
        [E("Minimise", S(char: "M", modifiers: 0), id: ids ? "performMiniaturize:" : nil), E("Zoom", id: ids ? "_zoom:" : nil),
         E("Fill", S(char: "F", modifiers: 28), id: ids ? "_zoomFill:" : nil), E("Centre", S(char: "C", modifiers: 28), id: ids ? "_zoomCenter:" : nil),
         E(""), E("Move & Resize", submenu: true), E("Full-Screen Tile", submenu: true), E("")]
    }

    @Test(arguments: [true, false])
    func everyItemIsFoundAndNoneIsMistaken(_ ids: Bool) throws {
        let items = Self.window(ids: ids) + Self.moveResize(ids: ids)
        func title(_ i: Int?) -> String? { i.map { items[$0].title } }
        #expect(MoveResizeMenu.isTilingMenu(Self.moveResize(ids: ids)))
        #expect(!MoveResizeMenu.isTilingMenu([E("New Window", S(char: "N", modifiers: 0)), E("Zoom", id: "_zoom:")]))
        let placements: [(WindowPlacement, String)] = [(.left, "Left"), (.right, "Right"), (.top, "Top"), (.bottom, "Bottom"),
                                                       (.fill, "Fill"), (.center, "Centre"), (.topLeft, "Top Left"),
                                                       (.topRight, "Top Right"), (.bottomLeft, "Bottom Left"), (.bottomRight, "Bottom Right")]
        for (p, t) in placements { #expect(title(MoveResizeMenu.index(p, in: items)) == t, "\(p) ids \(ids)") }
        for a in WindowArrangement.allCases where a != .fullScreen {
            #expect(title(MoveResizeMenu.index(a, in: items)) == a.title, "\(a) ids \(ids)")
        }
        #expect(MoveResizeMenu.index(.fullScreen, in: items) == nil)
        #expect(title(MoveResizeMenu.returnIndex(in: items)) == "Return to Previous Size")
    }

    @Test func shortcutsNeverConfuseNeighbours() {
        #expect(MoveResizeMenu.arrangement(Self.key(123, 29)) == .leftAndRight)
        #expect(MoveResizeMenu.arrangement(Self.key(123, 31)) == .leftAndQuarters)
        #expect(MoveResizeMenu.arrangement(Self.key(125, 29)) == .bottomAndTop)
        #expect(MoveResizeMenu.arrangement(Self.key(126, 31)) == .topAndQuarters)
        // The plain halves, a command key, or no control: no arrangement.
        #expect(MoveResizeMenu.arrangement(Self.key(123, 28)) == nil)
        #expect(MoveResizeMenu.arrangement(Self.key(123, 1 | 4)) == nil)
        #expect(MoveResizeMenu.arrangement(S(char: "R", modifiers: 29)) == nil)
        #expect(!MoveResizeMenu.matches(Self.key(123, 31), .left))
        #expect(MoveResizeMenu.isReturnToPreviousSize(S(char: "r", modifiers: 28)))
        #expect(!MoveResizeMenu.isReturnToPreviousSize(S(char: "R", modifiers: 0)))
        #expect(!MoveResizeMenu.isReturnToPreviousSize(S(char: "R", modifiers: 29)))
    }

    @Test func itemsWithoutShortcutsAreFoundOnlyWhereMacOSPutsThem() {
        var items = Self.moveResize(ids: false)
        // An extra item among the quarters, or a missing separator: not trusted.
        items.insert(E("Something Else"), at: 9)
        #expect(MoveResizeMenu.quarterIndex(.topLeft, in: items) == nil)
        var arrange = Self.moveResize(ids: false)
        arrange.insert(E("More"), at: 22)
        #expect(MoveResizeMenu.quartersArrangeIndex(in: arrange) == nil)
        // An app's own item with a Move & Resize action name wins over any shortcut look-alike.
        let named = [E("Tidy", Self.key(123, 28), id: "tidyLeft:"), E("Left", nil, id: "_zoomLeft:")]
        #expect(MoveResizeMenu.index(.left, in: named) == 1)
        // With action names present, a missing one is missing (never guessed by shortcut).
        let partial = [E("Left", Self.key(123, 28), id: "_zoomLeft:"), E("Left & Right", Self.key(123, 29))]
        #expect(MoveResizeMenu.index(.leftAndRight, in: partial) == nil)
    }

    @Test func fullScreenTileOffersLeftAndRightOnlyBeforeAWindowIsTiled() {
        let window = Self.window(ids: true)
        let free = [E("Left of Screen"), E("Right of Screen")]
        #expect(MoveResizeMenu.fullScreenTileIndices(windowMenu: window, moveResize: 5, tile: free)! == (0, 1))
        // Once tiled it offers other things.
        let tiled = [E("Replace Tiled Window", id: "_changeWindowTileLocation:"), E("Move Window to Desktop"), E("Make Window Full Screen")]
        #expect(MoveResizeMenu.fullScreenTileIndices(windowMenu: window, moveResize: 5, tile: tiled) == nil)
        // Not straight after Move & Resize: not it.
        #expect(MoveResizeMenu.fullScreenTileIndices(windowMenu: window, moveResize: 3, tile: free) == nil)
    }
}
