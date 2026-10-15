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
    @Published var capabilities: SynthCapabilities
    @Published var settings: TrackpadSettings
    @Published var accessibilityTrusted = true
    /// Music apps the user refused Automation for (e.g. "Spotify").
    @Published var automationDenied: [String] = []
    @Published var pairingURL: URL?
    @Published var lastError: String?
    @Published var dock = MacDockState(hidden: false, hideWhileConnected: false)
    @Published var launchAtLogin = false
    @Published var launchNeedsApproval = false
    @Published var allowShellButtons = false
    /// Glasspad stopped listening on purpose: the phone cannot connect until resumed.
    @Published var isPaused = false

    let macName: String
    let macros: MacroCoordinator
    let actions: Actions

    /// Everything a button can do. Plain closures so the harness can pass no-ops.
    struct Actions {
        var beginPairing: @MainActor () -> Void = {}
        var cancelPairing: @MainActor () -> Void = {}
        var forget: @MainActor (StoredPhone) -> Void = { _ in }
        var requestAccessibility: @MainActor () -> Void = {}
        var openAutomationSettings: @MainActor () -> Void = {}
        var recheckPermissions: @MainActor () -> Void = {}
        var setDockHidden: @MainActor (Bool) -> Void = { _ in }
        var setHideDockWhileConnected: @MainActor (Bool) -> Void = { _ in }
        var setLaunchAtLogin: @MainActor (Bool) -> Void = { _ in }
        var setPaused: @MainActor (Bool) -> Void = { _ in }
        var setAllowShellButtons: @MainActor (Bool) -> Void = { _ in }
        var showActionsFile: @MainActor () -> Void = {}
        var showMacrosFolder: @MainActor () -> Void = {}
        var openConsole: @MainActor () -> Void = {}
        var openTrackpadSettings: @MainActor () -> Void = {}
        var openLoginItems: @MainActor () -> Void = {}
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

    /// Permissions that stop something from working. Empty when all is well.
    var missingPermissions: [MissingPermission] {
        var out: [MissingPermission] = []
        if !accessibilityTrusted { out.append(.accessibility) }
        out += automationDenied.map { .automation($0) }
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
    case automation(String)

    var id: String {
        switch self {
        case .accessibility: "accessibility"
        case .automation(let app): "automation.\(app)"
        }
    }
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
        a.recheckPermissions = { controller.refreshAccessibility() }
        a.setDockHidden = { hider.setManual($0) }
        a.setHideDockWhileConnected = { hider.setHideWhileConnected($0) }
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
        a.openTrackpadSettings = { SystemSettings.openTrackpad() }
        a.openLoginItems = { SystemSettings.openLoginItems() }
        a.refresh = {
            controller.refreshAccessibility()
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

        controller.$linkState.assign(to: &model.$link)
        controller.$stats.assign(to: &model.$stats)
        controller.$phones.assign(to: &model.$phones)
        controller.$connectedPhoneName.assign(to: &model.$connectedPhoneName)
        controller.$capabilities.assign(to: &model.$capabilities)
        controller.$settings.assign(to: &model.$settings)
        controller.$accessibilityTrusted.assign(to: &model.$accessibilityTrusted)
        controller.$pairingURL.assign(to: &model.$pairingURL)
        controller.$lastError.assign(to: &model.$lastError)
        hider.$published.assign(to: &model.$dock)
        media.$deniedApps.assign(to: &model.$automationDenied)
        return model
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
