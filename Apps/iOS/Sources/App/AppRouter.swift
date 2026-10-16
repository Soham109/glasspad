import Foundation
import GlasspadKit
import Observation
import UIKit

/// Which screen is showing, plus the sheets on top. Deep links, widgets and Siri all
/// come through here.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    private(set) var mode: AppMode
    /// The split-screen layout on screen, if any. While one shows, `mode` is its first pane's.
    private(set) var layoutID: UUID?
    /// The layout gallery (templates and the person's own).
    var showLayouts = false
    /// The layout editor, opened straight from the mode menu.
    var layoutDraft: LayoutDraft?
    var showSettings = false
    var showPairing = false
    /// The first-run checklist (also from Settings).
    var showSetup = false
    /// Clipboard as a small tool sheet (when it is not a mode of its own).
    var showClipboard = false
    /// Present, full screen, opened as a tool (when it is not a mode of its own).
    var showPresenter = false {
        didSet {
            presenting = showPresenter
            ScreenAwake.update()
        }
    }
    /// Remote, full screen, opened as a tool (when it is not shown as a mode).
    var showRemote = false
    /// A pairing link that arrived from outside the app (the Camera app, a web page, another
    /// app), waiting for the user to confirm it. Applying it unasked would let any link switch
    /// this iPhone to another Mac, or replace the key of the paired one.
    var pairingRequest: PairingPayload?
    /// The trackpad and Present screens dim after the idle delay; a touch wakes them.
    private(set) var isDimmed = false {
        didSet { if isDimmed != oldValue { MacSession.shared.dimmedChanged() } }
    }
    /// Last time anything touched a screen that dims. Not observed: it changes on every touch.
    @ObservationIgnored private var lastActivity = ProcessInfo.processInfo.systemUptime
    @ObservationIgnored private var dimTimer: Timer?

    private init() {
        mode = PhoneSettings.shared.startMode
        // Opening where it was left: a layout, when one was on screen.
        if PhoneSettings.shared.launchMode == nil, let id = LayoutStore.shared.activeID,
           let layout = LayoutStore.shared.layout(id) {
            layoutID = id
            mode = layout.shownModes.first ?? .trackpad
        }
    }

    /// The layout on screen, if any.
    var layout: ScreenLayout? { layoutID.flatMap { LayoutStore.shared.layout($0) } }

    /// Every mode on screen: the current one, or each open pane of the layout.
    var screenModes: [AppMode] { layout?.shownModes ?? [mode] }

    func show(_ requested: AppMode) {
        // Clipboard and Present are tools unless they were split into modes of their own.
        if requested.isTool, requested.shown != requested {
            openTool(requested)
            return
        }
        let newMode = requested.shown
        showSettings = false
        showPairing = false
        showSetup = false
        layoutID = nil
        LayoutStore.shared.activeID = nil
        if mode != newMode {
            mode = newMode
            PhoneSettings.shared.lastMode = newMode
        }
        screenChanged()
    }

    /// Shows a layout: several modes on one screen.
    func show(layout: ScreenLayout) {
        showSettings = false
        showPairing = false
        showSetup = false
        showLayouts = false
        layoutID = layout.id
        LayoutStore.shared.activeID = layout.id
        mode = layout.shownModes.first ?? .trackpad
        screenChanged()
    }

    /// A pane of the layout on screen folded away or came back.
    func layoutPanesChanged() {
        guard let layout else { return }
        mode = layout.shownModes.first ?? .trackpad
        screenChanged()
    }

    private func screenChanged() {
        noteActivity()
        MacSession.shared.modesDidChange(to: screenModes)
        ScreenAwake.update()
        LiveActivityController.shared.refresh()
    }

    /// Opens the editor on a new layout made from `template`.
    func newLayout(from template: LayoutTemplate) -> LayoutDraft {
        let store = LayoutStore.shared
        return LayoutDraft(layout: template.makeLayout(named: store.uniqueName(template.name)), isNew: true)
    }

    /// Opens Clipboard or Present on top of the current mode.
    func openTool(_ tool: AppMode) {
        showSettings = false
        showPairing = false
        switch tool {
        case .clipboard: showClipboard = true
        case .present: showPresenter = true
        case .remote: showRemote = true
        default: break
        }
    }

    /// Handles `glasspad://pair?...`, `glasspad://trackpad` and `glasspad://mode/<name>`.
    func open(_ url: URL) {
        guard url.scheme == "glasspad" else { return }
        switch url.host() {
        case "pair":
            if let payload = PairingParser.parse(url.absoluteString) { pairingRequest = payload }
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

    /// Pairs with the Mac in a code the user scanned or confirmed.
    func pair(_ payload: PairingPayload) {
        pairingRequest = nil
        let mac = PairingStore.shared.add(payload)
        PhoneSettings.shared.hasOnboarded = true
        MacSession.shared.didPair(mac)
        show(.trackpad)
        Haptics.shared.play(.snap)
    }

    // MARK: Idle dimming

    /// The full-screen presenter inside Actions is showing.
    var presenting = false

    var dims: Bool { screenModes.contains(.trackpad) || screenModes.contains(.present) || presenting }

    /// Called on every touch of a dimming screen. Cheap enough to call per touch sample.
    func noteActivity() {
        lastActivity = ProcessInfo.processInfo.systemUptime
        if isDimmed { isDimmed = false }
        if ScreenAwake.releasedForIdle { ScreenAwake.update() }
    }

    /// Seconds since the last touch on a screen that dims.
    var idleTime: TimeInterval { ProcessInfo.processInfo.systemUptime - lastActivity }

    /// Starts the idle check if it is not running (a running one keeps its idle time).
    func startDimTimer() {
        guard dimTimer == nil else { return }
        lastActivity = ProcessInfo.processInfo.systemUptime
        isDimmed = false
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
        guard dims, !showSettings, !showPairing, !showClipboard, !showSetup, !showLayouts, layoutDraft == nil else { return }
        let idle = ProcessInfo.processInfo.systemUptime - lastActivity
        let delay = PhoneSettings.shared.dimDelay
        if !isDimmed, delay > 0, idle >= delay { isDimmed = true }
        // Left alone long enough: let the phone lock on its own Auto-Lock.
        if UIApplication.shared.isIdleTimerDisabled, idle >= PowerMonitor.shared.policy.keepAwakeLimit {
            ScreenAwake.update()
        }
    }
}

/// A layout being made or changed in the editor.
struct LayoutDraft: Identifiable {
    var layout: ScreenLayout
    var isNew: Bool
    var id: UUID { layout.id }
}

/// Keeps the screen on only while a screen that needs it is visible, the app is active and a
/// Mac is connected, and only until it has been left alone for `PowerPolicy.keepAwakeLimit`.
@MainActor
enum ScreenAwake {
    static var sceneActive = false
    /// Held on except that nobody touched it for too long; the next touch holds it on again.
    private(set) static var releasedForIdle = false

    static func update() {
        let router = AppRouter.shared
        let settings = PhoneSettings.shared
        let policy = PowerMonitor.shared.policy
        var inputs = KeepAwakeInputs(
            sceneActive: sceneActive, enabled: settings.hasOnboarded && settings.keepScreenAwake,
            screenNeedsIt: router.dims,
            coveredBySheet: router.showSettings || router.showPairing || router.showClipboard || router.showSetup
                || router.showLayouts || router.layoutDraft != nil,
            connected: true, idle: 0)
        // Dimming runs whenever the screen would be held on apart from the link and idle time,
        // so a dimmed screen stays dimmed until a touch or until the phone locks.
        let dims = policy.keepsScreenAwake(inputs)
        if dims { router.startDimTimer() } else { router.stopDimTimer() }
        inputs.connected = MacSession.shared.isConnected
        inputs.idle = router.idleTime
        // StandBy screens keep the screen on by their own rules (StandByMode.swift), without dimming.
        let standBy = sceneActive && StandByMonitor.shared.power.keepsScreenOn && !inputs.coveredBySheet
        let wanted = policy.keepsScreenAwake(inputs) || standBy
        if UIApplication.shared.isIdleTimerDisabled != wanted {
            UIApplication.shared.isIdleTimerDisabled = wanted
        }
        releasedForIdle = dims && inputs.connected && !wanted
    }
}
