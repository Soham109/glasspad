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
    /// The connected iPhone's battery, once it reports one (`ControlMessage.phoneStatus`).
    @Published public private(set) var phoneBattery: PhoneBattery?
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
    /// Why the last clipboard transfer did not happen (`ClipboardMode.lastRefusal`).
    @Published public private(set) var clipboardRefusal: String?
    /// The user's per-gesture choices (Settings > Trackpad, "If a gesture stops working").
    @Published public private(set) var gesturePreferences: GesturePreferences

    public let pairing: PairingStore
    public let macName: String
    /// Macros: the engine, the Settings editor's data, and the phone's Macros screen.
    public let macros: MacroCoordinator
    private let server: GlasspadServer
    private let watcher: TrackpadPrefsWatcher
    private let pipeline: TouchPipeline
    private let modes: ModeRouter
    /// The mode handlers, for the live check (which drives them without starting the server).
    public var modeRouter: ModeRouter { modes }
    private var statusTimer: Timer?
    private var bridge: LinkBridge?
    private var flow = PairingFlow()
    private var reporter = MacStatusReporter()
    private var deniedWatch: AnyCancellable?
    private var axMonitor: AccessibilityMonitor
    /// What the launch self-check found, before the user's choices are applied.
    private let detectedCapabilities: SynthCapabilities
    private let preferencesDefaults: UserDefaults

    /// `accessibilityCheck` reads the Accessibility permission (tests inject their own).
    /// `preferences` holds the per-gesture choices (tests pass their own suite).
    public init(pairing: PairingStore = PairingStore(), macName: String = Host.current().localizedName ?? "Mac",
                accessibilityCheck: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
                preferences: UserDefaults = .standard) {
        self.pairing = pairing
        self.axMonitor = AccessibilityMonitor(check: accessibilityCheck)
        self.macName = macName
        self.preferencesDefaults = preferences
        let detected = SynthCapabilities.select(probe: SynthCapabilities.probeNative)
        let prefs = GesturePreferences.load(from: preferences)
        self.detectedCapabilities = detected
        self.gesturePreferences = prefs
        let caps = detected.applying(prefs)
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
        modes.clipboard.onRefusalChange = { [weak self] reason in self?.clipboardRefusal = reason }
    }

    // MARK: Gestures

    /// Sets how one gesture reaches the Mac and applies it at once, without a restart. Saved in
    /// the app's preferences; a choice the gesture cannot honour is stored as Automatic.
    public func setGesturePreference(_ preference: GesturePreference, for gesture: SynthGesture) {
        var prefs = gesturePreferences
        prefs.set(preference, for: gesture)
        guard prefs != gesturePreferences else { return }
        prefs.save(to: preferencesDefaults)
        gesturePreferences = prefs
        let caps = detectedCapabilities.applying(prefs)
        pipeline.synth.updateCapabilities(caps)
        capabilities = caps
        GPLog.log("gestures: \(gesture.rawValue) set to \(prefs.preference(for: gesture).rawValue), now \(caps.mode(for: gesture).rawValue)")
    }

    /// What the launch self-check found for a gesture, before the user's choice.
    public func detectedMode(for gesture: SynthGesture) -> SynthMode { detectedCapabilities.mode(for: gesture) }

    /// The paths the synthesizer is using right now (tests check the live apply with it).
    var synthCapabilities: SynthCapabilities { pipeline.synth.capabilities }

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
        scheduleStatus()
    }

    /// Every second while a phone is connected or a pairing code is up (the phone sees
    /// Accessibility change, the code runs out on time); every 5 s otherwise.
    nonisolated static func statusInterval(phoneConnected: Bool, pairing: Bool) -> TimeInterval {
        phoneConnected || pairing ? 1 : 5
    }

    /// A fifth of the interval: the code's countdown and a permission change still land on time.
    nonisolated static func statusTolerance(_ interval: TimeInterval) -> TimeInterval { interval / 5 }

    private var statusInterval: TimeInterval {
        let connected = if case .connected = linkState { true } else { false }
        return Self.statusInterval(phoneConnected: connected, pairing: flow.phase.url != nil)
    }

    /// Starts the status timer, or restarts it when its interval should change.
    private func scheduleStatus() {
        let interval = statusInterval
        if let statusTimer, statusTimer.isValid, statusTimer.timeInterval == interval { return }
        statusTimer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatus() }
        }
        // Lets macOS fire it together with other work instead of waking the Mac just for it.
        t.tolerance = Self.statusTolerance(interval)
        RunLoop.main.add(t, forMode: .common)
        statusTimer = t
    }

    public func stop() {
        statusTimer?.invalidate()
        statusTimer = nil
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
        if statusTimer != nil { scheduleStatus() }
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
    private var automationProbeInFlight = false

    /// Never blocks the main thread (see `AutomationProbe.current`); the answer lands later.
    public func refreshAutomation() {
        guard !automationProbeInFlight else { return }
        automationProbeInFlight = true
        let denied = MediaPermissions.shared.deniedApps
        Task { @MainActor [weak self] in
            let state = await AutomationProbe.current(deniedApps: denied)
            guard let self else { return }
            self.automationProbeInFlight = false
            if state != self.automation { self.automation = state }
            self.reportStatus()
        }
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
        // `ModeRouter` reads `modesShown`, so the phone's layouts need not poll the Dock.
        MacStatus(accessibilityTrusted: accessibilityTrusted, automationMedia: automation, macName: macName,
                  followsAllPanes: true)
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
        // The new phone reports its own battery right after connecting.
        phoneBattery = nil
        // With no phone the trackpad prefs are not polled, so read them before sending.
        watcher.refresh()
        server.send(.settings(settings))
        refreshAutomation()
        reportStatus(newSession: true)
        macros.sessionStarted()
    }

    fileprivate func linkStateChanged(_ state: LinkState) {
        let wasConnected = { if case .connected = linkState { return true } else { return false } }()
        linkState = state
        let connected = if case .connected = state { true } else { false }
        watcher.setPhoneConnected(connected)
        if statusTimer != nil { scheduleStatus() }
        if case .connected = state {
            connectedPhoneName = server.connectedPhone?.phoneName
        } else {
            connectedPhoneName = nil
            phoneBattery = nil
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
        case .phoneStatus(let status): phoneBattery = status.battery
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

    private var lastDropLog: TimeInterval = 0

    fileprivate func received(_ frame: TouchFrame) {
        guard accessibilityTrusted else {
            // Touches are dropped while macOS denies Accessibility; say so (at most every 5 s)
            // so a stale permission is visible in the log instead of a silent dead trackpad.
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastDropLog > 5 {
                lastDropLog = now
                GPLog.log("touches dropped: Accessibility is off for this copy of Glasspad (AXIsProcessTrusted \(AXIsProcessTrusted()))")
            }
            return
        }
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
        // Only a real change is published: every publish redraws whatever observes the model.
        let fresh = server.stats
        if fresh != stats { stats = fresh }
        // Every second, so turning Accessibility off in System Settings reaches the phone too.
        refreshAccessibility()
        if flow.tick(now: Date()) {
            disarmPairingKey()
            publishPairing()
        }
        scheduleStatus()
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
