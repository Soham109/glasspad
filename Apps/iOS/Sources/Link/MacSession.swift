import Foundation
import GlasspadKit
import Observation
import UIKit

/// The phone's one connection to its selected Mac, and everything the Mac has told it.
/// Owns the `GlasspadClient`; views and App Intents talk to the Mac only through here.
@MainActor
@Observable
final class MacSession {
    static let shared = MacSession()

    // MARK: Link

    private(set) var state: LinkState = .idle
    /// The Mac's trackpad preferences. Until the first connect, the last ones seen (or macOS defaults).
    private(set) var trackpadSettings: TrackpadSettings
    /// True once a Mac has sent its settings at least once.
    private(set) var hasMacSettings: Bool
    /// `thermalState >= .serious`: haptics and heartbeats are off until the phone cools.
    private(set) var isWarm = false

    var isConnected: Bool { if case .connected = state { true } else { false } }
    var macName: String? { PairingStore.shared.selected?.name }

    // MARK: Mode data

    private(set) var dockApps: [DockApp] = []
    let icons = IconCache()
    private(set) var media: MediaState?
    private(set) var mediaReceivedAt: Date?
    private(set) var deckButtons: [DeckButton]?
    private(set) var deckPending: Set<UUID> = []
    private(set) var deckOutcomes: [UUID: DeckOutcome] = [:]
    private(set) var deckFailure: DeckFailure?
    private(set) var clipboardPulled: PulledClipboard?
    private(set) var clipboardPullPending = false

    private(set) var macroProfile: ActiveProfileInfo?
    private(set) var allMacros: [MacroSummary]?
    /// The macro playing now, with its latest progress.
    private(set) var macroRunning: MacroProgress?
    private(set) var macroPendingID: UUID?
    private(set) var macroResult: MacroResult?
    private(set) var isRecordingMacro = false

    // MARK: Private

    @ObservationIgnored private var client: GlasspadClient?
    @ObservationIgnored private let bridge = LinkBridge()
    @ObservationIgnored private var foreground = false
    @ObservationIgnored private var backgroundUsers = 0
    @ObservationIgnored private var trackpadVisible = false
    @ObservationIgnored private var lastLocalHaptic: [HapticKind: TimeInterval] = [:]
    @ObservationIgnored private var stateWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    @ObservationIgnored private var laserOn = false
    @ObservationIgnored private var thermalObserver: NSObjectProtocol?

    private static let settingsKey = "lastMacSettings"
    private static let deckCacheKey = "deckButtonsCache"
    private static let macroCacheKey = "macrosCache"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(TrackpadSettings.self, from: data) {
            trackpadSettings = saved
            hasMacSettings = true
        } else {
            trackpadSettings = .macDefault
            hasMacSettings = false
        }
        if let data = UserDefaults.standard.data(forKey: Self.deckCacheKey) {
            deckButtons = try? JSONDecoder().decode([DeckButton].self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: Self.macroCacheKey) {
            allMacros = try? JSONDecoder().decode([MacroSummary].self, from: data)
        }
        bridge.session = self
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { MacSession.shared.updateThermal() }
        }
        updateThermal()
        refreshHapticStrength()
    }

    // MARK: Lifecycle

    /// The app came to the foreground or went to the background.
    func setForeground(_ active: Bool) {
        foreground = active
        if active {
            connectIfNeeded()
        } else {
            releaseBackgroundOrDisconnect()
        }
    }

    /// The trackpad surface appeared or disappeared. Heartbeats only run while it is visible.
    func setTrackpadVisible(_ visible: Bool) {
        trackpadVisible = visible
        applyHeartbeats()
        if visible { Haptics.shared.warmUp() } else { Haptics.shared.coolDown() }
    }

    func select(_ mac: PairedMac) {
        guard PairingStore.shared.selectedID != mac.macID || client == nil else { return }
        PairingStore.shared.selectedID = mac.macID
        reconnect()
    }

    func forget(_ mac: PairedMac) {
        let wasSelected = PairingStore.shared.selected?.macID == mac.macID
        PairingStore.shared.forget(mac)
        if wasSelected {
            resetModeData()
            reconnect()
        }
    }

    /// Drops the current connection and starts over (new Mac, new phone name).
    func reconnect() {
        disconnect()
        connectIfNeeded()
    }

    private func connectIfNeeded() {
        guard foreground || backgroundUsers > 0 else { return }
        guard let mac = PairingStore.shared.selected else {
            setState(.idle)
            return
        }
        if let client, client.pairing.macID == mac.macID,
           client.phoneName == PhoneSettings.shared.phoneName {
            if case .failed = client.state { client.connect() }
            return
        }
        disconnect()
        let new = GlasspadClient(phoneID: PairingStore.shared.phoneID.uuidString,
                                 phoneName: PhoneSettings.shared.phoneName,
                                 pairing: mac.payload)
        new.delegate = bridge
        client = new
        applyHeartbeats()
        new.connect()
    }

    private func disconnect() {
        if laserOn { laserOff() }
        client?.delegate = nil
        client?.disconnect()
        client = nil
        setState(.idle)
    }

    private func releaseBackgroundOrDisconnect() {
        guard !foreground, backgroundUsers == 0 else { return }
        disconnect()
    }

    // MARK: Sending

    /// One touch snapshot from the surface. Called for every sample, on the main thread.
    func send(frame: TouchFrame) {
        client?.send(frame: frame)
    }

    func send(_ message: ModeMessage) {
        client?.send(message: .mode(message))
    }

    func modeDidChange(to mode: AppMode) {
        if mode != .present, laserOn { laserOff() }
        send(.modeSelected(mode.wireMode))
    }

    func runDeck(_ id: UUID) {
        deckPending.insert(id)
        send(.deckRun(id: id))
        // If the Mac never answers (old Mac build, dropped link), stop the spinner.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            if self.deckPending.remove(id) != nil {
                self.showDeckFailure("Your Mac did not answer.")
            }
        }
    }

    func pullClipboard() {
        clipboardPullPending = true
        send(.clipboardPull)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            self.clipboardPullPending = false
        }
    }

    func laser(at point: CGPoint) {
        AppRouter.shared.noteActivity()
        if !laserOn {
            laserOn = true
            send(.presentLaser(on: true))
        }
        send(.presentLaserPosition(x: point.x, y: point.y))
    }

    func laserOff() {
        guard laserOn else { return }
        laserOn = false
        send(.presentLaser(on: false))
    }

    // MARK: Haptics and heat

    /// Strength = phone slider x the Mac's click firmness.
    func refreshHapticStrength() {
        let s = PhoneSettings.shared.hapticStrength * trackpadSettings.clickPressure.hapticScale
        Haptics.shared.strength = min(1, max(0, s))
    }

    /// The local recognizer just played this kind; the Mac's copy of the same cue is skipped.
    func noteLocalHaptic(_ kind: HapticKind) {
        lastLocalHaptic[kind] = ProcessInfo.processInfo.systemUptime
    }

    private func updateThermal() {
        let warm = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        isWarm = warm
        Haptics.shared.suspendedForHeat = warm
        applyHeartbeats()
    }

    private func applyHeartbeats() {
        client?.heartbeatsEnabled = trackpadVisible && !isWarm
    }

    // MARK: Receiving

    fileprivate func linkStateChanged(_ new: LinkState) {
        setState(new)
        if case .connected = new {
            send(.modeSelected(AppRouter.shared.mode.wireMode))
            // Refresh whatever the current screen shows.
            switch AppRouter.shared.mode {
            case .dock: send(.dockRequest)
            case .media: send(.mediaRequest)
            case .deck: send(.deckRequest)
            case .macros: send(.macro(.listMacros))
            default: break
            }
        }
    }

    fileprivate func received(_ message: ControlMessage) {
        switch message {
        case .settings(let settings):
            trackpadSettings = settings
            hasMacSettings = true
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: Self.settingsKey)
            }
            refreshHapticStrength()
        case .haptic(let kind):
            let now = ProcessInfo.processInfo.systemUptime
            if let local = lastLocalHaptic[kind], now - local < 0.25 { return }
            Haptics.shared.play(HapticCue(kind))
        case .mode(let mode):
            received(mode)
        case .bye, .ping, .pong:
            break
        }
    }

    private func received(_ message: ModeMessage) {
        switch message {
        case .dockList(let apps):
            for app in apps {
                if let png = app.iconPNG { icons.store(png, for: app.bundleID) }
            }
            dockApps = apps.map { DockApp(bundleID: $0.bundleID, name: $0.name, iconPNG: nil, running: $0.running, active: $0.active) }
        case .mediaState(let state):
            media = state
            mediaReceivedAt = Date()
        case .deckButtons(let buttons):
            deckButtons = buttons
            if let data = try? JSONEncoder().encode(buttons) {
                UserDefaults.standard.set(data, forKey: Self.deckCacheKey)
            }
        case .deckResult(let id, let ok, let message):
            deckPending.remove(id)
            let outcome = DeckOutcome(ok: ok, message: message)
            deckOutcomes[id] = outcome
            if ok {
                Haptics.shared.play(.detent)
            } else {
                Haptics.shared.play(.error)
                showDeckFailure(message ?? "That button did not work.")
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.6))
                if self.deckOutcomes[id] == outcome { self.deckOutcomes[id] = nil }
            }
        case .clipboardContent(let content):
            clipboardPullPending = false
            clipboardPulled = PulledClipboard(content: content)
            switch content {
            case .text(let text)?: UIPasteboard.general.string = text
            case .imagePNG(let data)?: if let image = UIImage(data: data) { UIPasteboard.general.image = image }
            case nil: break
            }
            Haptics.shared.play(content == nil ? .error : .snap)
        case .macro(let macro):
            received(macro)
        default:
            // Phone -> Mac messages never arrive here.
            break
        }
    }

    private func received(_ message: MacroMessage) {
        switch message {
        case .macroList(let active, let all):
            macroProfile = active
            allMacros = all
            if let data = try? JSONEncoder().encode(all) {
                UserDefaults.standard.set(data, forKey: Self.macroCacheKey)
            }
            // Siri phrases that name a macro ("Run Rename files with Glasspad") use this list.
            GlasspadShortcuts.updateAppShortcutParameters()
        case .activeProfileChanged(let active):
            if macroProfile?.profileID != active.profileID { Haptics.shared.play(.detent) }
            macroProfile = active
        case .progress(let progress):
            macroPendingID = nil
            macroRunning = progress
        case .runFinished(let id, let outcome, let message, let outputs):
            macroPendingID = nil
            if macroRunning?.macroID == id { macroRunning = nil }
            let name = allMacros?.first { $0.id == id }?.name ?? macroProfile?.macros.first { $0.id == id }?.name ?? "Macro"
            showMacroResult(MacroResult(macroID: id, title: name, outcome: outcome,
                                        message: message, output: outputs.last))
            Haptics.shared.play(outcome == .completed ? .detent : .error)
        case .recordingState(let on):
            isRecordingMacro = on
        case .recordingFinished(let macro, let dropped):
            isRecordingMacro = false
            let note = dropped > 0 ? "\(dropped) keys typed into password fields were left out." : nil
            showMacroResult(MacroResult(macroID: macro.id, title: "Saved \(macro.name)", outcome: .completed,
                                        message: note, output: nil))
            send(.macro(.listMacros))
            Haptics.shared.play(.snap)
        case .recordingFailed(let message):
            isRecordingMacro = false
            showMacroResult(MacroResult(macroID: nil, title: "Recording stopped", outcome: .failed,
                                        message: message, output: nil))
            Haptics.shared.play(.error)
        case .listMacros, .run, .gesture, .cancelRun, .recordStart, .recordStop:
            break
        }
    }

    func runMacro(_ id: UUID) {
        macroPendingID = id
        send(.macro(.run(macroID: id)))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            if self.macroPendingID == id {
                self.macroPendingID = nil
                self.showMacroResult(MacroResult(macroID: id, title: "No answer", outcome: .failed,
                                                 message: "Your Mac did not answer.", output: nil))
            }
        }
    }

    private func showMacroResult(_ result: MacroResult) {
        macroResult = result
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(result.output == nil ? 3.5 : 6))
            if self.macroResult == result { self.macroResult = nil }
        }
    }

    /// Waits for the macro list (for the "Run Macro" action's picker).
    func fetchMacros() async -> [MacroSummary] {
        send(.macro(.listMacros))
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(100))
            if let all = allMacros, isConnected, !all.isEmpty { return all }
        }
        return allMacros ?? []
    }

    private func showDeckFailure(_ message: String) {
        let failure = DeckFailure(message: message)
        deckFailure = failure
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            if self.deckFailure == failure { self.deckFailure = nil }
        }
    }

    private func resetModeData() {
        dockApps = []
        media = nil
        deckButtons = nil
        deckOutcomes = [:]
        deckPending = []
        clipboardPulled = nil
        macroProfile = nil
        allMacros = nil
        macroRunning = nil
        macroResult = nil
        isRecordingMacro = false
        UserDefaults.standard.removeObject(forKey: Self.deckCacheKey)
        UserDefaults.standard.removeObject(forKey: Self.macroCacheKey)
    }

    private func setState(_ new: LinkState) {
        guard state != new else { return }
        state = new
        switch new {
        case .connected:
            resumeWaiters(true)
        case .failed:
            resumeWaiters(false)
        default:
            break
        }
        LiveActivityController.shared.refresh()
    }

    // MARK: Background use (Siri and Shortcuts)

    enum SessionError: LocalizedError {
        case notPaired, unreachable(String)
        var errorDescription: String? {
            switch self {
            case .notPaired: "Glasspad is not paired with a Mac yet. Open Glasspad to pair."
            case .unreachable(let name): "Glasspad could not reach \(name). Check that it is on and on the same Wi-Fi."
            }
        }
    }

    /// Connects if needed (also from the background, for App Intents), runs `body`, then
    /// gives the message a moment to leave before letting go of the connection.
    func withConnection(timeout: TimeInterval = 8, _ body: @MainActor (MacSession) async throws -> Void) async throws {
        guard let mac = PairingStore.shared.selected else { throw SessionError.notPaired }
        backgroundUsers += 1
        defer {
            backgroundUsers -= 1
            releaseBackgroundOrDisconnect()
        }
        connectIfNeeded()
        guard await waitUntilConnected(timeout: timeout) else { throw SessionError.unreachable(mac.name) }
        try await body(self)
        try? await Task.sleep(for: .milliseconds(400))
    }

    func waitUntilConnected(timeout: TimeInterval) async -> Bool {
        if isConnected { return true }
        let id = UUID()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(timeout))
            self.stateWaiters.removeValue(forKey: id)?.resume(returning: false)
        }
        return await withCheckedContinuation { continuation in
            if isConnected {
                continuation.resume(returning: true)
            } else {
                stateWaiters[id] = continuation
            }
        }
    }

    private func resumeWaiters(_ value: Bool) {
        let waiters = stateWaiters
        stateWaiters = [:]
        for waiter in waiters.values { waiter.resume(returning: value) }
    }

    /// Waits for the Deck list (for the "Run Deck button" action's picker).
    func fetchDeckButtons() async -> [DeckButton] {
        send(.deckRequest)
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(100))
            if let buttons = deckButtons, isConnected, !buttons.isEmpty { return buttons }
        }
        return deckButtons ?? []
    }
}

/// Receives link callbacks (on the main queue, the client's default) and hands them to the session.
private final class LinkBridge: GlasspadLinkDelegate {
    weak var session: MacSession?

    func link(didChangeState state: LinkState) {
        let session = self.session
        MainActor.assumeIsolated { session?.linkStateChanged(state) }
    }

    func link(didReceive message: ControlMessage) {
        let session = self.session
        MainActor.assumeIsolated { session?.received(message) }
    }
}

extension LinkState {
    var statusText: String {
        switch self {
        case .idle: "Not connected"
        case .searching: "Looking for your Mac"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .failed(let reason): "Could not connect: \(reason)"
        }
    }
}
