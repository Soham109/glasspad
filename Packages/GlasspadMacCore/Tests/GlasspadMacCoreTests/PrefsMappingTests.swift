import Foundation
import GlasspadKit
import Testing
@testable import GlasspadMacCore

/// Values copied from `defaults read` on the development Mac (macOS 26.6).
nonisolated(unsafe) let observedTrackpad: [String: Any] = [
    "ActuateDetents": 1, "Clicking": 1, "DragLock": 0, "Dragging": 0, "FirstClickThreshold": 1,
    "ForceSuppressed": 0, "SecondClickThreshold": 1, "TrackpadCornerSecondaryClick": 2,
    "TrackpadFiveFingerPinchGesture": 2, "TrackpadFourFingerHorizSwipeGesture": 2,
    "TrackpadFourFingerPinchGesture": 2, "TrackpadFourFingerVertSwipeGesture": 2, "TrackpadHandResting": 1,
    "TrackpadHorizScroll": 1, "TrackpadMomentumScroll": 1, "TrackpadPinch": 1, "TrackpadRightClick": 0,
    "TrackpadRotate": 1, "TrackpadScroll": 1, "TrackpadThreeFingerDrag": 0,
    "TrackpadThreeFingerHorizSwipeGesture": 2, "TrackpadThreeFingerTapGesture": 0,
    "TrackpadThreeFingerVertSwipeGesture": 2, "TrackpadTwoFingerDoubleTapGesture": 1,
    "TrackpadTwoFingerFromRightEdgeSwipeGesture": 3, "USBMouseStopsTrackpad": 0, "UserPreferences": 1, "version": 12,
]
nonisolated(unsafe) let observedGlobal: [String: Any] = [
    "com.apple.mouse.scaling": "1.5", "com.apple.swipescrolldirection": 1,
    "com.apple.trackpad.forceClick": 1, "com.apple.trackpad.scaling": "0.875",
]

@Suite struct PrefsMappingTests {
    @Test func observedMacMapsAsExpected() {
        let s = TrackpadPrefsReader.map(.init(trackpad: observedTrackpad, global: observedGlobal))
        #expect(s.trackingSpeed == 0.875)
        #expect(s.naturalScrolling)
        #expect(s.tapToClick)
        #expect(s.secondaryClick == .bottomRight)
        #expect(!s.threeFingerDrag)
        #expect(s.lookUp == .forceClick)
        #expect(s.scrollMomentum)
        #expect(s.pinchToZoom && s.rotate && s.smartZoom)
        #expect(s.swipeBetweenPages == .twoFinger)
        #expect(s.swipeBetweenSpaces == .three)
        #expect(s.missionControl == .three)
        #expect(s.appExpose == .off)
        #expect(s.launchpadPinch && s.showDesktopSpread)
        #expect(s.notificationCenterEdge)
        #expect(s.clickPressure == .medium)
        #expect(s.hapticStrength == TrackpadSettings.macDefault.hapticStrength)
    }

    @Test func emptyDomainsGiveMacDefault() {
        #expect(TrackpadPrefsReader.map(.init()) == TrackpadSettings.macDefault)
    }

    @Test func bluetoothDomainFillsMissingKeys() {
        let s = TrackpadPrefsReader.map(.init(trackpad: [:], bluetoothTrackpad: ["Clicking": 1, "FirstClickThreshold": 2]))
        #expect(s.tapToClick)
        #expect(s.clickPressure == .firm)
    }

    @Test func builtInDomainWinsOverBluetooth() {
        let s = TrackpadPrefsReader.map(.init(trackpad: ["Clicking": 0], bluetoothTrackpad: ["Clicking": 1]))
        #expect(!s.tapToClick)
    }

    @Test(arguments: [
        (1, 0, SecondaryClick.twoFinger), (0, 1, .bottomLeft), (0, 2, .bottomRight), (0, 0, .off), (1, 2, .twoFinger),
    ])
    func secondaryClick(right: Int, corner: Int, expected: SecondaryClick) {
        let s = TrackpadPrefsReader.map(.init(trackpad: ["TrackpadRightClick": right, "TrackpadCornerSecondaryClick": corner]))
        #expect(s.secondaryClick == expected)
    }

    @Test func threeFingerPageSwipesAndFourFingerSpaces() {
        let s = TrackpadPrefsReader.map(.init(
            trackpad: ["TrackpadThreeFingerHorizSwipeGesture": 1, "TrackpadFourFingerHorizSwipeGesture": 2,
                       "TrackpadThreeFingerVertSwipeGesture": 0, "TrackpadFourFingerVertSwipeGesture": 2],
            global: ["AppleEnableSwipeNavigateWithScrolls": 0]))
        #expect(s.swipeBetweenPages == .threeFinger)
        #expect(s.swipeBetweenSpaces == .four)
        #expect(s.missionControl == .four)
    }

    @Test func twoOrThreeFingerPages() {
        let s = TrackpadPrefsReader.map(.init(trackpad: ["TrackpadThreeFingerHorizSwipeGesture": 1],
                                              global: ["AppleEnableSwipeNavigateWithScrolls": 1]))
        #expect(s.swipeBetweenPages == .twoOrThree)
        #expect(s.swipeBetweenSpaces == .off)
    }

    @Test func pagesOff() {
        let s = TrackpadPrefsReader.map(.init(trackpad: ["TrackpadThreeFingerHorizSwipeGesture": 0],
                                              global: ["AppleEnableSwipeNavigateWithScrolls": 0]))
        #expect(s.swipeBetweenPages == .off)
    }

    @Test func dockTogglesGateMissionControlExposeLaunchpadDesktop() {
        let s = TrackpadPrefsReader.map(.init(
            trackpad: observedTrackpad,
            dock: ["showMissionControlGestureEnabled": 0, "showAppExposeGestureEnabled": 1,
                   "showLaunchpadGestureEnabled": 0, "showDesktopGestureEnabled": 1]))
        #expect(s.missionControl == .off)
        #expect(s.appExpose == .three)
        #expect(!s.launchpadPinch)
        #expect(s.showDesktopSpread)
    }

    @Test func pinchOffDisablesBoth() {
        let s = TrackpadPrefsReader.map(.init(trackpad: ["TrackpadFourFingerPinchGesture": 0, "TrackpadFiveFingerPinchGesture": 0]))
        #expect(!s.launchpadPinch && !s.showDesktopSpread)
    }

    @Test func lookUpVariants() {
        #expect(TrackpadPrefsReader.map(.init(trackpad: ["TrackpadThreeFingerTapGesture": 2])).lookUp == .threeFingerTap)
        #expect(TrackpadPrefsReader.map(.init(trackpad: ["TrackpadThreeFingerTapGesture": 0],
                                              global: ["com.apple.trackpad.forceClick": 0])).lookUp == .off)
    }

    @Test func miscBooleansAndClamping() {
        let s = TrackpadPrefsReader.map(.init(
            trackpad: ["TrackpadMomentumScroll": 0, "TrackpadPinch": 0, "TrackpadRotate": 0,
                       "TrackpadTwoFingerDoubleTapGesture": 0, "TrackpadThreeFingerDrag": 1,
                       "TrackpadTwoFingerFromRightEdgeSwipeGesture": 0, "FirstClickThreshold": 0],
            global: ["com.apple.trackpad.scaling": 7.5, "com.apple.swipescrolldirection": 0]))
        #expect(!s.scrollMomentum && !s.pinchToZoom && !s.rotate && !s.smartZoom)
        #expect(s.threeFingerDrag)
        #expect(!s.notificationCenterEdge)
        #expect(s.clickPressure == .light)
        #expect(s.trackingSpeed == 3)
        #expect(!s.naturalScrolling)
    }

    @Test @MainActor func watcherPublishesOnlyOnChange() {
        var value = TrackpadSettings.macDefault
        let watcher = TrackpadPrefsWatcher(read: { value })
        var seen: [TrackpadSettings] = []
        watcher.onChange = { seen.append($0) }
        watcher.refresh()
        #expect(seen.isEmpty)
        value.tapToClick.toggle()
        watcher.refresh()
        watcher.refresh()
        #expect(seen.count == 1)
        #expect(watcher.settings.tapToClick == value.tapToClick)
    }

    /// With no phone the prefs are read every 5 s; a phone connecting gets a fresh read at
    /// once and the usual 2 s after that.
    @Test @MainActor func watcherSlowsDownWithoutAPhone() {
        var value = TrackpadSettings.macDefault
        let watcher = TrackpadPrefsWatcher(read: { value })
        var seen: [TrackpadSettings] = []
        watcher.onChange = { seen.append($0) }
        watcher.start()
        defer { watcher.stop() }
        #expect(watcher.scheduledInterval == 5)
        value.tapToClick.toggle()
        watcher.setPhoneConnected(true)
        #expect(seen.count == 1)
        #expect(watcher.scheduledInterval == 2)
        watcher.setPhoneConnected(false)
        #expect(watcher.scheduledInterval == 5 && watcher.currentInterval == 5)
    }

    @Test func statusChecksSlowDownWithoutAPhoneOrCode() {
        #expect(GlasspadController.statusInterval(phoneConnected: true, pairing: false) == 1)
        #expect(GlasspadController.statusInterval(phoneConnected: false, pairing: true) == 1)
        #expect(GlasspadController.statusInterval(phoneConnected: false, pairing: false) == 5)
    }

    @Test func liveReadDoesNotCrash() {
        // Reads (never writes) the real domains on this Mac.
        let s = TrackpadPrefsReader.read()
        #expect((0...3).contains(s.trackingSpeed))
    }
}
