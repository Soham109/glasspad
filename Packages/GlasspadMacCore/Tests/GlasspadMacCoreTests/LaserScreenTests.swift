import CoreGraphics
import Testing
@testable import GlasspadMacCore

@Suite struct LaserScreenTests {
    // A MacBook (built in, main) with a projector to its right, in Core Graphics coordinates.
    let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let projector = CGRect(x: 1512, y: -100, width: 1920, height: 1080)
    var both: [(frame: CGRect, builtIn: Bool)] { [(laptop, true), (projector, false)] }

    @Test func oneDisplay() {
        let picked = LaserScreenPicker.pick(frontWindows: [laptop], screens: [(laptop, true)], main: laptop)
        #expect(picked == laptop)
        #expect(LaserScreenPicker.pick(frontWindows: [], screens: [(laptop, true)], main: laptop) == laptop)
    }

    @Test func slidesOnTheProjectorWithPresenterViewOnTheLaptop() {
        // Either order of windows: the external display wins.
        #expect(LaserScreenPicker.pick(frontWindows: [laptop, projector], screens: both, main: laptop) == projector)
        #expect(LaserScreenPicker.pick(frontWindows: [projector, laptop], screens: both, main: laptop) == projector)
    }

    @Test func slidesOnlyOnTheLaptop() {
        #expect(LaserScreenPicker.pick(frontWindows: [laptop], screens: both, main: laptop) == laptop)
    }

    @Test func externalMainDisplayAndSlidesOnTheLaptop() {
        let screens: [(frame: CGRect, builtIn: Bool)] = [(projector, false), (laptop, true)]
        #expect(LaserScreenPicker.pick(frontWindows: [laptop], screens: screens, main: projector) == laptop)
    }

    @Test func noFrontWindowsKeepsTheMainDisplay() {
        #expect(LaserScreenPicker.pick(frontWindows: [], screens: both, main: laptop) == laptop)
        // A window somewhere off every display.
        let lost = CGRect(x: -5_000, y: -5_000, width: 400, height: 300)
        #expect(LaserScreenPicker.pick(frontWindows: [lost], screens: both, main: laptop) == laptop)
    }

    @Test func aWindowAPointShortStillCounts() {
        let nearly = projector.insetBy(dx: 1, dy: 1)
        let big = CGRect(x: 0, y: 30, width: 1512, height: 900)   // larger than nothing on the laptop
        #expect(LaserScreenPicker.pick(frontWindows: [big, nearly], screens: both, main: laptop) == projector)
    }

    @Test func aWindowTenPointsShortDoesNotCover() {
        let short = projector.insetBy(dx: 10, dy: 10)
        #expect(!LaserScreenPicker.covers(short, projector))
        #expect(LaserScreenPicker.covers(projector.insetBy(dx: 1, dy: 1), projector))
        // Not covering, so the largest window decides: the laptop's is larger.
        let laptopWindow = CGRect(x: 0, y: 25, width: 1512, height: 957)
        let small = CGRect(x: 1600, y: 0, width: 800, height: 600)
        #expect(LaserScreenPicker.pick(frontWindows: [laptopWindow, small], screens: both, main: laptop) == laptop)
        #expect(LaserScreenPicker.pick(frontWindows: [short], screens: both, main: laptop) == projector)
    }

    @Test func largestWindowGoesToTheDisplayHoldingMostOfIt() {
        // A window straddling both, mostly on the projector.
        let straddling = CGRect(x: 1200, y: 100, width: 1200, height: 700)
        #expect(LaserScreenPicker.pick(frontWindows: [straddling], screens: both, main: laptop) == projector)
    }

    @Test func appKitFrameFlipsAroundTheMainDisplay() {
        // The projector sits 100 pt higher than the laptop's top edge.
        let frame = LaserScreenPicker.appKitFrame(projector, mainHeight: laptop.height)
        #expect(frame == CGRect(x: 1512, y: 982 - 980, width: 1920, height: 1080))
        #expect(LaserScreenPicker.appKitFrame(laptop, mainHeight: laptop.height) == CGRect(x: 0, y: 0, width: 1512, height: 982))
    }

    @Test func screenPointOnADisplayLeftOfAndBelowTheMainOne() {
        let left = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)    // AppKit frame
        #expect(PresentMode.screenPoint(x: 0, y: 0, screen: left) == CGPoint(x: -1920, y: 0))
        #expect(PresentMode.screenPoint(x: 1, y: 1, screen: left) == CGPoint(x: 0, y: -1080))
        #expect(PresentMode.screenPoint(x: 1, y: 0, screen: left) == CGPoint(x: 0, y: 0))
        #expect(PresentMode.screenPoint(x: 0, y: 1, screen: left) == CGPoint(x: -1920, y: -1080))
    }
}
