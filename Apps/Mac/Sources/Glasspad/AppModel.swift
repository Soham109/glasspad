import AppKit
import Combine
import GlasspadKit
import GlasspadMacCore
import GlasspadMacros
import SwiftUI

/// What the menu bar popover and the Settings window show, and what their buttons do.
///
/// Views never talk to `GlasspadController` directly: they read this model and call its
/// `actions`. The app builds it with `live(_:)`, which mirrors the controller and the shared
/// helpers; the snapshot harness (Apps/Mac/Tests) builds it with fixed values and no-op
/// actions, so every screen can be drawn without starting a server or touching the system.
@MainActor
final class AppModel: ObservableObject {
    @Published var link: LinkState = .idle
    @Published var stats = LinkStats()
    @Published var phones: [StoredPhone] = []
    @Published var connectedPhoneName: String?
    /// The connected iPhone's battery, when it reports one.
    @Published var phoneBattery: PhoneBattery?
    @Published var capabilities: SynthCapabilities
    @Published var settings: TrackpadSettings
    @Published var accessibilityTrusted = true
    /// Music apps the user refused Automation for (e.g. "Spotify").
    @Published var automationDenied: [String] = []
    /// Spotify and Music control, as the phone is told it.
    @Published var automation: AutomationState = .notDetermined
    /// Shown under the Spotify and Music row after asking found no player to ask.
    @Published var automationHint: String?
    /// Waiting for a scan, paired, expired or failed.
    @Published var pairing: PairingPhase = .idle
    @Published var lastError: String?
    @Published var dock = MacDockState(hidden: false, hideWhileConnected: false)
    @Published var launchAtLogin = false
    @Published var launchNeedsApproval = false
    @Published var allowShellButtons = false
    /// Glasspad stopped listening on purpose: the phone cannot connect until resumed.
    @Published var isPaused = false
    /// Why the last clipboard transfer did not happen (Advanced > Diagnostics).
    @Published var clipboardRefusal: String?
    /// The user's per-gesture choices (Trackpad > If a Gesture Stops Working).
    @Published var gesturePreferences = GesturePreferences()
    /// The iPhone install and its renewal (Settings > iPhone). Nil when none was recorded.
    @Published var phoneInstall: PhoneInstallStatus?

    let macName: String
    let macros: MacroCoordinator
    let actions: Actions
    private var watchers: [AnyCancellable] = []

    /// Everything a button can do. Plain closures so the harness can pass no-ops.
    struct Actions {
        var beginPairing: @MainActor () -> Void = {}
        /// Cancels a code, or dismisses a pairing result.
        var cancelPairing: @MainActor () -> Void = {}
        /// Puts the pairing link on the pasteboard (for pasting on the phone, or AirDrop).
        var copyPairingLink: @MainActor (URL) -> Void = { _ in }
        /// Asks for Spotify and Music control; sets `automationHint` when nothing could be asked.
        var requestAutomation: @MainActor () -> Void = {}
        var forget: @MainActor (StoredPhone) -> Void = { _ in }
        var requestAccessibility: @MainActor () -> Void = {}
        var openAutomationSettings: @MainActor () -> Void = {}
        var recheckPermissions: @MainActor () -> Void = {}
        /// Never, While Connected or Always, as one change.
        var setDockHiding: @MainActor (MacDockHiding) -> Void = { _ in }
        var setLaunchAtLogin: @MainActor (Bool) -> Void = { _ in }
        var setPaused: @MainActor (Bool) -> Void = { _ in }
        var setAllowShellButtons: @MainActor (Bool) -> Void = { _ in }
        /// Applies at once; no restart.
        var setGesturePreference: @MainActor (GesturePreference, SynthGesture) -> Void = { _, _ in }
        var showActionsFile: @MainActor () -> Void = {}
        var showMacrosFolder: @MainActor () -> Void = {}
        var openConsole: @MainActor () -> Void = {}
        var openTrackpadSettings: @MainActor () -> Void = {}
        var openLoginItems: @MainActor () -> Void = {}
        /// Reads the iPhone install's state into `phoneInstall`, off the main thread.
        var loadPhoneInstall: @MainActor () -> Void = {}
        var showRenewalLog: @MainActor () -> Void = {}
        /// Called when the popover or a Settings pane appears, to pick up outside changes.
        var refresh: @MainActor () -> Void = {}
        var quit: @MainActor () -> Void = {}
    }

    init(macName: String, macros: MacroCoordinator, capabilities: SynthCapabilities,
         settings: TrackpadSettings, actions: Actions) {
        self.macName = macName
        self.macros = macros
        self.capabilities = capabilities
        self.settings = settings
        self.actions = actions
    }

    // MARK: Derived

    var isConnected: Bool { link.isConnected && !isPaused }

    /// The link in the QR code, while it can be scanned.
    var pairingURL: URL? { pairing.url }

    /// Permissions that stop something from working. Empty when all is well.
    var missingPermissions: [MissingPermission] {
        var out: [MissingPermission] = []
        // Accessibility first: nothing works without it. Spotify and Music is optional, so it
        // only shows here once it was refused.
        if !accessibilityTrusted { out.append(.accessibility) }
        if automation == .denied { out.append(.automation) }
        return out
    }

    var signal: SignalQuality? {
        guard isConnected else { return nil }
        return SignalQuality(medianMs: stats.rttMedianMs, p95Ms: stats.rttP95Ms)
    }
}

/// Lets the live actions reach the model they belong to without a retain cycle.
@MainActor
private final class ModelRef {
    weak var model: AppModel?
}

enum MissingPermission: Hashable, Identifiable {
    case accessibility
    /// Spotify and Music control (optional).
    case automation

    var id: String {
        switch self {
        case .accessibility: "accessibility"
        case .automation: "automation"
        }
    }

    var isRequired: Bool { self == .accessibility }
}

// MARK: - Live wiring

extension AppModel {
    /// The app's model: mirrors the controller, the Dock hider, Automation state and login item.
    static func live(_ controller: GlasspadController) -> AppModel {
        let login = LaunchAtLogin()
        let hider = MacDockHider.shared
        let media = MediaPermissions.shared
        let ref = ModelRef()

        var a = Actions()
        a.beginPairing = { controller.beginPairing() }
        a.cancelPairing = { controller.cancelPairing() }
        a.forget = { controller.revoke($0) }
        a.requestAccessibility = {
            controller.requestAccessibility()
            SystemSettings.openAccessibility()
        }
        a.openAutomationSettings = { media.openAutomationSettings() }
        // Marked private and short-lived for clipboard history apps, and cleared when pairing ends.
        let linkBoard = PairingLinkPasteboard()
        a.copyPairingLink = { url in linkBoard.copy(url) }
        controller.approvalPrompt = { name, timeout, answer in
            ApprovalPrompt.ask(phoneName: name, timeout: timeout, answer: answer)
        }
        a.requestAutomation = {
            ref.model?.automationHint = nil
            Task { @MainActor in
                let asked = await controller.requestAutomation()
                ref.model?.automationHint = asked ? nil : PermissionCopy.openPlayerFirst
            }
        }
        a.recheckPermissions = { controller.refreshAccessibility() }
        a.setDockHiding = { hider.set($0.state) }
        a.setLaunchAtLogin = { on in
            login.set(on)
            ref.model?.launchAtLogin = login.isEnabled
            ref.model?.launchNeedsApproval = login.needsApproval
        }
        a.setPaused = { on in
            guard let model = ref.model, model.isPaused != on else { return }
            if on {
                controller.cancelPairing()
                controller.stop()
            } else {
                controller.start()
            }
            model.isPaused = on
        }
        a.setAllowShellButtons = { on in
            var cfg = DeckConfig.load()
            cfg.allowShellCommands = on
            try? cfg.save()
            ref.model?.allowShellButtons = DeckConfig.load().allowShellCommands
        }
        a.showActionsFile = {
            let url = DeckConfig.defaultURL()
            if !FileManager.default.fileExists(atPath: url.path) { try? DeckConfig.load().save() }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        a.showMacrosFolder = {
            let url = MacroStore.defaultDirectory
            if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                NSWorkspace.shared.open(MacroStore.defaultSupportDirectory)
            }
        }
        a.openConsole = {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Console") {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
        }
        a.setGesturePreference = { controller.setGesturePreference($0, for: $1) }
        a.openTrackpadSettings = { SystemSettings.openTrackpad() }
        a.openLoginItems = { SystemSettings.openLoginItems() }
        a.loadPhoneInstall = {
            Task.detached(priority: .utility) {
                let status = PhoneInstallStatus.load()
                await MainActor.run { if ref.model?.phoneInstall != status { ref.model?.phoneInstall = status } }
            }
        }
        a.showRenewalLog = {
            let log = PhoneInstallStatus.Paths().log
            if FileManager.default.fileExists(atPath: log.path) {
                NSWorkspace.shared.open(log)
            } else {
                NSWorkspace.shared.open(log.deletingLastPathComponent())
            }
        }
        a.refresh = {
            controller.refreshAccessibility()
            controller.refreshAutomation()
            login.refresh()
            ref.model?.launchAtLogin = login.isEnabled
            ref.model?.launchNeedsApproval = login.needsApproval
        }
        a.quit = { NSApp.terminate(nil) }

        let model = AppModel(macName: controller.macName, macros: controller.macros,
                             capabilities: controller.capabilities, settings: controller.settings, actions: a)
        ref.model = model
        model.launchAtLogin = login.isEnabled
        model.launchNeedsApproval = login.needsApproval
        model.allowShellButtons = DeckConfig.load().allowShellCommands

        // Only real changes reach the views: the controller republishes some values unchanged.
        // The round trip inside `.connected` changes with every ping; the views read it from
        // `stats`, so it is left out here and the views redraw on real state changes only.
        controller.$linkState.map(\.withoutRoundTrip).removeDuplicates().assign(to: &model.$link)
        controller.$stats.removeDuplicates().assign(to: &model.$stats)
        controller.$phones.removeDuplicates().assign(to: &model.$phones)
        controller.$connectedPhoneName.removeDuplicates().assign(to: &model.$connectedPhoneName)
        controller.$phoneBattery.removeDuplicates().assign(to: &model.$phoneBattery)
        controller.$capabilities.removeDuplicates().assign(to: &model.$capabilities)
        controller.$settings.removeDuplicates().assign(to: &model.$settings)
        controller.$accessibilityTrusted.removeDuplicates().assign(to: &model.$accessibilityTrusted)
        controller.$pairingPhase.removeDuplicates().assign(to: &model.$pairing)
        model.watchers.append(controller.$pairingPhase.map { $0.url == nil }.removeDuplicates().sink { ended in
            if ended { MainActor.assumeIsolated { linkBoard.clear() } }
        })
        controller.$automation.removeDuplicates().assign(to: &model.$automation)
        controller.$lastError.removeDuplicates().assign(to: &model.$lastError)
        controller.$clipboardRefusal.removeDuplicates().assign(to: &model.$clipboardRefusal)
        controller.$gesturePreferences.removeDuplicates().assign(to: &model.$gesturePreferences)
        hider.$published.removeDuplicates().assign(to: &model.$dock)
        media.$deniedApps.removeDuplicates().assign(to: &model.$automationDenied)
        model.recordPhoneSessions(controller)
        return model
    }

    /// Keeps phone-session.json in step with the link, so the renewal script can tell an app
    /// that is only suspended on the iPhone from one in use. Small writes, kept off the main thread.
    private func recordPhoneSessions(_ controller: GlasspadController) {
        let file = PhoneSessionFile()
        let queue = DispatchQueue(label: "glasspad.phone-session", qos: .utility)
        watchers.append(controller.$linkState.map(\.isConnected).removeDuplicates().sink { active in
            queue.async { file.record(active: active) }
        })
        // Quitting ends any session; written before the app goes so it is not left marked active.
        watchers.append(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification).sink { _ in
            queue.sync { file.record(active: false) }
        })
    }
}

// MARK: - Signal quality

/// The link's round trip time in words, so the main view never shows milliseconds.
enum SignalQuality: Equatable {
    case excellent, good, fair, weak, measuring

    init(medianMs: Double?, p95Ms: Double?) {
        guard let m = medianMs else { self = .measuring; return }
        // The slow tail matters more for feel than the middle, so it can pull the grade down.
        let worst = max(m, (p95Ms ?? m) / 2)
        switch worst {
        case ..<8: self = .excellent
        case ..<20: self = .good
        case ..<45: self = .fair
        default: self = .weak
        }
    }

    var title: String {
        switch self {
        case .excellent: "Excellent"
        case .good: "Good"
        case .fair: "Fair"
        case .weak: "Weak"
        case .measuring: "Checking"
        }
    }

    var advice: String? {
        switch self {
        case .fair: "Moving nearer your router helps."
        case .weak: "The pointer may lag. Move nearer your router."
        default: nil
        }
    }
}
