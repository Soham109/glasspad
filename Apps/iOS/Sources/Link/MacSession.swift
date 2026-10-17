import Foundation
import ImageIO
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
    /// Low Power Mode: keep-awake heartbeats stop after 10 s without a touch instead of 2 min,
    /// and button-tap haptics are skipped. Pointer traffic and click haptics are unchanged.
    private(set) var isLowPower = false
    /// What the Mac last said it can do (Accessibility, Automation). nil until a Mac that
    /// reports it connects; older Mac builds never send it.
    private(set) var macStatus: MacStatus?
    /// Why the link cannot come up, when the client can tell (Local Network off, or a network
    /// that keeps devices apart).
    private(set) var linkIssue: LinkIssue?
    /// When the current session reached `connected` (to tell "not reported yet" from "an older
    /// Mac that never reports").
    private(set) var connectedAt: Date?

    var isConnected: Bool { if case .connected = state { true } else { false } }
    /// Another iPhone took this Mac. The link waits for the user instead of retrying.
    var isReplaced: Bool { state.isReplaced }
    var macName: String? { PairingStore.shared.selected?.name }
    /// Connected, and the Mac says Accessibility is off: touches arrive but cannot move anything.
    var macNeedsAccessibility: Bool { isConnected && macStatus?.accessibilityTrusted == false }

    /// Round trips measured in this session (only while `setDiagnosticsVisible(true)`). Not
    /// observed: read it on a timer.
    var roundTrip: RoundTripStats { client?.roundTrip ?? RoundTripStats() }
    /// How this session reaches the Mac. Not observed: read it on a timer.
    var linkPath: LinkPath? { client?.path }

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
    /// What each key types on the Mac's keyboard layout (`keysLayout`), for Keyboard. US until
    /// a Mac says otherwise; kept across launches so the right letters show at once.
    private(set) var keyboardLetters: KeyboardLetters = .us
    private(set) var deckButtons: [DeckButton]?
    private(set) var deckPending: Set<UUID> = []
    private(set) var deckOutcomes: [UUID: DeckOutcome] = [:]
    private(set) var deckFailure: DeckFailure?
    private(set) var clipboardPulled: PulledClipboard?
    private(set) var clipboardPullPending = false
    /// The last send to the Mac clipboard and what the Mac said about it.
    private(set) var clipboardPush: ClipboardPushStatus?
    @ObservationIgnored private var clipboardPushGeneration = 0
    @ObservationIgnored private var clipboardPullGeneration = 0
    /// The Mac explained a refused pull; the plain nil it sends next (for older phones) is skipped.
    @ObservationIgnored private var clipboardSkipNextEmpty = false

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
    /// Trackpad surfaces on screen (a layout can show two).
    @ObservationIgnored private var trackpads = ShownCount()
    private var trackpadVisible: Bool { trackpads.isShown }
    /// Set only by an explicit move to the background (not at launch, before the first scene
    /// phase arrives).
    @ObservationIgnored private var backgrounded = false
    @ObservationIgnored private var hapticsWarm = false
    @ObservationIgnored private var lastLocalHaptic: [HapticKind: TimeInterval] = [:]
    @ObservationIgnored private var stateWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    @ObservationIgnored private var laserOn = false
    @ObservationIgnored private var power = PowerPolicy()
    @ObservationIgnored private var diagnostics = ShownCount()
    /// The last Deck save, until the Mac confirms or refuses it.
    @ObservationIgnored private var deckSaveWatch = ReplyWatch()
    /// Drops a request for state made again a moment after the same one (two panes asking).
    @ObservationIgnored private var requests = RequestCoalescer()
    /// Icons being decoded for the last Dock message; the next one waits for it.
    @ObservationIgnored private var iconWork: Task<Void, Never>?
    /// Counts `resetModeData`, so late work for the previous Mac is dropped.
    @ObservationIgnored private var modeDataEpoch = 0

    private static let settingsKey = "lastMacSettings"
    private static let deckCacheKey = "deckButtonsCache"
    private static let macroCacheKey = "macrosCache"
    private static let deckLayoutCacheKey = "deckLayoutCache"
    private static let dockListCacheKey = "dockListCache"
    private static let keyboardLettersKey = "keyboardLetters"

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
        if let data = UserDefaults.standard.data(forKey: Self.keyboardLettersKey),
           let saved = try? JSONDecoder().decode(KeyboardLetters.self, from: data) {
            keyboardLetters = saved
        }
        bridge.session = self
        PowerMonitor.shared.onChange { [weak self] in self?.powerChanged($0) }
        refreshHapticStrength()
    }

    // MARK: Lifecycle

    /// The app came to the foreground or went to the background.
    func setForeground(_ active: Bool) {
        foreground = active
        backgrounded = !active
        applyHapticEngine()
        if active {
            connectIfNeeded()
        } else {
            releaseBackgroundOrDisconnect()
        }
    }

    /// A trackpad surface appeared or disappeared. Heartbeats only run while one is visible.
    func setTrackpadVisible(_ visible: Bool) {
        trackpads.set(visible)
        GPLog.log("trackpad visible: \(visible) (\(trackpads.count) shown), client \(client == nil ? "nil" : "ok")")
        applyHeartbeats()
        applyHapticEngine()
    }

    /// The trackpad dimmed or woke. A dimmed trackpad swallows the touch that wakes it, so the
    /// haptic engine can rest meanwhile and be ready again before the first real click.
    func dimmedChanged() {
        applyHapticEngine()
    }

    /// The Taptic Engine stays powered only while the trackpad is on screen, awake and in front.
    private func applyHapticEngine() {
        let wanted = trackpadVisible && !backgrounded && !AppRouter.shared.isDimmed
        guard wanted != hapticsWarm else { return }
        hapticsWarm = wanted
        if wanted { Haptics.shared.warmUp() } else { Haptics.shared.coolDown() }
    }

    /// A diagnostics screen (Connection, the setup checklist) appeared or disappeared. While one
    /// shows, the phone measures round trips, with heartbeats on so the numbers match the trackpad.
    func setDiagnosticsVisible(_ visible: Bool) {
        diagnostics.set(visible)
        applyHeartbeats()
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
        SetupGuide.shared.paired()
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
        new.client?.onIssueChange = { issue in
            MainActor.assumeIsolated { MacSession.shared.linkIssue = issue }
        }
        linkIssue = new.client?.issue
        applyHeartbeats()
    }

    private func disconnect() {
        if laserOn { laserOff() }
        connector?.delegate = nil
        connector?.disconnect()
        connector = nil
        linkIssue = nil
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
        guard requests.shouldSend(message, now: ProcessInfo.processInfo.systemUptime) else { return }
        client?.send(message: .mode(message))
    }

    /// Any control message (the trackpad uses it to send its tuning inside `.settings`).
    func send(control message: ControlMessage) {
        client?.send(message: message)
    }

    func modeDidChange(to mode: AppMode) {
        modesDidChange(to: [mode])
    }

    /// Tells the Mac what is on screen: one mode, or every open pane of a layout. The Mac
    /// follows one screen at a time, so `LayoutWirePlan` picks the one it must follow and the
    /// rest are asked for directly.
    func modesDidChange(to modes: [AppMode]) {
        if !modes.contains(.present), laserOn { laserOff() }
        let plan = LayoutWirePlan(modes: modes.map(\.wireMode))
        send(.modeSelected(plan.primary))
        if let shown = plan.shown { send(.modesShown(shown)) }
        if plan.requestsMedia { send(.mediaRequest) }
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
        // An older Mac drops a Deck it cannot read without answering; never leave it looking saved.
        let generation = deckSaveWatch.start()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard self.deckSaveWatch.timedOut(generation) else { return }
            self.deckSaveError = self.isConnected
                ? "Your Mac did not save the change. Update Glasspad on your Mac, then try again."
                : "Not connected to your Mac, so the change was not saved."
            Haptics.shared.play(.error)
            self.send(.deckRequest)
        }
    }

    /// A button from a newer Glasspad was tapped: it cannot run, so say why.
    func deckNeedsUpdate() {
        Haptics.shared.play(.error)
        showDeckFailure(DeckAction.updateToUse)
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
        clipboardSkipNextEmpty = false
        clipboardPullGeneration += 1
        let generation = clipboardPullGeneration
        send(.clipboardPull)
        // A large image takes a few seconds on slow Wi-Fi; past this the Mac is not answering.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(15))
            guard self.clipboardPullGeneration == generation, self.clipboardPullPending else { return }
            self.clipboardPullPending = false
            self.clipboardPulled = PulledClipboard(content: nil, problem: ClipboardPushStatus.noAnswer)
        }
    }

    /// Sends content to the Mac clipboard. It shows as sent only once the Mac says it took it
    /// (`clipboardPushResult`); a refusal shows the Mac's reason.
    func pushClipboard(_ content: ClipboardContent) {
        if case .text(let text) = content, content.byteCount > ClipboardContent.maxTextBytes {
            clipboardPush = .refused(ClipboardContent.tooLargeMessage(bytes: text.utf8.count, holder: "This text"))
            Haptics.shared.play(.error)
            return
        }
        guard isConnected else {
            clipboardPush = .refused("Not connected to your Mac. Connect, then tap Paste again.")
            Haptics.shared.play(.error)
            return
        }
        clipboardPushGeneration += 1
        let generation = clipboardPushGeneration
        let done: String
        switch content {
        case .text(let t): done = "Sent \(t.count) characters"
        case .imagePNG: done = "Sent an image"
        }
        clipboardPush = .waiting(whenDone: done)
        send(.clipboardPush(content))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(20))
            guard self.clipboardPushGeneration == generation, case .waiting = self.clipboardPush else { return }
            self.clipboardPush = .refused(ClipboardPushStatus.noConfirmation)
        }
    }

    /// `pushClipboard`, then waits for the Mac's answer (Shortcuts uses it). Still `.waiting`
    /// when the Mac did not answer within `timeout`.
    func pushClipboardConfirmed(_ content: ClipboardContent, timeout: TimeInterval = 10) async -> ClipboardPushStatus? {
        pushClipboard(content)
        let end = Date().addingTimeInterval(timeout)
        while case .waiting = clipboardPush, Date() < end { try? await Task.sleep(for: .milliseconds(50)) }
        return clipboardPush
    }

    /// A problem found on the phone before anything was sent (nothing readable was pasted).
    func clipboardPushFailed(_ message: String) {
        clipboardPushGeneration += 1
        clipboardPush = .refused(message)
        Haptics.shared.play(.error)
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

    private func powerChanged(_ policy: PowerPolicy) {
        power = policy
        if isWarm != policy.isWarm { isWarm = policy.isWarm }
        if isLowPower != policy.lowPower { isLowPower = policy.lowPower }
        Haptics.shared.suspendedForHeat = !policy.allowsHaptics
        applyHeartbeats()
    }

    private func applyHeartbeats() {
        guard let client else { return }
        client.heartbeatIdleTimeout = power.heartbeatIdleTimeout
        client.measuresRoundTrip = diagnostics.isShown
        client.heartbeatsEnabled = (trackpadVisible || diagnostics.isShown) && power.allowsHeartbeats
    }

    // MARK: Receiving

    fileprivate func linkStateChanged(_ new: LinkState) {
        setState(new)
        if !new.isConnectedState, case .waiting = clipboardPush {
            // The answer cannot come any more; never leave it looking sent.
            clipboardPush = .refused("The connection dropped before your Mac confirmed it. Try again.")
        }
        if case .connected = new {
            connectedAt = Date()
            // Anything asked before this session never reached the Mac.
            requests.reset()
            // The connector marked this Mac as last used; show it.
            PairingStore.shared.reload()
            let modes = AppRouter.shared.screenModes
            modesDidChange(to: modes)
            DisplaysStore.shared.linkConnected()
            // Refresh whatever the screen shows (every pane of a layout).
            for mode in modes {
                switch mode {
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
        case .macStatus(let status):
            receivedStatus(status)
        case .bye, .ping, .pong, .phoneStatus, .unknown:
            break
        }
    }

    private func receivedStatus(_ status: MacStatus) {
        let wasBlocked = macStatus?.accessibilityTrusted == false
        macStatus = status
        if wasBlocked && status.accessibilityTrusted {
            Haptics.shared.play(.snap)
            UIAccessibility.post(notification: .announcement, argument: "Your Mac allows Glasspad now.")
        } else if !wasBlocked && !status.accessibilityTrusted {
            UIAccessibility.post(notification: .announcement, argument: "Your Mac needs one permission. Turn on Glasspad in Accessibility settings on the Mac.")
        }
    }

    private func received(_ message: ModeMessage) {
        switch message {
        case .dockList(let apps):
            storeIcons(apps) { list in
                // The same list again (a refresh, a push after a tap) changes nothing: no
                // redraw, no write.
                guard list != self.dockApps else { return }
                self.dockApps = list
                if let data = try? JSONEncoder().encode(list) {
                    UserDefaults.standard.set(data, forKey: Self.dockListCacheKey)
                }
            }
        case .dockIcons(let apps):
            storeIcons(apps) { _ in }
        case .dockCatalog(let apps):
            if dockCatalog != apps { dockCatalog = apps }
        case .dockOpenResult(let bundleID, let ok, let message):
            if ok {
                Haptics.shared.play(.detent)
            } else {
                Haptics.shared.play(.error)
                let name = (dockApps + dockCatalog).first { $0.bundleID == bundleID }?.name ?? "That app"
                showDockNotice(DockNotice(title: "\(name) did not open", message: message ?? "Your Mac could not open it."))
            }
        case .frontmostApp(let bundleID):
            if frontmostBundleID != bundleID { frontmostBundleID = bundleID }
        case .macDockState(let state):
            if macDockState != state { macDockState = state }
        case .deckLayout(let layout):
            guard deckLayout != layout else { return }
            deckLayout = layout
            cacheDeckLayout(layout)
        case .deckSaveResult(let ok, let message):
            deckSaveWatch.settle()
            if !ok {
                deckSaveError = message ?? "Your Mac did not save your buttons."
                Haptics.shared.play(.error)
                send(.deckRequest)
            }
        case .deckCatalog(let catalog):
            if deckCatalog != catalog { deckCatalog = catalog }
        case .deckImage(_, let data, let destination):
            receivedDeckImage(data, destination)
        case .mediaState(let state):
            media = state
            mediaReceivedAt = Date()
            MediaStore.shared.receive(state)
        case .deckButtons(let buttons):
            guard deckButtons != buttons else { return }
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
        case .clipboardPushResult(let ok, let message):
            guard case .waiting(let done) = clipboardPush else { return }
            clipboardPush = ok ? .accepted(done) : .refused(message ?? "Your Mac did not take it.")
            Haptics.shared.play(ok ? .snap : .error)
        case .clipboardPullRefused(let message):
            clipboardPullPending = false
            clipboardSkipNextEmpty = true
            clipboardPulled = PulledClipboard(content: nil, problem: message)
            Haptics.shared.play(.error)
        case .clipboardContent(let content):
            if clipboardSkipNextEmpty, content == nil {
                clipboardSkipNextEmpty = false
                return
            }
            clipboardSkipNextEmpty = false
            clipboardPullPending = false
            clipboardPulled = PulledClipboard(content: content)
            switch content {
            case .text(let text)?: UIPasteboard.general.string = text
            case .imagePNG(let data)?: Self.copyImage(data)
            case nil: break
            }
            Haptics.shared.play(content == nil ? .error : .snap)
        case .macro(let macro):
            received(macro)
        case .keysLayout(let letters):
            guard letters != keyboardLetters else { return }
            keyboardLetters = letters
            if let data = try? JSONEncoder().encode(letters) {
                UserDefaults.standard.set(data, forKey: Self.keyboardLettersKey)
            }
        case .displaysState, .displaysResult:
            DisplaysStore.shared.receive(message)
        default:
            // Phone -> Mac messages never arrive here.
            break
        }
    }

    private func received(_ message: MacroMessage) {
        switch message {
        case .macroList(let active, let all):
            if macroProfile != active { macroProfile = active }
            guard allMacros != all else { return }
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

    /// Keeps icons by key, then hands `then` the list without the image bytes. Icons are
    /// decoded off the main thread (the first Dock list carries dozens at 384 px), and lists
    /// are handled in the order they came, so an older list never lands after a newer one.
    private func storeIcons(_ apps: [DockApp], then: @escaping @MainActor ([DockApp]) -> Void) {
        let list = apps.map { app -> DockApp in
            var a = app
            a.iconPNG = nil
            return a
        }
        let incoming = apps.compactMap { app in app.iconPNG.map { (app, $0) } }
        guard !incoming.isEmpty || iconWork != nil else { return then(list) }
        let previous = iconWork
        let epoch = modeDataEpoch
        let work = Task { @MainActor in
            await previous?.value
            let decoded = await Task.detached(priority: .userInitiated) {
                incoming.map { app, png in (app, png, IconCache.decode(png)) }
            }.value
            for (app, png, image) in decoded {
                guard let image else { continue }
                self.icons.store(png, decoded: image, key: app.iconKey ?? app.bundleID, bundleID: app.bundleID)
            }
            // Another Mac was chosen meanwhile: this list is not its.
            if self.modeDataEpoch == epoch { then(list) }
        }
        iconWork = work
        Task { @MainActor in
            await work.value
            if self.iconWork == work { self.iconWork = nil }
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

    /// A screenshot from a Deck button. Its bytes go to the pasteboard or Photos as they came:
    /// a full-display PNG is many megabytes, and decoding it on the main thread only to encode
    /// it again froze the screen for a moment.
    private func receivedDeckImage(_ data: Data, _ destination: DeckImageDestination) {
        guard Self.imageType(data) != nil else { return }
        switch destination {
        case .clipboard:
            Self.copyImage(data)
            showDeckImageNotice("Screenshot copied")
        case .photos:
            PhotoSaver.save(imageData: data) { ok in
                self.showDeckImageNotice(ok ? "Screenshot saved to Photos" : "Allow Glasspad to add to Photos in Settings")
            }
        }
        Haptics.shared.play(.snap)
    }

    /// Puts image bytes on the pasteboard without decoding them (apps that paste read them as
    /// an image of their type: PNG, or JPEG from a Mac that had to shrink a large one).
    private static func copyImage(_ data: Data) {
        guard let type = imageType(data) else { return }
        UIPasteboard.general.setData(data, forPasteboardType: type)
    }

    /// The bytes' image type identifier (read from the header only), nil when not an image.
    private static func imageType(_ data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        return CGImageSourceGetType(source) as String?
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
        modeDataEpoch += 1
        macStatus = nil
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
        DisplaysStore.shared.reset()
        deckButtons = nil
        deckOutcomes = [:]
        deckPending = []
        clipboardPulled = nil
        clipboardPush = nil
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
        if case .connected = new {} else { connectedAt = nil }
        switch new {
        case .connected:
            resumeWaiters(true)
        case .failed:
            resumeWaiters(false)
        default:
            break
        }
        LiveActivityController.shared.refresh()
        // The screen is held on only while connected.
        ScreenAwake.update()
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

    /// Waits for the Deck list (for the "Run Glasspad Button" action's picker).
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
    var isConnectedState: Bool { if case .connected = self { true } else { false } }

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
