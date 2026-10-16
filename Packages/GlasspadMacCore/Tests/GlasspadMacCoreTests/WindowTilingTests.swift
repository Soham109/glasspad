import CoreGraphics
import GlasspadKit
import Testing
@testable import GlasspadMacCore

@Suite struct WindowTilingTests {
    /// A 1440 x 900 main display with a 25 pt menu bar and the Dock hidden (Cocoa coordinates).
    let mainFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let mainVisible = CGRect(x: 0, y: 0, width: 1440, height: 875)

    private func screen(_ frame: CGRect, _ visible: CGRect) -> TilingScreen {
        TilingScreen(frame: WindowTiling.quartz(frame, mainHeight: 900), visible: WindowTiling.quartz(visible, mainHeight: 900))
    }

    @Test func menuBarIsLeftOutInQuartzCoordinates() {
        let s = screen(mainFrame, mainVisible)
        #expect(s.frame == CGRect(x: 0, y: 0, width: 1440, height: 900))
        #expect(s.visible == CGRect(x: 0, y: 25, width: 1440, height: 875))
    }

    @Test func halvesFillTheVisibleArea() {
        let v = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let w = CGRect(x: 100, y: 100, width: 500, height: 400)
        #expect(WindowTiling.frame(.left, window: w, in: v) == CGRect(x: 0, y: 25, width: 720, height: 875))
        #expect(WindowTiling.frame(.right, window: w, in: v) == CGRect(x: 720, y: 25, width: 720, height: 875))
        #expect(WindowTiling.frame(.top, window: w, in: v) == CGRect(x: 0, y: 25, width: 1440, height: 438))
        #expect(WindowTiling.frame(.bottom, window: w, in: v) == CGRect(x: 0, y: 463, width: 1440, height: 437))
        #expect(WindowTiling.frame(.fill, window: w, in: v) == v)
        #expect(WindowTiling.frame(.center, window: w, in: v) == CGRect(x: 470, y: 263, width: 500, height: 400))
    }

    @Test func dockOnTheLeftShiftsTheLeftHalf() {
        // Dock on the left, 70 pt wide: Cocoa's visible frame starts at x 70.
        let s = screen(mainFrame, CGRect(x: 70, y: 0, width: 1370, height: 875))
        #expect(s.visible == CGRect(x: 70, y: 25, width: 1370, height: 875))
        #expect(WindowTiling.frame(.left, window: .zero, in: s.visible) == CGRect(x: 70, y: 25, width: 685, height: 875))
        #expect(WindowTiling.frame(.right, window: .zero, in: s.visible) == CGRect(x: 755, y: 25, width: 685, height: 875))
    }

    @Test func dockAtTheBottomShortensTheHalves() {
        // Dock at the bottom, 80 pt tall.
        let s = screen(mainFrame, CGRect(x: 0, y: 80, width: 1440, height: 795))
        #expect(s.visible == CGRect(x: 0, y: 25, width: 1440, height: 795))
        let left = WindowTiling.frame(.left, window: .zero, in: s.visible)
        #expect(left.maxY == 820 && left.minY == 25)
    }

    @Test func marginsLeaveAGapAroundAndBetween() {
        let v = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let g = WindowTiling.margin
        let (left, right) = WindowTiling.split(in: v, gap: g)
        #expect(left.minX == g && left.minY == 25 + g)
        #expect(right.maxX == 1440 - g && left.maxY == 900 - g)
        #expect(right.minX - left.maxX >= g)
        #expect(abs(left.width - right.width) <= 1)
    }

    @Test func centreNeverSpillsOffTheScreen() {
        let v = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let huge = CGRect(x: -50, y: 0, width: 3000, height: 2000)
        #expect(WindowTiling.frame(.center, window: huge, in: v) == v)
    }

    @Test func secondDisplayToTheRightAndLowerConverts() {
        // 1920 x 1080 to the right, its bottom 180 pt below the main display's bottom.
        let s = screen(CGRect(x: 1440, y: -180, width: 1920, height: 1080), CGRect(x: 1440, y: -180, width: 1920, height: 1080))
        #expect(s.frame == CGRect(x: 1440, y: 0, width: 1920, height: 1080))
        #expect(WindowTiling.frame(.left, window: .zero, in: s.visible) == CGRect(x: 1440, y: 0, width: 960, height: 1080))
    }

    @Test func displayAboveAndToTheLeftHaveNegativeCoordinates() {
        let above = screen(CGRect(x: 0, y: 900, width: 1920, height: 1080), CGRect(x: 0, y: 900, width: 1920, height: 1055))
        #expect(above.frame == CGRect(x: 0, y: -1080, width: 1920, height: 1080))
        #expect(above.visible == CGRect(x: 0, y: -1055, width: 1920, height: 1055))
        let left = screen(CGRect(x: -1280, y: 0, width: 1280, height: 800), CGRect(x: -1280, y: 0, width: 1280, height: 800))
        #expect(WindowTiling.frame(.right, window: .zero, in: left.visible) == CGRect(x: -640, y: 100, width: 640, height: 800))
    }

    @Test func windowBelongsToTheScreenShowingMostOfIt() {
        let screens = [screen(mainFrame, mainVisible),
                       screen(CGRect(x: 1440, y: -180, width: 1920, height: 1080), CGRect(x: 1440, y: -180, width: 1920, height: 1080))]
        #expect(WindowTiling.screenIndex(for: CGRect(x: 1300, y: 100, width: 600, height: 400), in: screens) == 1)
        #expect(WindowTiling.screenIndex(for: CGRect(x: 1000, y: 100, width: 600, height: 400), in: screens) == 0)
        // Off every screen: the nearest one.
        #expect(WindowTiling.screenIndex(for: CGRect(x: 5000, y: 100, width: 300, height: 300), in: screens) == 1)
        #expect(WindowTiling.screenIndex(for: .zero, in: []) == nil)
    }

    @Test func nextDisplayGoesLeftToRightAndWraps() {
        let main = screen(mainFrame, mainVisible)
        let right = screen(CGRect(x: 1440, y: 0, width: 1920, height: 1080), CGRect(x: 1440, y: 0, width: 1920, height: 1080))
        let left = screen(CGRect(x: -1280, y: 0, width: 1280, height: 800), CGRect(x: -1280, y: 0, width: 1280, height: 800))
        let screens = [main, right, left]
        #expect(WindowTiling.nextScreenIndex(after: 2, in: screens) == 0)
        #expect(WindowTiling.nextScreenIndex(after: 0, in: screens) == 1)
        #expect(WindowTiling.nextScreenIndex(after: 1, in: screens) == 2)
        #expect(WindowTiling.nextScreenIndex(after: 0, in: [main]) == nil)
    }

    @Test func movingKeepsTheWindowsShareOfTheScreen() {
        let from = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let to = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let leftHalf = WindowTiling.frame(.left, window: .zero, in: from)
        #expect(WindowTiling.moved(leftHalf, from: from, to: to) == CGRect(x: 1440, y: 0, width: 960, height: 1080))
        let small = CGRect(x: 360, y: 243, width: 720, height: 437)
        let m = WindowTiling.moved(small, from: from, to: to)
        #expect(m.minX >= to.minX && m.maxX <= to.maxX && m.minY >= to.minY && m.maxY <= to.maxY)
        #expect(abs(m.midX - to.midX) <= 1)
    }

    @Test func placementsComeFromTheirButtons() {
        #expect(WindowPlacement(.windowLeft) == .left)
        #expect(WindowPlacement(.windowCenter) == .center)
        #expect(WindowPlacement(.windowSplit) == nil)
        #expect(WindowPlacement(.mute) == nil)
    }

    @Test func moveAndResizeMenuItemsAreFoundByTheirShortcut() {
        let fnControl = 4 | 8
        typealias S = MoveResizeMenu.Shortcut
        #expect(MoveResizeMenu.matches(S(glyph: 0x64, modifiers: fnControl), .left))
        #expect(MoveResizeMenu.matches(S(virtualKey: 124, modifiers: fnControl), .right))
        #expect(MoveResizeMenu.matches(S(char: "\u{F700}", modifiers: fnControl), .top))
        #expect(MoveResizeMenu.matches(S(glyph: 0x6A, modifiers: fnControl), .bottom))
        #expect(MoveResizeMenu.matches(S(char: "f", modifiers: fnControl), .fill))
        #expect(MoveResizeMenu.matches(S(char: "C", modifiers: fnControl), .center))
        // Command C (Copy) and control shift left are other things.
        #expect(!MoveResizeMenu.matches(S(char: "C", modifiers: 0), .center))
        #expect(!MoveResizeMenu.matches(S(glyph: 0x64, modifiers: fnControl | 1), .left))
        #expect(!MoveResizeMenu.matches(S(glyph: 0x65, modifiers: fnControl), .left))
    }

    @Test func doNotDisturbSwitchIsFoundByIdentifier() {
        #expect(ControlCenterFocus.isDoNotDisturbSwitch("focus-mode-activity-com.apple.donotdisturb.mode.default"))
        #expect(!ControlCenterFocus.isDoNotDisturbSwitch("focus-mode-activity-com.apple.focus.work"))
        #expect(!ControlCenterFocus.isDoNotDisturbSwitch(nil))
        #expect(ControlCenterFocus.isFocusTile("controlcenter-focus-modes"))
    }
}
