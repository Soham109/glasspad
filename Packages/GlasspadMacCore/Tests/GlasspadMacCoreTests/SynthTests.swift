import CoreGraphics
import Foundation
import GlasspadKit
import Testing
@testable import GlasspadMacCore

/// Builds events and inspects fields. Nothing here posts into the live session: the poster is
/// a CapturingEventPoster and the cursor/displays are fixed.
func makeSynth(_ caps: SynthCapabilities = .select(probe: { _ in true }),
               settings: TrackpadSettings = .macDefault,
               cursor: CGPoint = CGPoint(x: 500, y: 400)) -> (EventSynthesizer, CapturingEventPoster) {
    let poster = CapturingEventPoster()
    let synth = EventSynthesizer(poster: poster, settings: settings, capabilities: caps, source: nil,
                                 cursorLocation: { cursor },
                                 displayBounds: { [CGRect(x: 0, y: 0, width: 1512, height: 982)] })
    return (synth, poster)
}

func int(_ e: CGEvent, _ f: CGEventField) -> Int64 { e.getIntegerValueField(f) }

@Suite struct PointerTests {
    @Test func moveSetsLocationAndDeltas() throws {
        let (s, p) = makeSynth()
        s.handle(.move(dx: 10.6, dy: -3.2))
        let e = try #require(p.events.first)
        #expect(e.type == .mouseMoved)
        #expect(e.location == CGPoint(x: 510.6, y: 396.8))
        #expect(int(e, .mouseEventDeltaX) == 10)
        #expect(int(e, .mouseEventDeltaY) == -3)
        #expect(p.posted.first?.tap == .cghidEventTap)
    }

    @Test func fractionalDeltasCarryOver() {
        let (s, p) = makeSynth()
        s.handle([.move(dx: 0.6, dy: 0), .move(dx: 0.6, dy: 0)])
        #expect(p.events.map { int($0, .mouseEventDeltaX) } == [0, 1])
    }

    @Test func moveIsClampedToDisplay() throws {
        let (s, p) = makeSynth(cursor: CGPoint(x: 1500, y: 970))
        s.handle(.move(dx: 100, dy: 100))
        let e = try #require(p.events.first)
        #expect(e.location == CGPoint(x: 1511, y: 981))
    }

    @Test func clampAllowsCrossingToAdjacentDisplayButNotGaps() {
        let displays = [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: -200, width: 1000, height: 600)]
        // Onto the second display.
        #expect(EventSynthesizer.clamp(CGPoint(x: 1100, y: -100), from: CGPoint(x: 990, y: 100), displays: displays) == CGPoint(x: 1100, y: -100))
        // Into the gap below the second display: clamped, not left in the gap.
        let c = EventSynthesizer.clamp(CGPoint(x: 1100, y: 700), from: CGPoint(x: 1100, y: 300), displays: displays)
        #expect(displays.contains { $0.contains(c) })
    }

    @Test func buttonsCarryClickStateAndDragsFollow() throws {
        let (s, p) = makeSynth()
        s.handle([.button(.left, down: true, clickCount: 2), .drag(dx: 5, dy: 1), .move(dx: 1, dy: 1),
                  .button(.left, down: false, clickCount: 2), .move(dx: 1, dy: 0)])
        let types = p.events.map(\.type)
        #expect(types == [.leftMouseDown, .leftMouseDragged, .leftMouseDragged, .leftMouseUp, .mouseMoved])
        #expect(int(p.events[0], .mouseEventClickState) == 2)
        #expect(int(p.events[3], .mouseEventClickState) == 2)
        #expect(int(p.events[1], .mouseEventDeltaX) == 5)
    }

    @Test func rightAndMiddleButtons() {
        let (s, p) = makeSynth()
        s.handle([.button(.right, down: true, clickCount: 1), .move(dx: 1, dy: 0), .button(.right, down: false, clickCount: 1),
                  .button(.middle, down: true, clickCount: 1), .button(.middle, down: false, clickCount: 1)])
        #expect(p.events.map(\.type) == [.rightMouseDown, .rightMouseDragged, .rightMouseUp, .otherMouseDown, .otherMouseUp])
        #expect(int(p.events[3], .mouseEventButtonNumber) == 2)
    }

    @Test func resetReleasesHeldButtons() {
        let (s, p) = makeSynth()
        s.handle(.button(.left, down: true, clickCount: 1))
        s.reset()
        #expect(p.events.last?.type == .leftMouseUp)
    }
}

@Suite struct ScrollTests {
    @Test func continuousPixelScrollWithPhases() throws {
        let (s, p) = makeSynth()
        s.handle(.scroll(dx: -2, dy: 12.5, phase: .began, momentum: .none))
        let e = try #require(p.events.first)
        #expect(e.type == .scrollWheel)
        #expect(int(e, .scrollWheelEventIsContinuous) == 1)
        #expect(int(e, .scrollWheelEventPointDeltaAxis1) == 12)
        #expect(int(e, .scrollWheelEventPointDeltaAxis2) == -2)
        #expect(e.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) == 12.5)
        #expect(int(e, .scrollWheelEventScrollPhase) == 1)
        #expect(int(e, .scrollWheelEventMomentumPhase) == 0)
    }

    @Test(arguments: [
        (ScrollPhase.changed, MomentumPhase.none, Int64(2), Int64(0)),
        (.ended, .none, 4, 0), (.cancelled, .none, 8, 0),
        (.none, .began, 0, 1), (.none, .changed, 0, 2), (.none, .ended, 0, 3),
    ])
    func phaseMapping(phase: ScrollPhase, momentum: MomentumPhase, cgPhase: Int64, cgMomentum: Int64) throws {
        let (s, p) = makeSynth()
        s.handle(.scroll(dx: 0, dy: 3, phase: phase, momentum: momentum))
        let e = try #require(p.events.first)
        #expect(int(e, .scrollWheelEventScrollPhase) == cgPhase)
        #expect(int(e, .scrollWheelEventMomentumPhase) == cgMomentum)
    }
}

@Suite struct NativeGestureTests {
    @Test func magnify() throws {
        let (s, p) = makeSynth()
        s.handle(.magnify(delta: 0.25, phase: .began))
        let e = try #require(p.events.first)
        #expect(e.type.rawValue == 29)
        #expect(e.get(.eventType) == 29)
        #expect(e.get(.gestureHIDType) == 8)
        #expect(e.getDouble(.gestureZoomValue) == 0.25)
        #expect(e.get(.gesturePhase) == 1)
        #expect(e.location == CGPoint(x: 500, y: 400))
    }

    @Test(arguments: [(GesturePhase.began, Int64(1)), (.changed, 2), (.ended, 4), (.cancelled, 8)])
    func rotatePhases(phase: GesturePhase, hid: Int64) throws {
        let (s, p) = makeSynth()
        s.handle(.rotate(degrees: -12.5, phase: phase))
        let e = try #require(p.events.first)
        #expect(e.type.rawValue == 29)
        #expect(e.get(.gestureHIDType) == 5)
        #expect(e.getDouble(.gestureRotationValue) == -12.5)
        #expect(e.get(.gesturePhase) == hid)
    }

    @Test func smartMagnify() throws {
        let (s, p) = makeSynth()
        s.handle(.smartMagnify)
        let e = try #require(p.events.first)
        #expect(e.type.rawValue == 29)
        #expect(e.get(.gestureHIDType) == 22)
    }

    @Test(arguments: [(true, Int64(4)), (false, 8)])
    func navigate(back: Bool, direction: Int64) {
        let (s, p) = makeSynth()
        s.handle(.navigate(back: back))
        #expect(p.events.count == 2)
        #expect(p.events.allSatisfy { $0.type.rawValue == 29 && $0.get(.gestureHIDType) == 16 })
        #expect(p.events[0].get(.gesturePhase) == 1)
        #expect(p.events[0].get(.gestureSwipeValue) == direction)
        #expect(p.events[1].get(.gesturePhase) == 4)
        #expect(p.events[1].get(.gestureSwipeValue) == 0)
    }

    @Test func spacesDockSwipeFollowsFingers() throws {
        let (s, p) = makeSynth()
        var completed: [SwipeKind] = []
        s.onSwipeCompleted = { completed.append($0) }
        s.handle([.swipe(.spaces, progress: 0.1, phase: .began),
                  .swipe(.spaces, progress: 0.4, phase: .changed),
                  .swipe(.spaces, progress: 0.8, phase: .ended)])
        // Each update is a type-29 companion + a type-30 dock event; the end is re-sent twice later.
        let immediate = p.posted.filter { $0.delay == 0 }
        #expect(immediate.count == 6)
        #expect(p.posted.allSatisfy { $0.tap == .cgSessionEventTap })
        let companion = immediate[0].event
        #expect(companion.type.rawValue == 29)
        #expect(companion.get(.dockSwipeCompanionMagic) == 33231)

        let begin = immediate[1].event
        #expect(begin.type.rawValue == 30)
        #expect(begin.get(.gestureHIDType) == 23)
        #expect(begin.get(.gesturePhase) == 1)
        #expect(begin.get(.dockSwipePhaseRepeat) == 1)
        #expect(begin.get(.dockSwipeMotion) == 1)
        #expect(begin.get(.dockSwipeMotionRepeat) == 1)
        #expect(begin.getDouble(.dockSwipeTypeEncodedA) == Double(Float(bitPattern: 1)))
        #expect(begin.getDouble(.dockSwipeTypeEncodedB) == Double(Float(bitPattern: 1)))
        #expect(abs(begin.getDouble(.dockSwipeOriginOffset) - 0.1) < 1e-6)
        #expect(begin.get(.dockSwipeOriginOffsetBits) == Int64(Float(0.1).bitPattern))
        #expect(begin.get(.dockSwipeInvertedFromDevice) == 1)   // natural scrolling on

        let changed = immediate[3].event
        #expect(changed.get(.gesturePhase) == 2)
        #expect(abs(changed.getDouble(.dockSwipeOriginOffset) - 0.4) < 1e-6)

        let end = immediate[5].event
        #expect(end.get(.gesturePhase) == 4)
        #expect(abs(end.getDouble(.dockSwipeExitSpeedX) - 40) < 1e-3)   // last delta 0.4 * 100
        #expect(abs(end.getDouble(.dockSwipeExitSpeedY) - 40) < 1e-3)

        let delayed = p.posted.filter { $0.delay > 0 }
        #expect(delayed.map(\.delay) == [0.2, 0.2, 0.5, 0.5])
        #expect(completed == [.spaces])
    }

    @Test func swipeBackTowardStartIsCancelled() throws {
        let (s, p) = makeSynth()
        var completed: [SwipeKind] = []
        s.onSwipeCompleted = { completed.append($0) }
        s.handle([.swipe(.spaces, progress: 0.3, phase: .began), .swipe(.spaces, progress: 0.1, phase: .ended)])
        let end = try #require(p.posted.filter { $0.delay == 0 }.last?.event)
        #expect(end.get(.gesturePhase) == 8)
        #expect(completed.isEmpty)
    }

    @Test(arguments: [
        (SwipeKind.missionControl, Int64(2), -0.5), (.appExpose, 2, 0.5), (.launchpad, 3, 0.5), (.showDesktop, 3, -0.5),
    ])
    func dockMotionsAndSigns(kind: SwipeKind, motion: Int64, offset: Double) throws {
        let (s, p) = makeSynth()
        s.handle(.swipe(kind, progress: 0.5, phase: .began))
        let dock = try #require(p.events.last)
        #expect(dock.type.rawValue == 30)
        #expect(dock.get(.dockSwipeMotion) == motion)
        #expect(dock.getDouble(.dockSwipeTypeEncodedA) == Double(Float(bitPattern: UInt32(motion))))
        #expect(dock.getDouble(.dockSwipeOriginOffset) == offset)
    }

    @Test func firstUpdateWithoutBeganIsPromotedToBegan() throws {
        let (s, p) = makeSynth()
        s.handle(.swipe(.missionControl, progress: 0.2, phase: .changed))
        #expect(p.events.last?.get(.gesturePhase) == 1)
    }
}

@Suite struct FallbackGestureTests {
    static let allFallback = SynthCapabilities.select(probe: { _ in false })

    func keyEvents(_ p: CapturingEventPoster) -> [(code: Int64, down: Bool, flags: CGEventFlags)] {
        p.events.filter { $0.type == .keyDown || $0.type == .keyUp }
            .map { (int($0, .keyboardEventKeycode), $0.type == .keyDown, $0.flags) }
    }

    @Test func magnifyBecomesCommandScroll() throws {
        let (s, p) = makeSynth(Self.allFallback)
        s.handle(.magnify(delta: 0.1, phase: .changed))
        let e = try #require(p.events.first)
        #expect(e.type == .scrollWheel)
        #expect(e.flags.contains(.maskCommand))
        #expect(int(e, .scrollWheelEventPointDeltaAxis1) == 40)
    }

    @Test func rotateAndSmartMagnifyAreDroppedWithoutFallback() {
        let (s, p) = makeSynth(Self.allFallback)
        s.handle([.rotate(degrees: 10, phase: .changed), .smartMagnify])
        #expect(p.events.isEmpty)
        #expect(Self.allFallback.mode(for: .rotate) == .unavailable)
    }

    @Test(arguments: [(true, Int64(33)), (false, 30)])
    func navigateUsesCommandBrackets(back: Bool, code: Int64) {
        let (s, p) = makeSynth(Self.allFallback)
        s.handle(.navigate(back: back))
        let keys = keyEvents(p)
        #expect(keys.count == 2)
        #expect(keys[0].code == code && keys[0].down && keys[0].flags.contains(.maskCommand))
    }

    @Test(arguments: [
        (SwipeKind.spaces, 0.6, Int64(124)), (.spaces, -0.6, 123), (.missionControl, 0.6, 126), (.appExpose, 0.6, 125),
    ])
    func dockSwipesUseControlArrows(kind: SwipeKind, progress: Double, code: Int64) {
        let (s, p) = makeSynth(Self.allFallback)
        var completed: [SwipeKind] = []
        s.onSwipeCompleted = { completed.append($0) }
        s.handle([.swipe(kind, progress: progress / 2, phase: .began), .swipe(kind, progress: progress, phase: .ended)])
        let keys = keyEvents(p)
        #expect(keys.count == 2)
        #expect(keys[0].code == code)
        #expect(keys[0].flags.contains(.maskControl))
        #expect(completed == [kind])
    }

    @Test func shortSwipeDoesNothing() {
        let (s, p) = makeSynth(Self.allFallback)
        s.handle(.swipe(.missionControl, progress: 0.1, phase: .ended))
        #expect(p.events.isEmpty)
    }

    @Test func showDesktopUsesF11AndLaunchpadOpensApp() {
        let (s, p) = makeSynth(Self.allFallback)
        s.handle(.swipe(.showDesktop, progress: 1, phase: .ended))
        #expect(keyEvents(p).first?.code == 103)
        s.handle(.swipe(.launchpad, progress: 1, phase: .ended))
        #expect(p.actions.count == 1)
        if case .openApplication(let url) = p.actions.first {
            #expect(url.lastPathComponent == "Apps.app" || url.lastPathComponent == "Launchpad.app")
        } else {
            Issue.record("expected openApplication")
        }
    }

    @Test func launchpadURLPrefersAppsApp() {
        #expect(EventSynthesizer.launchpadURL(fileExists: { _ in true }).lastPathComponent == "Apps.app")
        #expect(EventSynthesizer.launchpadURL(fileExists: { $0.hasSuffix("Launchpad.app") }).lastPathComponent == "Launchpad.app")
    }

    @Test func lookUpIsControlCommandD() {
        let (s, p) = makeSynth()
        s.handle(.lookUp)
        let keys = keyEvents(p)
        #expect(keys.first?.code == 2)
        #expect(keys.first?.flags.contains([.maskCommand, .maskControl]) == true)
    }

    @Test func forceClickStage2LooksUpOnlyWhenConfigured() {
        var settings = TrackpadSettings.macDefault
        settings.lookUp = .forceClick
        let (s, p) = makeSynth(settings: settings)
        s.handle([.forceClick(stage: 1), .forceClick(stage: 2)])
        #expect(keyEvents(p).count == 2)

        settings.lookUp = .threeFingerTap
        let (s2, p2) = makeSynth(settings: settings)
        s2.handle(.forceClick(stage: 2))
        #expect(p2.events.isEmpty)
    }

    @Test func notificationCenterRunsClockScript() {
        let (s, p) = makeSynth()
        s.handle(.notificationCenter)
        if case .runAppleScript(let src) = p.actions.first { #expect(src.contains("Clock")) } else { Issue.record("no action") }
    }
}

@Suite struct CapabilityTests {
    @Test func selfCheckFindsEveryNativePathOnThisMac() {
        let caps = SynthCapabilities.selfCheck()
        for g in SynthGesture.allCases where g.hasNativePath {
            #expect(caps.mode(for: g) == .native, "\(g)")
        }
        #expect(caps.mode(for: .lookUp) == .fallback)
        #expect(caps.mode(for: .notificationCenter) == .fallback)
    }

    @Test func selectionRule() {
        let caps = SynthCapabilities.select(probe: { $0 == .magnify })
        #expect(caps.mode(for: .magnify) == .native)
        #expect(caps.mode(for: .spaces) == .fallback)
        #expect(caps.mode(for: .rotate) == .unavailable)
        #expect(caps.mode(for: .smartMagnify) == .unavailable)
        #expect(caps.mode(for: .navigate) == .fallback)
    }

    @Test func forceFallback() {
        var caps = SynthCapabilities.selfCheck()
        caps.forceFallback(.spaces)
        caps.forceFallback(.rotate)
        #expect(caps.mode(for: .spaces) == .fallback)
        #expect(caps.mode(for: .rotate) == .unavailable)
        #expect(caps.summary.count == SynthGesture.allCases.count)
    }

    @Test func encodedDockTypesMatchKnownConstants() {
        #expect(DockSwipeMotion.horizontal.encoded == 1.401298464324817e-45)
        #expect(DockSwipeMotion.vertical.encoded == 2.802596928649634e-45)
        #expect(DockSwipeMotion.pinch.encoded == 4.203895392974451e-45)
    }
}
