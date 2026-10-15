import Foundation
import GlasspadKit
import Network
import Observation
import UIKit

/// The phone's one connection to its selected Mac, and everything the Mac has told it.
/// Owns GlasspadKit's `MacConnector` (one client at a time, last used Mac first); views and
/// App Intents talk to the Mac only through here.
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
    /// Another iPhone took this Mac. The link waits for the user instead of retrying.
    var isReplaced: Bool { state.isReplaced }
    var macName: String? { PairingStore.shared.selected?.name }

    // MARK: Mode data

    private(set) var dockApps: [DockApp] = []
    let icons = IconCache()
    /// Every app installed on the Mac (names only), for search and the Deck editor.
    private(set) var dockCatalog: [DockApp] = []
    /// Why the last Dock tap did not work, shown for a few seconds.
    private(set) var dockNotice: DockNotice?
    /// Whether the Mac's own Dock is hidden, and the two switches behind it.
    private(set) var macDockState: MacDockState?
    /// The Mac's frontmost app (Deck brings linked pages forward).
    private(set) var frontmostBundleID: String?
    /// Pages, folders and grid density of the Deck.
    private(set) var deckLayout: DeckLayout?
    private(set) var deckCatalog: DeckCatalog?
    /// A Deck edit the Mac refused, with its reason.
    private(set) var deckSaveError: String?
    /// A screenshot a Deck button sent, for a short confirmation.
    private(set) var deckImageNotice: DeckFailure?
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

    @ObservationIgnored private var connector: MacConnector?
    private var client: GlasspadClient? { connector?.client }
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
    private static let deckLayoutCacheKey = "deckLayoutCache"
    private static let dockListCacheKey = "dockListCache"

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
        if let data = UserDefaults.standard.data(forKey: Self.deckLayoutCacheKey) {
            deckLayout = try? JSONDecoder().decode(DeckLayout.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: Self.dockListCacheKey) {
            dockApps = (try? JSONDecoder().decode([DockApp].self, from: data)) ?? []
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
        GPLog.log("trackpad visible: \(visible), client \(client == nil ? "nil" : "ok")")
        trackpadVisible = visible
        applyHeartbeats()
        if visible { Haptics.shared.warmUp() } else { Haptics.shared.coolDown() }
    }

    func select(_ mac: PairedMac) {
        guard connector?.activeMacID != mac.macID || client == nil else { return }
        PairingStore.shared.select(mac.macID)
        resetModeData()
        reconnect()
    }

    /// A code was just scanned. Always starts a fresh session: even for a Mac paired before,
    /// the key is new.
    func didPair(_ mac: PairedMac) {
        PairingStore.shared.select(mac.macID)
        resetModeData()
        reconnect()
    }

    /// After another iPhone took the Mac: take it back, once, because the user asked.
    func useHere() {
        guard let client else { return reconnect() }
        client.connect()
    }

    enum WakeResult { case sent, noAddress, failed }

    /// Sends a Wake-on-LAN magic packet to the selected Mac's last address. Unicast only: the
    /// broadcast copy needs the multicast networking entitlement, which this app does not have.
    func wakeMac() async -> WakeResult {
        guard let target = PairingStore.shared.selected?.wakeTarget,
              let packet = WakeOnLAN.magicPacket(macAddress: target.macAddress),
              let ip = target.lastIPv4 else { return .noAddress }
        let sent = await UnicastWake.send(packet, to: ip, port: target.port)
        if sent { connector?.reconnectNow() }
        return sent ? .sent : .failed
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
        #if DEBUG
        if isDemo { return }
        #endif
        guard foreground || backgroundUsers > 0 else { return }
        guard let mac = PairingStore.shared.selected else {
            setState(.idle)
            return
        }
        if let connector, let client = connector.client, connector.activeMacID == mac.macID,
           connector.phoneName == PhoneSettings.shared.phoneName {
            switch client.state {
            case .failed(let reason) where reason == GlasspadService.replacedFailure:
                // Another iPhone has the Mac. Taking it back is the user's call, not a loop.
                break
            case .failed:
                client.connect()
            default:
                // Back from the background: skip any backoff wait and replace a dead socket.
                connector.reconnectNow()
            }
            return
        }
        disconnect()
        let new = MacConnector(store: PairingStore.shared.known,
                               phoneID: PairingStore.shared.phoneID.uuidString,
                               phoneName: PhoneSettings.shared.phoneName)
        new.delegate = bridge
        connector = new
        new.connect(to: mac.macID)
        // Same store update the connector does, plus a refresh of what the views show.
        let macID = mac.macID
        new.client?.onWakeTarget = { target in
            MainActor.assumeIsolated { PairingStore.shared.setWakeTarget(target, for: macID) }
        }
        applyHeartbeats()
    }

    private func disconnect() {
        if laserOn { laserOff() }
        connector?.delegate = nil
        connector?.disconnect()
        connector = nil
        setState(.idle)
    }

    private func releaseBackgroundOrDisconnect() {
        guard !foreground, backgroundUsers == 0 else { return }
        disconnect()
    }

    // MARK: Sending

    /// One touch snapshot from the surface. Called for every sample, on the main thread.
    func send(frame: TouchFrame) {
        if client == nil { GPLog.log("send(frame): no client") }
        client?.send(frame: frame)
    }

    func send(_ message: ModeMessage) {
        client?.send(message: .mode(message))
    }

    /// Any control message (the trackpad uses it to send its tuning inside `.settings`).
    func send(control message: ControlMessage) {
        client?.send(message: message)
    }

    func modeDidChange(to mode: AppMode) {
        if mode != .present, laserOn { laserOff() }
        send(.modeSelected(mode.wireMode))
    }

    /// Asks for the Dock list, telling the Mac which icons this phone already has.
    func requestDock() {
        send(.dockSync(iconKeys: icons.knownKeys))
    }

    func openDockApp(_ app: DockApp) {
        dockNotice = nil
        send(.dockOpen(bundleID: app.bundleID))
    }

    /// Changes the Mac's own Dock switches (applied on the Mac, which answers with the new state).
    func setMacDock(_ state: MacDockState) {
        macDockState = state
        send(.macDockSet(state))
    }

    /// Sends the edited Deck to the Mac. Shown at once; the Mac's answer confirms or undoes it.
    func saveDeck(_ layout: DeckLayout) {
        deckSaveError = nil
        deckLayout = layout
        cacheDeckLayout(layout)
        send(.deckSave(layout))
    }

    func runDeck(_ id: UUID, confirmed: Bool = false) {
        deckPending.insert(id)
        send(confirmed ? .deckRunConfirmed(id: id) : .deckRun(id: id))
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
            // The connector marked this Mac as last used; show it.
            PairingStore.shared.reload()
            send(.modeSelected(AppRouter.shared.mode.wireMode))
            // Refresh whatever the current screen shows.
            switch AppRouter.shared.mode {
            case .dock: requestDock()
            case .media: send(.mediaRequest)
            case .deck: send(.deckRequest)
            case .actions:
                send(.deckRequest)
                send(.macro(.listMacros))
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
            guard PhoneSettings.shared.allowsHaptic(kind) else { return }
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
            dockApps = storeIcons(apps)
            if let data = try? JSONEncoder().encode(dockApps) {
                UserDefaults.standard.set(data, forKey: Self.dockListCacheKey)
            }
        case .dockIcons(let apps):
            _ = storeIcons(apps)
        case .dockCatalog(let apps):
            dockCatalog = apps
        case .dockOpenResult(let bundleID, let ok, let message):
            if ok {
                Haptics.shared.play(.detent)
            } else {
                Haptics.shared.play(.error)
                let name = (dockApps + dockCatalog).first { $0.bundleID == bundleID }?.name ?? "That app"
                showDockNotice(DockNotice(title: "\(name) did not open", message: message ?? "Your Mac could not open it."))
            }
        case .frontmostApp(let bundleID):
            frontmostBundleID = bundleID
        case .macDockState(let state):
            macDockState = state
        case .deckLayout(let layout):
            deckLayout = layout
            cacheDeckLayout(layout)
        case .deckSaveResult(let ok, let message):
            if !ok {
                deckSaveError = message ?? "Your Mac did not save the Deck."
                Haptics.shared.play(.error)
                send(.deckRequest)
            }
        case .deckCatalog(let catalog):
            deckCatalog = catalog
        case .deckImage(_, let data, let destination):
            receivedDeckImage(data, destination)
        case .mediaState(let state):
            media = state
            mediaReceivedAt = Date()
            MediaStore.shared.receive(state)
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

    /// Keeps icons by key and returns the list without the image bytes.
    private func storeIcons(_ apps: [DockApp]) -> [DockApp] {
        apps.map { app in
            var a = app
            if let png = app.iconPNG { icons.store(png, key: app.iconKey ?? app.bundleID, bundleID: app.bundleID) }
            a.iconPNG = nil
            return a
        }
    }

    private func showDockNotice(_ notice: DockNotice) {
        dockNotice = notice
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if self.dockNotice == notice { self.dockNotice = nil }
        }
    }

    private func cacheDeckLayout(_ layout: DeckLayout) {
        if let data = try? JSONEncoder().encode(layout) {
            UserDefaults.standard.set(data, forKey: Self.deckLayoutCacheKey)
        }
    }

    private func receivedDeckImage(_ data: Data, _ destination: DeckImageDestination) {
        guard let image = UIImage(data: data) else { return }
        switch destination {
        case .clipboard:
            UIPasteboard.general.image = image
            showDeckImageNotice("Screenshot copied")
        case .photos:
            PhotoSaver.save(image) { ok in
                self.showDeckImageNotice(ok ? "Screenshot saved to Photos" : "Allow Glasspad to add to Photos in Settings")
            }
        }
        Haptics.shared.play(.snap)
    }

    private func showDeckImageNotice(_ text: String) {
        let notice = DeckFailure(message: text)
        deckImageNotice = notice
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if self.deckImageNotice == notice { self.deckImageNotice = nil }
        }
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
        dockCatalog = []
        macDockState = nil
        frontmostBundleID = nil
        deckLayout = nil
        deckCatalog = nil
        UserDefaults.standard.removeObject(forKey: Self.deckLayoutCacheKey)
        UserDefaults.standard.removeObject(forKey: Self.dockListCacheKey)
        media = nil
        MediaStore.shared.reset()
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
        #if DEBUG
        if isDemo { return }
        #endif
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

    #if DEBUG
    /// Debug builds only: fills every screen with sample data for simulator screenshots.
    @ObservationIgnored private(set) var isDemo = false

    func applyDemo(_ demo: DemoData) {
        isDemo = true
        state = .connected(rttMs: 3)
        for (id, png) in demo.icons { icons.store(png, key: "\(id)@demo", bundleID: id) }
        dockApps = demo.dockApps
        dockCatalog = demo.catalog
        frontmostBundleID = demo.frontmost
        deckLayout = demo.layout
        macroProfile = demo.profile
        allMacros = demo.macros
        macDockState = MacDockState(hidden: false, hideWhileConnected: true, isHiddenNow: true)
        hasMacSettings = true
    }
    #endif

    // MARK: Background use (Siri and Shortcuts)

    enum SessionError: LocalizedError {
        case notPaired, unreachable(String), replaced(String)
        var errorDescription: String? {
            switch self {
            case .notPaired: "Glasspad is not paired with a Mac yet. Open Glasspad to pair."
            case .replaced(let name): "Another iPhone is using \(name). Open Glasspad to use it on this iPhone."
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
        if isReplaced { throw SessionError.replaced(mac.name) }
        guard await waitUntilConnected(timeout: timeout) else {
            throw isReplaced ? SessionError.replaced(mac.name) : SessionError.unreachable(mac.name)
        }
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
    var isReplaced: Bool {
        if case .failed(let reason) = self { reason == GlasspadService.replacedFailure } else { false }
    }

    var statusText: String {
        switch self {
        case .idle: "Not connected"
        case .searching: "Looking for your Mac"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .failed where isReplaced: "Another iPhone is using this Mac"
        case .failed(let reason): "Could not connect: \(reason)"
        }
    }
}

/// One UDP datagram to one address, over the Network framework.
enum UnicastWake {
    static func send(_ packet: Data, to host: String, port: UInt16) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .udp)
        let done = Once()
        return await withCheckedContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: packet, completion: .contentProcessed { error in
                        if done.claim() { continuation.resume(returning: error == nil) }
                        connection.cancel()
                    })
                case .failed, .cancelled:
                    if done.claim() { continuation.resume(returning: false) }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                if done.claim() { continuation.resume(returning: false) }
                connection.cancel()
            }
        }
    }

    /// Lets exactly one of several racing callbacks resume the continuation.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var used = false
        func claim() -> Bool { lock.withLock { defer { used = true }; return !used } }
    }
}
