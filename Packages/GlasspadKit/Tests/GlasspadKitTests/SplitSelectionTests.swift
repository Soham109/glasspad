import CoreGraphics
import Foundation
import Testing
@testable import GlasspadKit

@Suite struct SplitSelectionTests {
    static let laptop = MacDisplay(id: 1, name: "Built-in Retina Display", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                   visibleFrame: CGRect(x: 0, y: 38, width: 1512, height: 874), isMain: true, isBuiltIn: true)
    static let studio = MacDisplay(id: 2, name: "Studio Display", frame: CGRect(x: 1512, y: -458, width: 2560, height: 1440),
                                   visibleFrame: CGRect(x: 1512, y: -434, width: 2560, height: 1416), isMain: false)

    /// Safari in front on the Studio Display, Notes behind it on the laptop, Mail behind that.
    static func state(displays: [MacDisplay] = [laptop, studio]) -> DisplaysState {
        DisplaysState(displays: displays, windows: [
            MacWindow(id: 11, bundleID: "com.apple.Safari", appName: "Safari", title: "Apple", frame: CGRect(x: 1600, y: -400, width: 1200, height: 900)),
            MacWindow(id: 12, bundleID: "com.apple.Notes", appName: "Notes", title: "Ideas", frame: CGRect(x: 100, y: 100, width: 700, height: 600)),
            MacWindow(id: 13, bundleID: "com.apple.mail", appName: "Mail", title: "Inbox", frame: CGRect(x: 200, y: 120, width: 900, height: 600)),
        ], tileMargin: 8)
    }

    @Test func startsWithTheFrontWindowLeftTheOneBehindRightOnItsDisplay() {
        let s = Self.state()
        #expect(s.defaultSplit() == SplitSelection(left: 11, right: 12, display: 2))
        // From Displays' Split With: the held window on the left, the front other one right.
        #expect(s.defaultSplit(left: 12) == SplitSelection(left: 12, right: 11, display: 1))
        var one = s
        one.windows = [s.windows[0]]
        #expect(one.defaultSplit() == nil)
    }

    @Test func choosingTheOtherSidesWindowSwapsAndTheDisplayFollowsTheLeftOne() {
        let s = Self.state()
        let start = s.defaultSplit()!
        // Mail on the left: it is on the laptop, so the split goes there.
        let mail = s.choosing(13, left: true, in: start)
        #expect(mail == SplitSelection(left: 13, right: 12, display: 1))
        // Notes is already on the right: picking it for the left swaps them, on the same display.
        #expect(s.choosing(12, left: true, in: start) == SplitSelection(left: 12, right: 11, display: 2))
        #expect(s.choosing(11, left: false, in: start) == start.swapped)
        // A new right window leaves the display alone.
        #expect(s.choosing(13, left: false, in: start) == SplitSelection(left: 11, right: 13, display: 2))
        #expect(start.swapped.swapped == start)
        // A display the person picked stays.
        var picked = start
        picked.display = 2
        picked.displayPicked = true
        #expect(s.choosing(13, left: true, in: picked).display == 2)
    }

    @Test func aLeftWindowOnAnotherDisplayGoesOverFirstThenTheSplit() {
        let s = Self.state()
        // Both on the Studio Display (Safari's): one command, the Mac brings Notes over.
        #expect(s.commands(for: SplitSelection(left: 11, right: 12, display: 2))?.map(\.command) == [.split(with: 12)])
        // On the laptop instead: Safari moves there first.
        let laptop = s.commands(for: SplitSelection(left: 11, right: 12, display: 1, displayPicked: true))
        #expect(laptop?.map(\.window) == [11, 11])
        #expect(laptop?.map(\.command) == [.move(display: 1, origin: nil), .split(with: 12)])
        // The preview the phone shows meanwhile ends with both on the laptop's halves.
        var preview = s
        for c in laptop ?? [] { preview = preview.applying(c.command, window: c.window) }
        let halves = DisplayGeometry.split(in: Self.laptop.visibleFrame, gap: 8)
        #expect(preview.window(11)?.frame == halves.left && preview.window(12)?.frame == halves.right)
        #expect(preview.windows.prefix(2).map(\.id) == [11, 12])
        #expect(s.splitFrames(for: SplitSelection(left: 11, right: 12, display: 1)).map { [$0.left, $0.right] } == [halves.left, halves.right])
        // Gone or the same window twice: nothing to send.
        #expect(s.commands(for: SplitSelection(left: 11, right: 11, display: 2)) == nil)
        #expect(s.commands(for: SplitSelection(left: 11, right: 99, display: 2)) == nil)
        #expect(s.commands(for: SplitSelection(left: 11, right: 12, display: 9)) == nil)
    }

    @Test func aWindowThatClosedIsReplacedAndAGoneDisplayFallsBack() {
        var s = Self.state()
        let picked = SplitSelection(left: 11, right: 12, display: 1, displayPicked: true)
        s.windows.removeAll { $0.id == 12 }
        #expect(s.refreshed(picked) == SplitSelection(left: 11, right: 13, display: 1, displayPicked: true))
        // The laptop's display went away (lid closed): back to Safari's.
        var docked = Self.state(displays: [Self.studio])
        docked.windows[1].frame.origin = CGPoint(x: 1600, y: -300)
        #expect(docked.refreshed(picked) == SplitSelection(left: 11, right: 12, display: 2))
        s.windows = [s.windows[0]]
        #expect(s.refreshed(picked) == nil)
    }

    @Test func theSummaryNamesBothAppsAndTheDisplay() {
        let s = Self.state()
        #expect(s.splitSummary(SplitSelection(left: 11, right: 12, display: 2)) == "Safari and Notes, side by side on Studio Display.")
        var one = Self.state(displays: [Self.laptop])
        #expect(one.splitSummary(SplitSelection(left: 12, right: 13, display: 1)) == "Notes and Mail, side by side.")
        one.windows[2].appName = "Notes"
        #expect(one.splitSummary(SplitSelection(left: 12, right: 13, display: 1)) == "Two Notes windows, side by side.")
    }

    @Test func theListOfferedKeepsTheChosenWindow() {
        var s = Self.state()
        for i in 0..<20 {
            s.windows.append(MacWindow(id: UInt32(100 + i), bundleID: nil, appName: "App \(i)", frame: CGRect(x: 10, y: 50, width: 400, height: 300)))
        }
        #expect(s.splitChoices(keeping: 11).count == DisplaysState.splitChoices)
        let far = s.splitChoices(keeping: 119)
        #expect(far.count == DisplaysState.splitChoices + 1 && far.last?.id == 119)
    }
}
