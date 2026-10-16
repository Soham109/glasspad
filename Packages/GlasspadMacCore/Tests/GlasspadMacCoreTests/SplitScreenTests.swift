import CoreGraphics
import Foundation
import GlasspadKit
import Testing
@testable import GlasspadMacCore

/// A window that behaves the way apps do: it is never sized past the display it is on, it may
/// have a minimum width, it may land a move a few reads later, it may refuse.
@MainActor
final class FakeWindow: MovableWindow {
    let appName: String
    /// Where the app really has it.
    var actual: CGRect
    /// What reads show while a move has not landed yet.
    private var shown: CGRect
    private var readsLeft = 0
    var minimumWidth: CGFloat = 0
    var maximumWidth: CGFloat = .infinity
    /// Reads before a change shows.
    var lag = 0
    var fullScreen = false
    var isFullScreen: Bool {
        guard fullScreen else { return false }
        if fullScreenReadsLeft > 0 {
            fullScreenReadsLeft -= 1
            if fullScreenReadsLeft == 0 { fullScreen = false }
            return true
        }
        return true
    }
    /// Reads that still say full screen after being asked to leave (the animation).
    var fullScreenReadsLeft = 0
    var staysFullScreen = false
    var refuses = false
    var closed = false
    /// Visible areas: a new size never goes past the one the window is on.
    let displays: [CGRect]
    private(set) var log: [String] = []

    init(_ app: String, _ frame: CGRect, displays: [CGRect]) {
        appName = app
        actual = frame
        shown = frame
        self.displays = displays
    }

    func exitFullScreen() -> Bool {
        log.append("exit full screen")
        if staysFullScreen { return false }
        fullScreenReadsLeft = 3
        return true
    }

    var frame: CGRect? {
        if closed { return nil }
        if readsLeft > 0 {
            readsLeft -= 1
            return shown
        }
        shown = actual
        return actual
    }

    func setPosition(_ origin: CGPoint) -> Bool {
        guard !refuses, !closed else { return false }
        log.append("position \(Int(origin.x)),\(Int(origin.y))")
        actual.origin = origin
        changed()
        return true
    }

    func setSize(_ size: CGSize) -> Bool {
        guard !refuses, !closed else { return false }
        log.append("size \(Int(size.width))x\(Int(size.height))")
        let on = DisplayGeometry.displayIndex(for: actual, in: displays).map { displays[$0] } ?? .infinite
        actual.size = CGSize(width: min(max(size.width, minimumWidth), maximumWidth, on.width), height: min(size.height, on.height))
        changed()
        return true
    }

    private func changed() {
        if readsLeft == 0 { readsLeft = lag }
    }
}

@Suite @MainActor struct SplitScreenTests {
    /// A 14 inch MacBook Pro: 1512 x 982, menu bar 38 pt.
    nonisolated static let laptop = TilingScreen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                     visible: CGRect(x: 0, y: 38, width: 1512, height: 944), name: "Built-in Retina Display")

    /// A Studio Display at 2560 x 1440 placed against the laptop, its visible area without a menu bar.
    nonisolated static func studio(_ origin: CGPoint) -> TilingScreen {
        let f = CGRect(origin: origin, size: CGSize(width: 2560, height: 1440))
        return TilingScreen(frame: f, visible: f, name: "Studio Display")
    }

    nonisolated static let right = studio(CGPoint(x: 1512, y: -458))
    nonisolated static let left = studio(CGPoint(x: -2560, y: -458))
    nonisolated static let above = studio(CGPoint(x: -524, y: -1440))

    private func arranger(_ screens: [TilingScreen], waited: @escaping (TimeInterval) -> Void = { _ in }) -> WindowArranger {
        WindowArranger(displays: screens.map(\.frame), pause: waited)
    }

    // MARK: Choosing

    @Test func frontWindowLeftTheOneBehindRightOnTheFrontWindowsDisplay() throws {
        let windows = [SplitScreen.Candidate(app: "Safari", frame: CGRect(x: 1600, y: -400, width: 1200, height: 900)),
                       SplitScreen.Candidate(app: "Notes", frame: CGRect(x: 100, y: 100, width: 700, height: 600))]
        let choice = try SplitScreen.choose(windows, displays: [Self.laptop.frame, Self.right.frame]).get()
        #expect(choice == SplitScreen.Choice(left: 0, right: 1, display: 1))
    }

    @Test func minimizedWindowsAreSkipped() throws {
        let windows = [SplitScreen.Candidate(app: "Safari", frame: CGRect(x: 100, y: 100, width: 700, height: 600)),
                       SplitScreen.Candidate(app: "Mail", frame: CGRect(x: 200, y: 100, width: 700, height: 600), isMinimized: true),
                       SplitScreen.Candidate(app: "Notes", frame: CGRect(x: 300, y: 100, width: 700, height: 600))]
        #expect(try SplitScreen.choose(windows, displays: [Self.laptop.frame]).get() == SplitScreen.Choice(left: 0, right: 2, display: 0))
        #expect(SplitScreen.choose(Array(windows.prefix(2)), displays: [Self.laptop.frame]) == .failure(.noSecondWindow))
        #expect(SplitScreen.choose([], displays: [Self.laptop.frame]) == .failure(.noWindow))
    }

    @Test func aWindowInFullScreenIsStillChosen() {
        let windows = [SplitScreen.Candidate(app: "Terminal", frame: CGRect(x: 0, y: 0, width: 1512, height: 982), isFullScreen: true),
                       SplitScreen.Candidate(app: "Notes", frame: CGRect(x: 300, y: 100, width: 700, height: 600))]
        #expect(SplitScreen.choose(windows, displays: [Self.laptop.frame]) == .success(SplitScreen.Choice(left: 0, right: 1, display: 0)))
        #expect(WindowFailure.fullScreen("Terminal").message == "Terminal would not leave full screen. Try again in a moment.")
    }

    // MARK: Halves

    @Test func aWindowWiderThanHalfKeepsItsEdgeAndTheOtherGetsTheRest() throws {
        let v = Self.laptop.visible
        let even = try #require(SplitScreen.halves(in: v, gap: 8))
        #expect(even == DisplayGeometry.split(in: v, gap: 8))
        let wide = try #require(SplitScreen.halves(in: v, gap: 8, rightMinimum: 900))
        #expect(wide.right.width == 900 && wide.right.maxX == even.right.maxX)
        #expect(wide.left.minX == even.left.minX && wide.right.minX - wide.left.maxX == 8)
        let wideLeft = try #require(SplitScreen.halves(in: v, gap: 8, leftMinimum: 1000))
        #expect(wideLeft.left.width == 1000 && wideLeft.right.maxX == even.right.maxX && wideLeft.right.minX - wideLeft.left.maxX == 8)
        // Both wider than half, or one wider than the whole display: they cannot share it.
        #expect(SplitScreen.halves(in: v, gap: 8, leftMinimum: 800, rightMinimum: 800) == nil)
        #expect(SplitScreen.halves(in: v, gap: 8, leftMinimum: 1600) == nil)
        #expect(SplitScreen.halves(in: v, gap: 8, leftMinimum: 1000, rightMinimum: 600) == nil)
    }

    // MARK: Moving

    @Test func bothOnOneDisplayLandOnTheirHalves() {
        let screens = [Self.laptop]
        let a = FakeWindow("Safari", CGRect(x: 100, y: 100, width: 700, height: 600), displays: screens.map(\.visible))
        let b = FakeWindow("Notes", CGRect(x: 300, y: 200, width: 500, height: 500), displays: screens.map(\.visible))
        #expect(arranger(screens).split(left: a, right: b, in: Self.laptop.visible, gap: 8, displayName: "Built-in Retina Display") == nil)
        let halves = DisplayGeometry.split(in: Self.laptop.visible, gap: 8)
        #expect(a.actual == halves.left && b.actual == halves.right)
    }

    /// The report: the front window on the monitor, the other on the laptop. The laptop's window
    /// goes over to the monitor first, then gets its size, so the laptop never limits it.
    @Test(arguments: [("right", SplitScreenTests.right), ("left", SplitScreenTests.left), ("above", SplitScreenTests.above)])
    func theWindowOnTheOtherDisplayMovesOverFirstThenIsSized(_ place: String, _ monitor: TilingScreen) {
        let screens = [Self.laptop, monitor]
        let visibles = screens.map(\.visible)
        let front = FakeWindow("Safari", CGRect(x: monitor.visible.minX + 200, y: monitor.visible.minY + 100, width: 1400, height: 1000),
                               displays: visibles)
        let behind = FakeWindow("Notes", CGRect(x: 100, y: 100, width: 1300, height: 800), displays: visibles)
        let failure = arranger(screens).split(left: front, right: behind, in: monitor.visible, gap: 8, displayName: monitor.name)
        #expect(failure == nil, "monitor \(place)")
        let halves = DisplayGeometry.split(in: monitor.visible, gap: 8)
        #expect(front.actual == halves.left, "monitor \(place)")
        #expect(behind.actual == halves.right, "monitor \(place)")
        // Taller than the laptop: only possible because it arrived before it was sized.
        #expect(behind.actual.height > Self.laptop.visible.height)
        #expect(behind.log.first == "position \(Int(halves.right.minX)),\(Int(halves.right.minY))", "monitor \(place)")
    }

    @Test func toTheSmallerDisplayToo() {
        let screens = [Self.laptop, Self.right]
        let visibles = screens.map(\.visible)
        let front = FakeWindow("Safari", CGRect(x: 100, y: 100, width: 900, height: 700), displays: visibles)
        let behind = FakeWindow("Xcode", CGRect(x: 1600, y: -400, width: 2400, height: 1400), displays: visibles)
        #expect(arranger(screens).split(left: front, right: behind, in: Self.laptop.visible, gap: 0, displayName: "Built-in Retina Display") == nil)
        let halves = DisplayGeometry.split(in: Self.laptop.visible)
        #expect(front.actual == halves.left && behind.actual == halves.right)
    }

    /// A 1x 1920 x 1080 display beside a 2x laptop: frames are points either way, whole points.
    @Test func displaysWithDifferentScaleFactorsUsePointsAlike() {
        let hd = TilingScreen(frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), visible: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
                              name: "HD Display")
        let screens = [Self.laptop, hd]
        let front = FakeWindow("Pages", CGRect(x: 1600, y: 100, width: 1000, height: 700), displays: screens.map(\.visible))
        let behind = FakeWindow("Preview", CGRect(x: 10, y: 60, width: 1001, height: 701), displays: screens.map(\.visible))
        #expect(arranger(screens).split(left: front, right: behind, in: hd.visible, gap: 8, displayName: hd.name) == nil)
        let halves = DisplayGeometry.split(in: hd.visible, gap: 8)
        #expect(front.actual == halves.left && behind.actual == halves.right)
        for f in [front.actual, behind.actual] { #expect(f == f.integral) }
    }

    @Test func aWindowWithAMinimumWidthKeepsItAndTheOtherGetsTheRest() {
        let screens = [Self.laptop]
        let a = FakeWindow("Safari", CGRect(x: 100, y: 100, width: 700, height: 600), displays: screens.map(\.visible))
        let b = FakeWindow("Xcode", CGRect(x: 300, y: 200, width: 1000, height: 700), displays: screens.map(\.visible))
        b.minimumWidth = 900
        #expect(arranger(screens).split(left: a, right: b, in: Self.laptop.visible, gap: 8, displayName: "Built-in Retina Display") == nil)
        #expect(b.actual.width == 900 && b.actual.maxX == Self.laptop.visible.maxX - 8)
        #expect(a.actual.minX == 8 && b.actual.minX - a.actual.maxX == 8)
    }

    @Test func twoWindowsTooWideToShareSaySoByName() {
        let screens = [Self.laptop]
        let a = FakeWindow("Xcode", CGRect(x: 100, y: 100, width: 1000, height: 600), displays: screens.map(\.visible))
        let b = FakeWindow("Logic Pro", CGRect(x: 300, y: 200, width: 1000, height: 700), displays: screens.map(\.visible))
        a.minimumWidth = 820
        b.minimumWidth = 820
        let failure = arranger(screens).split(left: a, right: b, in: Self.laptop.visible, gap: 8, displayName: "Built-in Retina Display")
        #expect(failure == .bothTooWide("Xcode", "Logic Pro", display: "Built-in Retina Display"))
        #expect(failure?.message == "Xcode and Logic Pro can't both fit on Built-in Retina Display. Try a wider display.")
        #expect(WindowFailure.bothTooWide("Safari", "Safari", display: "Studio Display").message
                == "These Safari windows can't both fit on Studio Display. Try a wider display.")
    }

    @Test func aWindowWiderThanTheDisplayCanBeSaysTryAWiderDisplay() {
        let screens = [Self.laptop]
        let a = FakeWindow("Safari", CGRect(x: 100, y: 100, width: 700, height: 600), displays: screens.map(\.visible))
        let b = FakeWindow("Notes", CGRect(x: 0, y: 40, width: 1512, height: 700), displays: screens.map(\.visible))
        b.minimumWidth = 1500
        let failure = arranger(screens).split(left: a, right: b, in: Self.laptop.visible, gap: 8, displayName: "Built-in Retina Display")
        #expect(failure == .tooWide("Notes"))
        #expect(failure?.message == "Notes can't be resized that small. Try a wider display.")
    }

    @Test func aFixedWidthWindowCountsOnceItIsInPlace() {
        let screens = [Self.laptop]
        let a = FakeWindow("System Settings", CGRect(x: 100, y: 100, width: 700, height: 600), displays: screens.map(\.visible))
        a.maximumWidth = 715
        let target = DisplayGeometry.split(in: Self.laptop.visible, gap: 8).left
        guard case .closest(let f) = arranger(screens).move(a, to: target) else { Issue.record("not placed"); return }
        #expect(f.origin == target.origin && f.width == 715)
    }

    @Test func aMoveThatLandsAMomentLaterStillCounts() {
        let screens = [Self.laptop, Self.right]
        var waited: TimeInterval = 0
        let w = FakeWindow("Slack", CGRect(x: 100, y: 100, width: 900, height: 700), displays: screens.map(\.visible))
        w.lag = 3
        let target = DisplayGeometry.split(in: Self.right.visible, gap: 8).right
        let landing = arranger(screens) { waited += $0 }.move(w, to: target)
        #expect(landing == .placed(target))
        // A short wait, never long: within the settle time for each step.
        #expect(waited > 0 && waited <= WindowArranger.settleTime * 3)
    }

    @Test func refusalsAndClosedWindowsSayWhatHappened() {
        let screens = [Self.laptop]
        let a = FakeWindow("Safari", CGRect(x: 100, y: 100, width: 700, height: 600), displays: screens.map(\.visible))
        let b = FakeWindow("Finder", CGRect(x: 300, y: 200, width: 500, height: 500), displays: screens.map(\.visible))
        b.refuses = true
        let refused = arranger(screens).split(left: a, right: b, in: Self.laptop.visible, gap: 8, displayName: "Built-in Retina Display")
        #expect(refused == .refused("Finder"))
        #expect(refused?.message == "Finder won't let Glasspad move its window. Try again, or drag it into place.")
        b.refuses = false
        b.closed = true
        #expect(arranger(screens).split(left: a, right: b, in: Self.laptop.visible, gap: 8, displayName: "") == .closed)
        b.closed = false
        // In full screen: taken out of it first, then split.
        b.fullScreen = true
        #expect(arranger(screens).split(left: a, right: b, in: Self.laptop.visible, gap: 8, displayName: "") == nil)
        #expect(b.log.first == "exit full screen")
        #expect(!b.isFullScreen)
        // One that will not leave full screen is named.
        b.fullScreen = true
        b.staysFullScreen = true
        #expect(arranger(screens).split(left: a, right: b, in: Self.laptop.visible, gap: 8, displayName: "") == .fullScreen("Finder"))
    }

    @Test func leftAndRightCountsOnlyWithEachWindowOnItsSide() {
        let v = Self.laptop.visible
        let halves = DisplayGeometry.split(in: v, gap: 8)
        #expect(SplitScreen.looksSplit(left: halves.left, right: halves.right, in: v))
        #expect(SplitScreen.looksSplit(left: DisplayGeometry.split(in: v).left, right: DisplayGeometry.split(in: v).right, in: v))
        #expect(!SplitScreen.looksSplit(left: halves.right, right: halves.left, in: v))
        #expect(!SplitScreen.looksSplit(left: CGRect(x: 100, y: 100, width: 700, height: 600), right: halves.right, in: v))
        #expect(!SplitScreen.looksSplit(left: halves.left, right: halves.right.offsetBy(dx: 2000, dy: 0), in: v))
    }
}
