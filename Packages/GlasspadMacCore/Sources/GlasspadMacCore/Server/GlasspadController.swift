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
    /// The pairing link shown as a QR code, while pairing is open.
    @Published public private(set) var pairingURL: URL?
    @Published public private(set) var lastError: String?

    public let pairing: PairingStore
    public let macName: String
    private let server: GlasspadServer
    private let watcher: TrackpadPrefsWatcher
    private let pipeline: TouchPipeline
    private let modes: ModeRouter
    private var statusTimer: Timer?
    private var bridge: LinkBridge?

    public init(pairing: PairingStore = PairingStore(), macName: String = Host.current().localizedName ?? "Mac") {
        self.pairing = pairing
        self.macName = macName
        let caps = SynthCapabilities.selfCheck()
        let poster = LiveEventPoster()
        let watcher = TrackpadPrefsWatcher()
        self.watcher = watcher
        self.settings = watcher.settings
        self.capabilities = caps
        let synth = EventSynthesizer(poster: poster, settings: watcher.settings, capabilities: caps)
        self.pipeline = TouchPipeline(settings: watcher.settings, synth: synth)
        self.modes = ModeRouter(poster: poster)
        let store = pairing
        self.server = GlasspadServer(macID: pairing.macID, macName: macName) { phoneID in
            store.storedKey(for: phoneID)
        }
        self.phones = pairing.phones
    }

    public func start() {
        let bridge = LinkBridge(owner: self)
        self.bridge = bridge
        server.delegate = bridge
        server.onPaired = { [weak self] phone in
            MainActor.assumeIsolated { self?.paired(phone) }
        }
        pipeline.onHaptic = { [weak self] kind in self?.server.send(.haptic(kind)) }
        pipeline.setDisplayWidth(Double(NSScreen.screens.first?.frame.width ?? 0))
        modes.send = { [weak self] message in self?.server.send(.mode(message)) }
        watcher.onChange = { [weak self] s in self?.settingsChanged(s) }
        watcher.start()
        do {
            try server.start()
        } catch {
            lastError = "Could not start listening: \(error.localizedDescription)"
        }
        refreshAccessibility()
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
        server.stop()
    }

    // MARK: Pairing

    public func beginPairing() {
        let payload = pairing.beginPairing(macName: macName)
        server.pendingPairKey = payload.pairKey
        pairingURL = payload.url
    }

    public func cancelPairing() {
        pairing.cancelPairing()
        server.pendingPairKey = nil
        pairingURL = nil
    }

    public func revoke(_ phone: StoredPhone) {
        try? pairing.revoke(phone.phoneID)
        if server.connectedPhone?.phoneID == phone.phoneID { server.disconnect(reason: "revoked") }
        phones = pairing.phones
    }

    private func paired(_ phone: PairedPhone) {
        do {
            try pairing.save(phoneID: phone.phoneID, phoneName: phone.phoneName, pairKey: phone.pairKey)
        } catch {
            lastError = "Could not save the pairing to the Keychain"
        }
        pairingURL = nil
        phones = pairing.phones
    }

    // MARK: Permissions

    public func refreshAccessibility() {
        accessibilityTrusted = AXIsProcessTrusted()
    }

    /// Shows the system prompt that adds Glasspad to the Accessibility list.
    public func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString   // kAXTrustedCheckOptionPrompt
        accessibilityTrusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    public nonisolated static let accessibilitySettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    // MARK: Link callbacks

    fileprivate func linkStateChanged(_ state: LinkState) {
        let wasConnected = { if case .connected = linkState { return true } else { return false } }()
        linkState = state
        if case .connected = state {
            connectedPhoneName = server.connectedPhone?.phoneName
            if !wasConnected { server.send(.settings(settings)) }
        } else {
            connectedPhoneName = nil
            if wasConnected {
                pipeline.cancelAll()
                modes.sessionEnded()
            }
        }
    }

    fileprivate func received(_ message: ControlMessage) {
        if case .mode(let m) = message { modes.handle(m) }
    }

    fileprivate func received(_ frame: TouchFrame) {
        guard accessibilityTrusted else { return }
        pipeline.process(frame)
    }

    private func settingsChanged(_ s: TrackpadSettings) {
        settings = s
        pipeline.settings = s
        server.send(.settings(s))
    }

    private func refreshStatus() {
        stats = server.stats
        if !accessibilityTrusted { refreshAccessibility() }
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
