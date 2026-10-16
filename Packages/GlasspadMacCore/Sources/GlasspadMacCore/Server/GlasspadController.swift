import AppKit
import ApplicationServices
import Combine
import GlasspadKit

/// Everything the menu bar app needs, wired together: transport (GlasspadServer), pairing
/// store, prefs watcher, touch pipeline (recognizer + synth) and the mode handlers.
@MainActor
public final class GlasspadController: ObservableObject {
    @Published public private(set) var linkState: LinkState = .idle
    @Published public private(set) var stats = LinkStats()
    @Published public private(set) var phones: [StoredPhone] = []
    @Published public private(set) var connectedPhoneName: String?
    @Published public private(set) var capabilities: SynthCapabilities
    @Published public private(set) var settings: TrackpadSettings
    @Published public private(set) var accessibilityTrusted = false
    /// The pairing link shown as a QR code, while pairing is open (the same as `pairingPhase.url`).
    @Published public private(set) var pairingURL: URL?
    /// Waiting for a scan, paired, expired or failed.
    @Published public private(set) var pairingPhase: PairingPhase = .idle
    /// Spotify and Music control (optional).
    @Published public private(set) var automation: AutomationState = .notDetermined
    @Published public private(set) var lastError: String?

    public let pairing: PairingStore
    public let macName: String
    /// Macros: the engine, the Settings editor's data, and the phone's Macros screen.
    public let macros: MacroCoordinator
    private let server: GlasspadServer
    private let watcher: TrackpadPrefsWatcher
    private let pipeline: TouchPipeline
    private let modes: ModeRouter
    private var statusTimer: Timer?
    private var bridge: LinkBridge?
    private var flow = PairingFlow()
    private var reporter = MacStatusReporter()
    private var deniedWatch: AnyCancellable?
    private var axMonitor: AccessibilityMonitor

    /// `accessibilityCheck` reads the Accessibility permission (tests inject their own).
    public init(pairing: PairingStore = PairingStore(), macName: String = Host.current().localizedName ?? "Mac",
                accessibilityCheck: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() }) {
        self.pairing = pairing
        self.axMonitor = AccessibilityMonitor(check: accessibilityCheck)
        self.macName = macName
        let caps = SynthCapabilities.selfCheck()
        let poster = LiveEventPoster()
        let watcher = TrackpadPrefsWatcher()
        self.watcher = watcher
        self.capabilities = caps
        let synth = EventSynthesizer(poster: poster, settings: watcher.settings, capabilities: caps)
        var initial = watcher.settings
        initial.tuning = Self.savedTuning()
        self.settings = initial
        self.pipeline = TouchPipeline(settings: initial, synth: synth, frameClock: DisplayFrameClock())
        self.modes = ModeRouter(poster: poster)
        self.macros = MacroCoordinator.live(poster: poster)
        self.modes.macros = macros
        let store = pairing
        self.server = GlasspadServer(macID: pairing.macID, macName: macName) { phoneID in
            store.storedKey(for: phoneID)
        }
        self.phones = pairing.phones
        self.accessibilityTrusted = axMonitor.trusted
    }

    public func start() {
        let bridge = LinkBridge(owner: self)
        self.bridge = bridge
        server.delegate = bridge
        server.onPaired = { [weak self] phone in
            MainActor.assumeIsolated { self?.paired(phone) }
        }
        pipeline.setDisplayWidth(Double(NSScreen.screens.first?.frame.width ?? 0))
        modes.send = { [weak self] message in self?.server.send(.mode(message)) }
        macros.send = { [weak self] message in self?.server.send(.mode(.macro(message))) }
        server.onSessionStarted = { [weak self] _ in
            MainActor.assumeIsolated { self?.sessionStarted() }
        }
        macros.start()
        watcher.onChange = { [weak self] s in self?.settingsChanged(s) }
        watcher.start()
        do {
            try server.start()
        } catch {
            lastError = "Could not start listening: \(error.localizedDescription)"
        }
        refreshAccessibility()
        deniedWatch = MediaPermissions.shared.$deniedApps
            .removeDuplicates()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshAutomation() }
            }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatus() }
        }
        RunLoop.main.add(t, forMode: .common)
        statusTimer = t
    }

    public func stop() {
        statusTimer?.invalidate()
        watcher.stop()
        pipeline.cancelAll()
        macros.stop()
        server.stop()
    }

    // MARK: Pairing

    /// Shows a fresh code (also "Show a New Code" after one expired or failed).
    public func beginPairing() {
        let payload = pairing.beginPairing(macName: macName)
        server.pendingPairKey = payload.pairKey
        flow.begin(url: payload.url, now: Date())
        publishPairing()
    }

    /// Cancel a code on screen, or dismiss the result of the last attempt.
    public func cancelPairing() {
        disarmPairingKey()
        flow.reset()
        publishPairing()
    }

    private func disarmPairingKey() {
        pairing.cancelPairing()
        server.pendingPairKey = nil
    }

    private func publishPairing() {
        if pairingPhase != flow.phase { pairingPhase = flow.phase }
        if pairingURL != flow.phase.url { pairingURL = flow.phase.url }
    }

    public func revoke(_ phone: StoredPhone) {
        try? pairing.revoke(phone.phoneID)
        if server.connectedPhone?.phoneID == phone.phoneID { server.disconnect(reason: "revoked") }
        phones = pairing.phones
    }

    private func paired(_ phone: PairedPhone) {
        do {
            try pairing.save(phoneID: phone.phoneID, phoneName: phone.phoneName, pairKey: phone.pairKey)
            flow.completed(phoneName: phone.phoneName)
        } catch {
            flow.failed("This Mac could not save the pairing to the Keychain.")
        }
        disarmPairingKey()
        publishPairing()
        phones = pairing.phones
    }

    // MARK: Permissions

    /// Re-reads Accessibility both ways (it can be turned off while Glasspad runs) and tells
    /// the phone when it changed.
    public func refreshAccessibility() {
        if let changed = axMonitor.poll() { accessibilityTrusted = changed }
        reportStatus()
    }

    /// Shows the system prompt that adds Glasspad to the Accessibility list.
    public func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString   // kAXTrustedCheckOptionPrompt
        let trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        axMonitor.set(trusted)
        accessibilityTrusted = trusted
        reportStatus()
    }

    /// Reads Spotify and Music control without asking.
    public func refreshAutomation() {
        let state = AutomationProbe.current(deniedApps: MediaPermissions.shared.deniedApps)
        if state != automation { automation = state }
        reportStatus()
    }

    /// Asks macOS for Spotify and Music control (only a running player can be asked).
    /// Returns false when neither was running, so nothing was asked.
    @discardableResult
    public func requestAutomation() async -> Bool {
        let result = await AutomationProbe.request()
        refreshAutomation()
        return result.askedAny
    }

    /// What the phone is told about this Mac (`ControlMessage.macStatus`).
    public var macStatus: MacStatus {
        MacStatus(accessibilityTrusted: accessibilityTrusted, automationMedia: automation, macName: macName)
    }

    private func reportStatus(newSession: Bool = false) {
        guard newSession || server.connectedPhone != nil else { return }
        if let status = reporter.update(macStatus, newSession: newSession) { server.send(.macStatus(status)) }
    }

    public nonisolated static let accessibilitySettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    // MARK: Link callbacks

    /// A phone's session became active: a fresh connect, or a phone replacing another one (the
    /// link state can stay `connected` through that, so this is the reliable signal).
    private func sessionStarted() {
        // Anything the previous phone was holding (a drag, momentum) ends now.
        pipeline.cancelAll()
        modes.sessionEnded()
        connectedPhoneName = server.connectedPhone?.phoneName
        server.send(.settings(settings))
        refreshAutomation()
        reportStatus(newSession: true)
        macros.sessionStarted()
    }

    fileprivate func linkStateChanged(_ state: LinkState) {
        let wasConnected = { if case .connected = linkState { return true } else { return false } }()
        linkState = state
        if case .connected = state {
            connectedPhoneName = server.connectedPhone?.phoneName
        } else {
            connectedPhoneName = nil
            reporter.sessionEnded()
            if wasConnected {
                pipeline.cancelAll()
                modes.sessionEnded()
            }
        }
    }

    fileprivate func received(_ message: ControlMessage) {
        switch message {
        case .mode(let m): modes.handle(m)
        case .settings(let fromPhone): phoneTuningChanged(fromPhone.tuning.clamped)
        default: break
        }
    }

    // MARK: Phone tuning

    private static let tuningKey = "phoneTrackpadTuning"

    static func savedTuning() -> TrackpadTuning {
        guard let data = UserDefaults.standard.data(forKey: tuningKey),
              let t = try? JSONDecoder().decode(TrackpadTuning.self, from: data) else { return .default }
        return t.clamped
    }

    /// The phone sent its feel settings (pointer speed, acceleration, scroll, momentum, haptics).
    /// The Mac keeps them with its own trackpad prefs and echoes the merged settings back.
    private func phoneTuningChanged(_ tuning: TrackpadTuning) {
        guard tuning != settings.tuning else { return }
        if let data = try? JSONEncoder().encode(tuning) { UserDefaults.standard.set(data, forKey: Self.tuningKey) }
        var s = settings
        s.tuning = tuning
        settings = s
        pipeline.settings = s
        server.send(.settings(s))
    }

    fileprivate func received(_ frame: TouchFrame) {
        guard accessibilityTrusted else { return }
        pipeline.process(frame)
    }

    private func settingsChanged(_ new: TrackpadSettings) {
        var s = new
        s.tuning = settings.tuning      // the phone owns tuning; the Mac prefs never carry it
        settings = s
        pipeline.settings = s
        server.send(.settings(s))
    }

    private func refreshStatus() {
        stats = server.stats
        // Every second, so turning Accessibility off in System Settings reaches the phone too.
        refreshAccessibility()
        if flow.tick(now: Date()) {
            disarmPairingKey()
            publishPairing()
        }
    }
}

/// Non-isolated delegate object; the server delivers on the main queue.
private final class LinkBridge: GlasspadLinkDelegate {
    weak var owner: GlasspadController?
    init(owner: GlasspadController) { self.owner = owner }

    func link(didChangeState state: LinkState) {
        let o = owner
        MainActor.assumeIsolated { o?.linkStateChanged(state) }
    }

    func link(didReceive message: ControlMessage) {
        let o = owner
        MainActor.assumeIsolated { o?.received(message) }
    }

    func link(didReceive frame: TouchFrame) {
        let o = owner
        MainActor.assumeIsolated { o?.received(frame) }
    }
}
