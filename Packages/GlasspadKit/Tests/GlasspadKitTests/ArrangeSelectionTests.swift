import CoreGraphics
import Foundation
import Testing
@testable import GlasspadKit

@Suite struct ArrangeSelectionTests {
    static let laptop = MacDisplay(id: 1, name: "Built-in Retina Display", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                   visibleFrame: CGRect(x: 0, y: 38, width: 1512, height: 874), isMain: true, isBuiltIn: true)
    static let studio = MacDisplay(id: 2, name: "Studio Display", frame: CGRect(x: 1512, y: -458, width: 2560, height: 1440),
                                   visibleFrame: CGRect(x: 1512, y: -434, width: 2560, height: 1416), isMain: false)
    static let every = WindowArrangement.allCases.map(\.rawValue)

    /// Safari in front on the Studio Display, Notes behind it on the laptop, then Mail and Music.
    static func state(displays: [MacDisplay] = [laptop, studio], arrangements: [String]? = every) -> DisplaysState {
        DisplaysState(displays: displays, windows: [
            MacWindow(id: 11, bundleID: "com.apple.Safari", appName: "Safari", title: "Apple", frame: CGRect(x: 1600, y: -400, width: 1200, height: 900)),
            MacWindow(id: 12, bundleID: "com.apple.Notes", appName: "Notes", title: "Ideas", frame: CGRect(x: 100, y: 100, width: 700, height: 600)),
            MacWindow(id: 13, bundleID: "com.apple.mail", appName: "Mail", title: "Inbox", frame: CGRect(x: 200, y: 120, width: 900, height: 600)),
            MacWindow(id: 14, bundleID: "com.apple.Music", appName: "Music", title: "Music", frame: CGRect(x: 300, y: 140, width: 900, height: 600)),
        ], tileMargin: 8, arrangements: arrangements)
    }

    // MARK: Starting

    @Test func startsWithTheFrontWindowFirstAndTheOnesBehindItOnItsDisplay() {
        let s = Self.state()
        #expect(s.defaultArrangement(.leftAndRight) == ArrangeSelection(.leftAndRight, windows: [11, 12], display: 2))
        #expect(s.defaultArrangement(.quarters) == ArrangeSelection(.quarters, windows: [11, 12, 13, 14], display: 2))
        // From Displays' Split With: the held window first, the front other ones after it.
        #expect(s.defaultArrangement(.leftAndRight, first: 12) == ArrangeSelection(.leftAndRight, windows: [12, 11], display: 1))
        var one = s
        one.windows = [s.windows[0]]
        #expect(one.defaultArrangement(.leftAndRight) == nil)
    }

    @Test func quartersTakeThreeWindowsAndLeaveTheLastQuarterEmpty() throws {
        var s = Self.state()
        s.windows.removeLast()
        let q = try #require(s.defaultArrangement(.quarters))
        #expect(q.windows == [11, 12, 13])
        // Only a window not placed yet goes into the empty quarter, and there is none.
        #expect(s.arrangeChoices(for: 3, in: q).isEmpty)
        #expect(s.choosing(12, place: 3, in: q) == q)
        s.windows.removeLast()
        #expect(s.defaultArrangement(.quarters) == nil)
        #expect(s.defaultArrangement(.topAndBottom) != nil)
    }

    @Test func anEmptyQuarterTakesAWindowNotPlacedYet() {
        let s = Self.state()
        let q = ArrangeSelection(.quarters, windows: [11, 12, 13], display: 2)
        #expect(s.arrangeChoices(for: 3, in: q).map(\.id) == [14])
        #expect(s.choosing(14, place: 3, in: q).windows == [11, 12, 13, 14])
    }

    @Test func theSheetOffersWhatTheMacTakes() {
        #expect(Self.state().sheetArrangements == [.leftAndRight, .topAndBottom, .quarters, .fullScreen])
        // A Mac from before arrangements: left and right only, the old way.
        #expect(Self.state(arrangements: nil).sheetArrangements == [.leftAndRight])
        // A newer Mac's arrangement this build does not know is skipped.
        #expect(Self.state(arrangements: ["leftAndRight", "spiral"]).sheetArrangements == [.leftAndRight])
    }

    // MARK: Choosing

    @Test func choosingAPlacedWindowSwapsAndTheDisplayFollowsTheFirstOne() {
        let s = Self.state()
        let start = s.defaultArrangement(.leftAndRight)!
        // Mail first: it is on the laptop, so the arrangement goes there.
        #expect(s.choosing(13, place: 0, in: start) == ArrangeSelection(.leftAndRight, windows: [13, 12], display: 1))
        // Notes is already second: picking it first swaps them, and the display follows Notes.
        #expect(s.choosing(12, place: 0, in: start) == ArrangeSelection(.leftAndRight, windows: [12, 11], display: 1))
        #expect(s.choosing(11, place: 1, in: start).windows == start.rotated.windows)
        // A new second window leaves the display alone.
        #expect(s.choosing(13, place: 1, in: start) == ArrangeSelection(.leftAndRight, windows: [11, 13], display: 2))
        // A display the person picked stays.
        var picked = start
        picked.display = 2
        picked.displayPicked = true
        #expect(s.choosing(13, place: 0, in: picked).display == 2)
        // Out of range or gone: nothing changes.
        #expect(s.choosing(13, place: 2, in: start) == start)
        #expect(s.choosing(99, place: 0, in: start) == start)
    }

    @Test func rotatingSwapsTwoAndTurnsQuartersClockwise() {
        let two = ArrangeSelection(.topAndBottom, windows: [1, 2], display: 1)
        #expect(two.rotated.windows == [2, 1] && two.rotated.rotated == two)
        // Top left, top right, bottom left, bottom right: each moves one quarter clockwise.
        let four = ArrangeSelection(.quarters, windows: [1, 2, 3, 4], display: 1)
        #expect(four.rotated.windows == [3, 1, 4, 2])
        #expect(four.rotated.rotated.rotated.rotated == four)
        // Three: around the three quarters that have a window.
        let three = ArrangeSelection(.quarters, windows: [1, 2, 3], display: 1)
        #expect(three.rotated.windows == [3, 1, 2])
    }

    @Test func switchingKeepsTheChosenWindowsAndFillsFromTheFront() throws {
        let s = Self.state()
        let start = ArrangeSelection(.leftAndRight, windows: [13, 11], display: 1)
        let q = try #require(s.switching(start, to: .quarters))
        #expect(q.windows == [13, 11, 12, 14] && q.display == 1)
        #expect(s.switching(q, to: .topAndBottom)?.windows == [13, 11])
        var two = s
        two.windows = Array(s.windows.prefix(2))
        #expect(two.switching(ArrangeSelection(.leftAndRight, windows: [11, 12], display: 2), to: .quarters) == nil)
    }

    @Test func theListOfferedKeepsTheChosenWindow() {
        var s = Self.state()
        for i in 0..<20 {
            s.windows.append(MacWindow(id: UInt32(100 + i), bundleID: nil, appName: "App \(i)", frame: CGRect(x: 10, y: 50, width: 400, height: 300)))
        }
        let sel = ArrangeSelection(.leftAndRight, windows: [11, 119], display: 1)
        #expect(s.arrangeChoices(for: 0, in: sel).count == DisplaysState.arrangeChoices)
        let far = s.arrangeChoices(for: 1, in: sel)
        #expect(far.count == DisplaysState.arrangeChoices + 1 && far.last?.id == 119)
    }

    @Test func aWindowThatClosedIsReplacedAndAGoneDisplayFallsBack() {
        var s = Self.state()
        let picked = ArrangeSelection(.leftAndRight, windows: [11, 12], display: 1, displayPicked: true)
        s.windows.removeAll { $0.id == 12 }
        #expect(s.refreshed(picked) == ArrangeSelection(.leftAndRight, windows: [11, 13], display: 1, displayPicked: true))
        // The laptop's display went away (lid closed): back to Safari's.
        var docked = Self.state(displays: [Self.studio])
        docked.windows[1].frame.origin = CGPoint(x: 1600, y: -300)
        #expect(docked.refreshed(picked) == ArrangeSelection(.leftAndRight, windows: [11, 12], display: 2))
        // Quarters down to three windows keeps going; down to two it cannot.
        var q = Self.state()
        let four = ArrangeSelection(.quarters, windows: [11, 12, 13, 14], display: 2)
        q.windows.removeAll { $0.id == 13 }
        #expect(q.refreshed(four)?.windows == [11, 12, 14])
        q.windows.removeAll { $0.id == 14 }
        #expect(q.refreshed(four) == nil)
        s.windows = [s.windows[0]]
        #expect(s.refreshed(picked) == nil)
    }

    // MARK: Sending

    @Test func aMacThatTakesArrangementsGetsOneCommand() throws {
        let s = Self.state()
        let q = ArrangeSelection(.quarters, windows: [12, 11, 14, 13], display: 1)
        let sent = try #require(s.commands(for: q))
        #expect(sent.count == 1 && sent[0].window == 12)
        #expect(sent[0].command == .arrange(.quarters, windows: [12, 11, 14, 13], display: 1))
        // The phone's picture meanwhile: each window in its quarter of the laptop, in front in order.
        let preview = s.applying(sent[0].command, window: sent[0].window)
        let frames = try #require(s.arrangeFrames(for: q))
        #expect([12, 11, 14, 13].map { preview.window($0)?.frame } == frames)
        #expect(preview.windows.map(\.id) == [12, 11, 14, 13])
        // Gone, twice, too many or too few: nothing to send.
        #expect(s.commands(for: ArrangeSelection(.leftAndRight, windows: [11, 11], display: 2)) == nil)
        #expect(s.commands(for: ArrangeSelection(.leftAndRight, windows: [11, 99], display: 2)) == nil)
        #expect(s.commands(for: ArrangeSelection(.leftAndRight, windows: [11, 12], display: 9)) == nil)
        #expect(s.commands(for: ArrangeSelection(.leftAndRight, windows: [11, 12, 13], display: 2)) == nil)
        #expect(s.commands(for: ArrangeSelection(.quarters, windows: [11, 12], display: 2)) == nil)
    }

    @Test func anOlderMacSplitsTheOldWay() {
        let s = Self.state(arrangements: nil)
        // Both on the Studio Display (Safari's): one command, the Mac brings Notes over.
        #expect(s.commands(for: ArrangeSelection(.leftAndRight, windows: [11, 12], display: 2))?.map(\.command) == [.split(with: 12)])
        // On the laptop instead: Safari moves there first.
        let laptop = s.commands(for: ArrangeSelection(.leftAndRight, windows: [11, 12], display: 1, displayPicked: true))
        #expect(laptop?.map(\.window) == [11, 11])
        #expect(laptop?.map(\.command) == [.move(display: 1, origin: nil), .split(with: 12)])
        var preview = s
        for c in laptop ?? [] { preview = preview.applying(c.command, window: c.window) }
        let halves = DisplayGeometry.split(in: Self.laptop.visibleFrame, gap: 8)
        #expect(preview.window(11)?.frame == halves.left && preview.window(12)?.frame == halves.right)
        // Anything else it cannot do.
        #expect(s.commands(for: ArrangeSelection(.topAndBottom, windows: [11, 12], display: 2)) == nil)
        // A Mac that lists arrangements but not this one is not sent the old split either.
        #expect(Self.state(arrangements: ["quarters"]).commands(for: ArrangeSelection(.leftAndRight, windows: [11, 12], display: 2)) == nil)
    }

    @Test func thePictureShowsEveryPlace() throws {
        let s = Self.state()
        let v = Self.laptop.visibleFrame
        let lr = try #require(s.arrangeFrames(for: ArrangeSelection(.leftAndRight, windows: [11, 12], display: 1)))
        #expect(lr == [DisplayGeometry.split(in: v, gap: 8).left, DisplayGeometry.split(in: v, gap: 8).right])
        let three = try #require(s.arrangeFrames(for: ArrangeSelection(.quarters, windows: [11, 12, 13], display: 1)))
        #expect(three.count == 4)
        // Split View: the whole display, no menu bar and no margins.
        let full = try #require(s.arrangeFrames(for: ArrangeSelection(.fullScreen, windows: [11, 12], display: 1)))
        #expect(full == [CGRect(x: 0, y: 0, width: 756, height: 982), CGRect(x: 756, y: 0, width: 756, height: 982)])
    }

    @Test func theSummaryNamesTheAppsAndTheDisplay() {
        let s = Self.state()
        #expect(s.arrangeSummary(ArrangeSelection(.leftAndRight, windows: [11, 12], display: 2)) == "Safari and Notes, side by side on Studio Display.")
        #expect(s.arrangeSummary(ArrangeSelection(.topAndBottom, windows: [11, 12], display: 2)) == "Safari and Notes, one above the other on Studio Display.")
        #expect(s.arrangeSummary(ArrangeSelection(.quarters, windows: [11, 12, 13], display: 2)) == "Safari, Notes and Mail, in quarters on Studio Display.")
        var one = Self.state(displays: [Self.laptop])
        #expect(one.arrangeSummary(ArrangeSelection(.leftAndRight, windows: [12, 13], display: 1)) == "Notes and Mail, side by side.")
        #expect(one.arrangeSummary(ArrangeSelection(.fullScreen, windows: [12, 13], display: 1)) == "Notes and Mail, side by side in full screen.")
        one.windows[2].appName = "Notes"
        #expect(one.arrangeSummary(ArrangeSelection(.leftAndRight, windows: [12, 13], display: 1)) == "Two Notes windows, side by side.")
    }

    @Test func buttonTitlesSayWhatWillHappen() {
        #expect(WindowArrangement.leftAndRight.actionTitle == "Split")
        #expect(WindowArrangement.topAndBottom.actionTitle == "Split Top & Bottom")
        #expect(WindowArrangement.quarters.actionTitle == "Arrange in Quarters")
        #expect(WindowArrangement.fullScreen.actionTitle == "Split in Full Screen")
        #expect(WindowArrangement.quarters.placeName(3) == "Bottom right quarter")
    }
}

@Suite struct WindowArrangementTests {
    static let visible = CGRect(x: 0, y: 38, width: 1512, height: 874)

    @Test func halvesMatchTheTilesAndQuartersSplitThem() {
        let v = Self.visible
        for gap: CGFloat in [0, 8] {
            #expect(DisplayGeometry.frame(of: .left, in: v, gap: gap) == DisplayGeometry.tile(.leftHalf, window: .zero, in: v, gap: gap))
            #expect(DisplayGeometry.frame(of: .right, in: v, gap: gap) == DisplayGeometry.tile(.rightHalf, window: .zero, in: v, gap: gap))
            #expect(DisplayGeometry.frame(of: .top, in: v, gap: gap) == DisplayGeometry.tile(.topHalf, window: .zero, in: v, gap: gap))
            #expect(DisplayGeometry.frame(of: .bottom, in: v, gap: gap) == DisplayGeometry.tile(.bottomHalf, window: .zero, in: v, gap: gap))
        }
        // With margins: 8 points around and between, whole points.
        let tl = DisplayGeometry.frame(of: .topLeft, in: v, gap: 8), br = DisplayGeometry.frame(of: .bottomRight, in: v, gap: 8)
        #expect(tl == CGRect(x: 8, y: 46, width: 744, height: 425))
        #expect(br.minX - tl.maxX == 8 && br.minY - tl.maxY == 8)
        #expect(br.maxX == v.maxX - 8 && br.maxY == v.maxY - 8)
        let tr = DisplayGeometry.frame(of: .topRight, in: v, gap: 8), bl = DisplayGeometry.frame(of: .bottomLeft, in: v, gap: 8)
        #expect(tr.minX == br.minX && tr.minY == tl.minY && bl.minX == tl.minX && bl.minY == br.minY)
    }

    @Test func eachArrangementPutsItsFirstWindowWhereItsNameSays() {
        #expect(WindowArrangement.rightAndLeft.slots == [.right, .left])
        #expect(WindowArrangement.bottomAndTop.slots == [.bottom, .top])
        #expect(WindowArrangement.leftAndQuarters.slots == [.left, .topRight, .bottomRight])
        #expect(WindowArrangement.bottomAndQuarters.slots == [.bottom, .topLeft, .topRight])
        #expect(WindowArrangement.quarters.slots == [.topLeft, .topRight, .bottomLeft, .bottomRight])
        #expect(WindowArrangement.allCases.allSatisfy { $0.minimumWindows <= $0.slots.count && $0.minimumWindows >= 2 })
        #expect(WindowArrangement.quarters.minimumWindows == 3)
    }
}
