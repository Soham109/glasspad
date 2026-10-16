import CoreGraphics
import Foundation
import Testing
@testable import GlasspadKit

/// Arrangements used below, in Quartz global coordinates (main display at 0, 0, y down).
private enum Arrangement {
    /// A 14 inch MacBook Pro looking like 1512 × 982.
    static let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    /// A 27 inch display at 2560 × 1440 to the right, bottoms lined up.
    static let right = CGRect(x: 1512, y: 982 - 1440, width: 2560, height: 1440)
    /// The same display to the left, tops lined up.
    static let left = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
    /// A 1920 × 1080 display above, centred.
    static let above = CGRect(x: (1512 - 1920) / 2, y: -1080, width: 1920, height: 1080)
}

@Suite struct DisplayGeometryTests {
    @Test func appKitFramesTurnIntoQuartzAndBack() {
        // An AppKit frame for a display above the main one has a positive y.
        let cocoa = CGRect(x: -204, y: 982, width: 1920, height: 1080)
        let q = DisplayGeometry.quartz(cocoa, mainHeight: 982)
        #expect(q == Arrangement.above)
        #expect(DisplayGeometry.quartz(q, mainHeight: 982) == cocoa)
        // The main display's visible frame (menu bar 37 pt, Dock 70 pt) loses its top in Quartz.
        let visible = DisplayGeometry.quartz(CGRect(x: 0, y: 70, width: 1512, height: 875), mainHeight: 982)
        #expect(visible == CGRect(x: 0, y: 37, width: 1512, height: 875))
    }

    @Test func aWindowBelongsToTheDisplayShowingMostOfIt() {
        let displays = [Arrangement.laptop, Arrangement.right]
        // Mostly on the external display.
        #expect(DisplayGeometry.displayIndex(for: CGRect(x: 1400, y: 100, width: 800, height: 600), in: displays) == 1)
        // Mostly on the laptop.
        #expect(DisplayGeometry.displayIndex(for: CGRect(x: 1000, y: 100, width: 800, height: 600), in: displays) == 0)
        // Off every display: the nearest one.
        #expect(DisplayGeometry.displayIndex(for: CGRect(x: 100, y: 2000, width: 100, height: 100), in: displays) == 0)
        #expect(DisplayGeometry.displayIndex(for: CGRect.zero, in: []) == nil)
    }

    @Test func pointsFindTheirDisplayInEveryArrangement() {
        let left = [Arrangement.laptop, Arrangement.left]
        #expect(DisplayGeometry.displayIndex(at: CGPoint(x: -10, y: 10), in: left) == 1)
        #expect(DisplayGeometry.displayIndex(at: CGPoint(x: 10, y: 10), in: left) == 0)
        let above = [Arrangement.laptop, Arrangement.above]
        #expect(DisplayGeometry.displayIndex(at: CGPoint(x: 700, y: -5), in: above) == 1)
        // Between displays (below the external one, right of the laptop): the nearest.
        let right = [Arrangement.laptop, Arrangement.right]
        #expect(DisplayGeometry.displayIndex(at: CGPoint(x: 1600, y: 1100), in: right) == 1)
    }

    @Test func tilesFollowMoveAndResize() {
        let visible = CGRect(x: 0, y: 37, width: 1512, height: 875)
        let window = CGRect(x: 200, y: 200, width: 900, height: 600)
        #expect(DisplayGeometry.tile(.leftHalf, window: window, in: visible) == CGRect(x: 0, y: 37, width: 756, height: 875))
        #expect(DisplayGeometry.tile(.rightHalf, window: window, in: visible) == CGRect(x: 756, y: 37, width: 756, height: 875))
        #expect(DisplayGeometry.tile(.topHalf, window: window, in: visible).height == 438)
        #expect(DisplayGeometry.tile(.bottomHalf, window: window, in: visible).maxY == visible.maxY)
        #expect(DisplayGeometry.tile(.fill, window: window, in: visible) == visible)
        let centred = DisplayGeometry.tile(.center, window: window, in: visible)
        #expect(centred.size == window.size && abs(centred.midX - visible.midX) <= 1 && abs(centred.midY - visible.midY) <= 1)
        // With margins the halves leave a gap around and between them.
        let (l, r) = DisplayGeometry.split(in: visible, gap: 8)
        #expect(l.minX == 8 && r.maxX == 1504 && r.minX - l.maxX == 8 && l.minY == 45)
        // On a display to the left, x is negative and the tile stays there.
        let leftVisible = Arrangement.left
        #expect(DisplayGeometry.tile(.rightHalf, window: window, in: leftVisible) == CGRect(x: -1280, y: 0, width: 1280, height: 1440))
    }

    @Test func movingToAnotherDisplayKeepsTheWindowsPlaceAndShare() {
        let laptop = CGRect(x: 0, y: 37, width: 1512, height: 875)
        let external = CGRect(x: 1512, y: -458, width: 2560, height: 1415)
        // A left half stays a left half on a bigger display.
        let half = DisplayGeometry.tile(.leftHalf, window: .zero, in: laptop)
        #expect(DisplayGeometry.moved(half, from: laptop, to: external) == CGRect(x: 1512, y: -458, width: 1280, height: 1415))
        // A window a quarter in keeps sitting a quarter in.
        let w = CGRect(x: 378, y: 37 + 218.75, width: 756, height: 437.5)
        let m = DisplayGeometry.moved(w, from: laptop, to: external)
        #expect(m.minX == 1512 + 640 && m.width == 1280)
        // Back again is where it started (to the point).
        let back = DisplayGeometry.moved(m, from: external, to: laptop)
        #expect(abs(back.minX - w.minX) <= 1 && abs(back.width - w.width) <= 1)
        // Above: y goes negative and stays inside.
        let up = DisplayGeometry.moved(half, from: laptop, to: Arrangement.above)
        #expect(Arrangement.above.contains(up))
        // From a display with no size: centred.
        #expect(Arrangement.above.contains(DisplayGeometry.moved(w, from: .zero, to: Arrangement.above)))
    }

    @Test func placingAWindowKeepsItInside() {
        let visible = CGRect(x: 0, y: 37, width: 1512, height: 875)
        let window = CGRect(x: 0, y: 37, width: 800, height: 600)
        #expect(DisplayGeometry.placed(window, origin: CGPoint(x: 100.4, y: 80.6), in: visible) == CGRect(x: 100, y: 81, width: 800, height: 600))
        #expect(DisplayGeometry.placed(window, origin: CGPoint(x: 1400, y: -50), in: visible) == CGRect(x: 712, y: 37, width: 800, height: 600))
        // Larger than the display: as large as the display.
        let big = DisplayGeometry.placed(CGRect(x: 0, y: 0, width: 3000, height: 2000), origin: .zero, in: visible)
        #expect(big == visible)
    }

    @Test func nextDisplayGoesLeftToRightAndWraps() {
        let displays = [Arrangement.laptop, Arrangement.right, Arrangement.left]
        #expect(DisplayGeometry.nextDisplayIndex(after: 2, in: displays) == 0)
        #expect(DisplayGeometry.nextDisplayIndex(after: 0, in: displays) == 1)
        #expect(DisplayGeometry.nextDisplayIndex(after: 1, in: displays) == 2)
        #expect(DisplayGeometry.nextDisplayIndex(after: 0, in: [Arrangement.laptop]) == nil)
    }

    @Test func makingADisplayMainMovesItToTheOrigin() {
        let displays: [(id: UInt32, frame: CGRect)] = [(1, Arrangement.laptop), (2, Arrangement.right)]
        let origins = DisplayGeometry.origins(makingMain: 2, displays)
        #expect(origins == [DisplayOrigin(display: 1, origin: CGPoint(x: -1512, y: 458)),
                            DisplayOrigin(display: 2, origin: .zero)])
        #expect(DisplayGeometry.origins(makingMain: 9, displays).isEmpty)
        #expect(DisplayGeometry.normalized(origins, main: 1).first?.origin == .zero)
    }

    @Test func draggedDisplaysSnapToAnEdgeAndLineUp() {
        let laptop = Arrangement.laptop
        let size = CGSize(width: 2560, height: 1440)
        // Dropped a little right of the laptop and a bit high: touches its right edge, and the
        // bottoms line up because they were close.
        let near = DisplayGeometry.snap(CGRect(origin: CGPoint(x: 1600, y: -420), size: size), to: [laptop])
        #expect(near == CGPoint(x: 1512, y: -458))
        // Dropped far above: sits on top, sharing part of the edge, never overlapping.
        let top = DisplayGeometry.snap(CGRect(origin: CGPoint(x: 300, y: -1700), size: size), to: [laptop])
        #expect(top.y == -1440)
        #expect(!CGRect(origin: top, size: size).insetBy(dx: 1, dy: 1).intersects(laptop))
        // Dropped on top of the laptop: pushed to the nearest free edge.
        let onTop = DisplayGeometry.snap(CGRect(origin: CGPoint(x: -2000, y: 100), size: size), to: [laptop])
        #expect(onTop.x == -2560)
        // Far below and to the right: touches the laptop along an edge, sharing part of it.
        let low = CGRect(origin: DisplayGeometry.snap(CGRect(origin: CGPoint(x: 1900, y: 3000), size: size), to: [laptop]), size: size)
        let sideBySide = (low.minX == laptop.maxX || low.maxX == laptop.minX) && low.minY < laptop.maxY && low.maxY > laptop.minY
        let stacked = (low.minY == laptop.maxY || low.maxY == laptop.minY) && low.minX < laptop.maxX && low.maxX > laptop.minX
        #expect(sideBySide || stacked)
        // Three displays: the snap never lands on the third.
        let third = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let s = DisplayGeometry.snap(CGRect(origin: CGPoint(x: 1600, y: 50), size: size), to: [laptop, third])
        let r = CGRect(origin: s, size: size).insetBy(dx: 1, dy: 1)
        #expect(!r.intersects(laptop) && !r.intersects(third))
    }

    @Test func theMiniatureFitsEveryArrangementAndMapsBack() {
        for displays in [[Arrangement.laptop, Arrangement.right], [Arrangement.laptop, Arrangement.left],
                         [Arrangement.laptop, Arrangement.above], [Arrangement.laptop]] {
            let size = CGSize(width: 360, height: 240)
            let m = DisplayMiniature(frames: displays, fitting: size, padding: 12)
            let union = displays.reduce(CGRect.null) { $0.union($1) }
            let drawn = m.toView(union)
            #expect(drawn.minX >= 11.99 && drawn.minY >= 11.99 && drawn.maxX <= 348.01 && drawn.maxY <= 228.01)
            // Centred, and touching the padding on at least one axis.
            #expect(abs(drawn.midX - 180) < 0.01 && abs(drawn.midY - 120) < 0.01)
            #expect(abs(drawn.width - 336) < 0.01 || abs(drawn.height - 216) < 0.01)
            // Same scale everywhere: relative sizes are true.
            let a = m.toView(displays[0])
            #expect(abs(a.width / a.height - displays[0].width / displays[0].height) < 0.0001)
            let p = CGPoint(x: 123, y: -45)
            let back = m.toGlobal(m.toView(p))
            #expect(abs(back.x - p.x) < 0.0001 && abs(back.y - p.y) < 0.0001)
        }
        // A display drawn as it is: the external one is 1.69 times as wide as the laptop.
        let m = DisplayMiniature(frames: [Arrangement.laptop, Arrangement.right], fitting: CGSize(width: 400, height: 300))
        #expect(abs(m.toView(Arrangement.right).width / m.toView(Arrangement.laptop).width - 2560.0 / 1512) < 0.0001)
        #expect(abs(m.toGlobal(length: m.scale * 10) - 10) < 0.0001)
    }

    @Test func stateFindsWindowsDisplaysAndSkipsMirrors() {
        let state = DisplaysState(displays: [
            MacDisplay(id: 1, name: "Built-in Retina Display", frame: Arrangement.laptop,
                       visibleFrame: CGRect(x: 0, y: 37, width: 1512, height: 875), isMain: true, isBuiltIn: true, notchWidth: 200),
            MacDisplay(id: 2, name: "Studio Display", frame: Arrangement.right, visibleFrame: Arrangement.right, isMain: false),
            MacDisplay(id: 3, name: "Projector", frame: Arrangement.laptop, visibleFrame: Arrangement.laptop, isMain: false, mirrorOf: 1),
        ], windows: [MacWindow(id: 9, bundleID: "com.apple.Safari", appName: "Safari", frame: CGRect(x: 2000, y: 0, width: 900, height: 700))])
        #expect(state.shownDisplays.map(\.id) == [1, 2])
        #expect(state.display(of: state.windows[0])?.id == 2)
        #expect(state.displays[0].menuBarHeight == 37)
        #expect(state.displays[1].menuBarHeight == 0)
        #expect(state.windows[0].label == "Safari")
    }
}

@Suite struct DisplaysProtocolTests {
    private func roundTrip(_ m: ModeMessage) throws -> ModeMessage? {
        let data = try ControlMessage.mode(m).jsonData()
        guard case .mode(let back) = try ControlMessage.from(jsonData: data) else { return nil }
        return back
    }

    @Test func everyDisplaysMessageRoundTrips() throws {
        let id = UUID()
        let state = DisplaysState(displays: [
            MacDisplay(id: 1, name: "Built-in Retina Display", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                       visibleFrame: CGRect(x: 0, y: 37, width: 1512, height: 875), isMain: true, isBuiltIn: true,
                       notchWidth: 186, brightness: 0.6,
                       resolutions: [DisplayResolution(id: 7, width: 1512, height: 982, isDefault: true)], resolutionID: 7),
        ], windows: [MacWindow(id: 42, bundleID: "com.apple.mail", appName: "Mail", title: "Inbox",
                               frame: CGRect(x: 10, y: 40, width: 900, height: 700))],
           nightShift: true, canArrangeWindows: true, tileMargin: 8,
           pending: PendingDisplayChange(summary: "Built-in Retina Display looks like 1512 × 982", secondsLeft: 15))
        let messages: [ModeMessage] = [
            .modeSelected(.displays), .displaysWatch(on: true), .displaysWatch(on: false), .displaysState(state),
            .windowCommand(id: id, windowID: 42, command: .raise),
            .windowCommand(id: id, windowID: 42, command: .tile(.leftHalf)),
            .windowCommand(id: id, windowID: 42, command: .split(with: 43)),
            .windowCommand(id: id, windowID: 42, command: .move(display: 2, origin: nil)),
            .windowCommand(id: id, windowID: 42, command: .move(display: 1, origin: CGPoint(x: 10, y: 20))),
            .windowCommand(id: id, windowID: 42, command: .minimize),
            .windowCommand(id: id, windowID: 42, command: .close),
            .windowCommand(id: id, windowID: 42, command: .fullScreen),
            .displayCommand(id: id, command: .brightness(display: 1, value: 0.4)),
            .displayCommand(id: id, command: .resolution(display: 1, id: 7)),
            .displayCommand(id: id, command: .mirror(display: 2, of: 1)),
            .displayCommand(id: id, command: .mirror(display: 2, of: nil)),
            .displayCommand(id: id, command: .makeMain(display: 2)),
            .displayCommand(id: id, command: .arrange([DisplayOrigin(display: 2, origin: CGPoint(x: 1512, y: -458))])),
            .displayCommand(id: id, command: .keepChanges),
            .displayCommand(id: id, command: .revertChanges),
            .displaysResult(id: id, ok: false, message: "That window closed"),
            .displaysResult(id: id, ok: true, message: nil),
        ]
        for m in messages { #expect(try roundTrip(m) == m) }
    }

    @Test func theWireShapeIsTheDocumentedOne() throws {
        let data = try JSONEncoder().encode(ModeMessage.displaysWatch(on: true))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["t"] as? String == "displaysWatch" && json["on"] as? Bool == true)
        let window = try JSONEncoder().encode(MacWindow(id: 5, bundleID: nil, appName: "App", frame: CGRect(x: 1, y: 2, width: 3, height: 4)))
        let w = try #require(JSONSerialization.jsonObject(with: window) as? [String: Any])
        #expect((w["frame"] as? [[Double]]) == [[1, 2], [3, 4]])
    }

    @Test func aBuildWithoutDisplaysDropsTheMessagesAndKeepsTalking() throws {
        // What an older peer sees: an unknown mode message fails to decode, and the transport
        // drops that one frame (it never ends the session). Simulated with a tag nobody knows.
        let unknown = #"{"t":"mode","mode":{"t":"displaysSomethingNewer","x":1}}"#
        #expect(throws: (any Error).self) { try ControlMessage.from(jsonData: Data(unknown.utf8)) }
        // A state from a newer Mac with fields this build does not know still decodes.
        let newer = #"{"displays":[],"windows":[],"canArrangeWindows":true,"tileMargin":0,"somethingNew":3}"#
        #expect(try JSONDecoder().decode(DisplaysState.self, from: Data(newer.utf8)).windows.isEmpty)
    }

    @Test func displaysStartsHiddenAndArrivesHiddenInSavedLists() throws {
        #expect(ModeListLayout().visible(known: ModeListLayout.defaultOrder) == ["trackpad", "keys", "media", "dock", "actions"])
        let old = #"{"order":["trackpad","keys","remote"],"hidden":[],"splitActions":false}"#
        let decoded = try JSONDecoder().decode(ModeListLayout.self, from: Data(old.utf8))
        #expect(decoded.order.last == "displays" && decoded.hidden == ["displays"])
    }
}
