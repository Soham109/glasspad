import Foundation
import Observation
import UIKit

/// Which screen is showing, plus the sheets on top. Deep links, widgets and Siri all
/// come through here.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    private(set) var mode: AppMode
    var showSettings = false
    var showPairing = false
    /// The trackpad and Present screens dim after the idle delay; a touch wakes them.
    private(set) var isDimmed = false
    /// Last time anything touched a screen that dims. Not observed: it changes on every touch.
    @ObservationIgnored private var lastActivity = ProcessInfo.processInfo.systemUptime
    @ObservationIgnored private var dimTimer: Timer?

    private init() {
        mode = PhoneSettings.shared.lastMode
    }

    func show(_ newMode: AppMode) {
        showSettings = false
        showPairing = false
        if mode != newMode {
            mode = newMode
            PhoneSettings.shared.lastMode = newMode
        }
        noteActivity()
        MacSession.shared.modeDidChange(to: newMode)
        ScreenAwake.update()
        LiveActivityController.shared.refresh()
    }

    /// Handles `glasspad://pair?...`, `glasspad://trackpad` and `glasspad://mode/<name>`.
    func open(_ url: URL) {
        guard url.scheme == "glasspad" else { return }
        switch url.host() {
        case "pair":
            if let payload = PairingParser.parse(url.absoluteString) {
                let mac = PairingStore.shared.add(payload)
                PhoneSettings.shared.hasOnboarded = true
                MacSession.shared.didPair(mac)
                show(.trackpad)
                Haptics.shared.play(.snap)
            }
        case "trackpad":
            show(.trackpad)
        case "mode":
            if let name = url.pathComponents.dropFirst().first, let target = AppMode(rawValue: name) {
                show(target)
            }
        default:
            break
        }
    }

    // MARK: Idle dimming

    var dims: Bool { mode == .trackpad || mode == .present }

    /// Called on every touch of a dimming screen. Cheap enough to call per touch sample.
    func noteActivity() {
        lastActivity = ProcessInfo.processInfo.systemUptime
        if isDimmed { isDimmed = false }
    }

    func startDimTimer() {
        dimTimer?.invalidate()
        noteActivity()
        let timer = Timer(timeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { AppRouter.shared.checkIdle() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        dimTimer = timer
    }

    func stopDimTimer() {
        dimTimer?.invalidate()
        dimTimer = nil
        isDimmed = false
    }

    private func checkIdle() {
        guard dims, !showSettings, !showPairing else { return }
        let idle = ProcessInfo.processInfo.systemUptime - lastActivity
        if !isDimmed, idle >= PhoneSettings.shared.dimDelay { isDimmed = true }
    }
}

/// Keeps the screen on only while a screen that needs it is visible and the app is active.
@MainActor
enum ScreenAwake {
    static var sceneActive = false

    static func update() {
        let router = AppRouter.shared
        let wanted = sceneActive && PhoneSettings.shared.hasOnboarded && router.dims
            && !router.showSettings && !router.showPairing
        if UIApplication.shared.isIdleTimerDisabled != wanted {
            UIApplication.shared.isIdleTimerDisabled = wanted
        }
        if wanted { router.startDimTimer() } else { router.stopDimTimer() }
    }
}
