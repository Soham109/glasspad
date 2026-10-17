import Foundation
import Network

/// Phone side of the link: finds the paired Mac over Bonjour (or a direct host:port), runs the
/// handshake, sends sealed touch frames over UDP and control messages over TCP, keeps the
/// Wi-Fi radio awake with heartbeats, and reconnects with backoff.
///
/// Touch frames: pass every frame as a full snapshot with `timestamp` in `systemUptime` seconds
/// (UITouch timestamps already are). The client assigns `seq`. While any finger is down it
/// resends the last snapshot (phases set to stationary, fresh timestamp) every 20 ms, so the
/// Mac never mistakes a resting finger for a dead link and a lost "ended" packet heals fast.
///
/// Staying connected: the client reconnects with backoff after any drop (`ReconnectBackoff`:
/// fast at first, then 5, 10 and 30 s with jitter), at once when the
/// network changes (Wi-Fi switch, wake from sleep) or when the Mac goes silent for
/// `GlasspadService.clientSilenceTimeout` (the Mac pings every second). A fresh start tries the
/// address the Mac last answered on alongside the Bonjour browse, so coming back after the
/// phone was locked does not wait for Bonjour to look the Mac up again. Call `reconnectNow()`
/// when the app returns to the foreground. It stops retrying only after `disconnect()`, a
/// refusal from the Mac, or when another phone takes over the Mac (`failed(replacedFailure)`).
///
/// Thread safety: every public member may be called from any thread.
public final class GlasspadClient: @unchecked Sendable {
    public let phoneID: String
    public let phoneName: String
    public let pairing: PairingPayload

    public weak var delegate: (any GlasspadLinkDelegate)? {
        get { delegateBox.get().value }
        set { delegateBox.set(WeakDelegate(value: newValue)) }
    }
    public var state: LinkState { stateBox.get() }
    /// Keep-awake heartbeats: set true while the trackpad screen is visible.
    public var heartbeatsEnabled: Bool {
        get { heartbeatsBox.get() }
        set {
            heartbeatsBox.set(newValue)
            if newValue { queue.async { [self] in speedUpKeepalive() } }
        }
    }
    /// Heartbeats stop after this long without a touch. Default
    /// `GlasspadService.heartbeatIdleTimeout`; the phone cuts it in Low Power Mode.
    public var heartbeatIdleTimeout: TimeInterval {
        get { idleBox.get() }
        set { idleBox.set(max(1, newValue)) }
    }
    /// While true the client pings the Mac about once a second and fills `roundTrip` (for a
    /// diagnostics screen). Off by default: it is extra traffic nothing else needs.
    public var measuresRoundTrip: Bool {
        get { measureBox.get() }
        set { measureBox.set(newValue) }
    }
    /// Datagrams sent (touch frames, resends and heartbeats).
    public var datagramsSent: Int { sentBox.get() }
    /// How to wake this Mac, from its last handshake (nil until then). Store it with the pairing
    /// (`KnownMacs.setWakeTarget`) so it is there when the Mac is asleep.
    public var wakeTarget: WakeTarget? { wakeBox.get() }
    /// Called on the delegate queue when the Mac sends its wake details (after each handshake).
    public var onWakeTarget: (@Sendable (WakeTarget) -> Void)? {
        get { wakeHandler.get() }
        set { wakeHandler.set(newValue) }
    }
    /// Round trips this phone measured in the current session: it pings the Mac once a
    /// second and the Mac answers. Empty until connected.
    public var roundTrip: RoundTripStats { rttBox.get() }
    /// How the current session reaches the Mac; nil while not connected.
    public var path: LinkPath? { pathBox.get() }
    /// Why the client cannot reach the Mac right now, when it can tell (nil when connected or
    /// when nothing is known). `state` keeps saying `searching`/`connecting` while it retries in
    /// the background; this says why, so the phone can explain instead of spinning forever.
    public var issue: LinkIssue? { issueBox.get() }
    /// Called on the delegate queue whenever `issue` changes (including back to nil).
    public var onIssueChange: (@Sendable (LinkIssue?) -> Void)? {
        get { issueHandler.get() }
        set { issueHandler.set(newValue) }
    }

    private let queue = DispatchQueue(label: "glasspad.client", qos: .userInteractive)
    private let delegateQueue: DispatchQueue
    private let delegateBox = Locked(WeakDelegate())
    private let stateBox = Locked(LinkState.idle)
    private let heartbeatsBox = Locked(false)
    private let sentBox = Locked(0)
    private let wakeBox = Locked<WakeTarget?>(nil)
    private let wakeHandler = Locked<(@Sendable (WakeTarget) -> Void)?>(nil)
    private let rttBox = Locked(RoundTripStats())
    private let idleBox = Locked(GlasspadService.heartbeatIdleTimeout)
    private let measureBox = Locked(false)
    /// True while the keepalive timer runs at the heartbeat rate (50 Hz); otherwise it ticks once
    /// a second, for the silence check only.
    private var keepaliveFast = false
    private let pathBox = Locked<LinkPath?>(nil)
    private let issueBox = Locked<LinkIssue?>(nil)
    private let issueHandler = Locked<(@Sendable (LinkIssue?) -> Void)?>(nil)
    /// Connections that failed before TCP even opened, in a row (queue-confined).
    private var connectFailures = ConnectFailureTracker()

    private enum Target { case bonjour, direct(host: String, port: UInt16) }
    private enum Phase { case hello(nonce: Data), confirm, connected }

    // Queue-confined state.
    private var target: Target?
    private var generation = 0
    private var browser: NWBrowser?
    private var channel: ControlChannel?
    private var phase: Phase?
    private var crypto: SessionCrypto?
    private var udpPort: UInt16 = 0
    private var udp: NWConnection?
    private var seq: UInt32 = 0
    private var lastSnapshot: TouchFrame?
    /// After the last finger lifts, an empty snapshot is resent this many more times, so a lost
    /// "ended" packet still lifts the finger on the Mac (resends only cover fingers still down).
    private var liftResends = 0
    private var liftSurface: CGSize = .zero
    /// Timestamp for the empty resends: the lift's, or the last resend's if that was later, so
    /// they are never older than what the Mac has (it drops late frames) nor newer than the
    /// app's next touch.
    private var liftTime: TimeInterval = 0
    /// Timestamp of the last touch frame sent.
    private var lastFrameTime: TimeInterval = 0
    static let liftResendCount = 2
    private var lastAppFrame: TimeInterval = 0
    private var lastSend: TimeInterval = 0
    private var lastTouchActivity: TimeInterval = 0
    private var keepalive: DispatchSourceTimer?
    private var attempt = 0
    private var reconnectWork: DispatchWorkItem?
    /// A quiet shared-network Bonjour browse kept open during a long backoff wait, so a Mac
    /// that comes back is tried at once instead of at the end of the wait.
    private var watcher: NWBrowser?
    private var watchAnswers = 0
    /// The current attempt opened TCP to the Mac (it is there, only busy or restarting).
    private var reachedMac = false
    private var lastReceived: TimeInterval = 0
    private var pathMonitor: NWPathMonitor?
    private var lastPathSignature: String?
    private var lastGateways = ""
    /// When AWDL may be used: it opens after the shared network found nothing (or connects to a
    /// found Mac kept failing) and closes again after `PeerToPeerWindow.length`.
    private var peerToPeer = PeerToPeerWindow()
    private var usePeerToPeer: Bool { peerToPeer.isOpen(now: uptime()) }
    /// Whether the channel being opened (and its session's UDP) may use AWDL.
    private var channelPeerToPeer = false
    /// A connection to the Mac's last address, racing the Bonjour browse on a fresh start.
    private var probe: ControlChannel?
    /// The open channel came from the last address rather than from Bonjour.
    private var channelFromLastAddress = false
    /// Tests only: the session now connected came from the last address.
    var connectedViaLastAddress: Bool { viaLastAddressBox.get() }
    private let viaLastAddressBox = Locked(false)

    /// Where each Mac last answered over the shared network, and on which network.
    static let lastAddresses = Locked(LastAddressBook())
    /// A fresh start came before the first network report: try the last address once it arrives.
    private var probeWhenPathKnown = false
    /// A last address that has not opened TCP by then is given up (Bonjour carries on).
    static let probeTimeout: TimeInterval = 1.5
    /// The handshake on a last address must finish this fast, or Bonjour takes over.
    static let probeHandshakeTimeout: TimeInterval = 1.5
    /// The phone's own pings, for `roundTrip`.
    private var pingID: UInt32 = 0
    private var pingSent: [UInt32: TimeInterval] = [:]
    private var lastPing: TimeInterval = 0
    /// Tests only: holds the Bonjour browse back this long while a last address is tried, as a
    /// lookup on a real network takes longer than on this Mac's own cache.
    var slowBonjourForTesting: TimeInterval = 0
    /// Internal so tests can shorten it.
    var silenceTimeout: TimeInterval = GlasspadService.clientSilenceTimeout

    /// Snapshot resends stop after this long without a frame from the app.
    static let maxResendAge: TimeInterval = 30

    public init(phoneID: String, phoneName: String, pairing: PairingPayload, delegateQueue: DispatchQueue = .main) {
        self.phoneID = phoneID
        self.phoneName = phoneName
        self.pairing = pairing
        self.delegateQueue = delegateQueue
    }

    deinit {
        pathMonitor?.cancel()
        watcher?.cancel()
        probe?.connection.cancel()
        browser?.cancel()
        keepalive?.cancel()
        udp?.cancel()
        channel?.connection.cancel()
    }

    /// Browses Bonjour for the paired Mac and connects; reconnects until `disconnect()`.
    public func connect() {
        queue.async { [self] in start(.bonjour) }
    }

    /// Connects straight to a known host and TCP port (tests, or a manual address).
    public func connect(host: String, port: UInt16) {
        queue.async { [self] in start(.direct(host: host, port: port)) }
    }

    /// Says bye and stops reconnecting.
    public func disconnect() {
        queue.async { [self] in
            if case .connected = phase, let ch = channel, crypto != nil,
               let plain = try? ControlMessage.bye(reason: "phone disconnected").jsonData(),
               let sealed = try? crypto!.sealTCP(plain) {
                channel = nil
                ch.onClosed = nil
                ch.sendThenClose(sealed, reason: "disconnect")
            }
            target = nil
            stopPathMonitor()
            teardown()
            setState(.idle)
        }
    }

    /// Reconnects right away, skipping any backoff wait. Use it when the app comes back to the
    /// foreground. A connected session is kept if the Mac was heard from in the last second,
    /// otherwise it is replaced (after sleep the old socket is often dead without knowing it).
    public func reconnectNow() {
        queue.async { [self] in
            guard target != nil else { return }
            if case .connected = phase, uptime() - lastReceived < 1.0 { return }
            restartNow()
        }
    }

    /// Sends one touch snapshot over UDP. Dropped while not connected.
    public func send(frame: TouchFrame) {
        queue.async { [self] in
            guard case .connected = phase else { GPLog.log("send(frame): dropped, phase \(String(describing: phase))"); return }
            let now = uptime()
            lastAppFrame = now
            lastTouchActivity = now
            var f = frame
            f.touches = Array(f.touches.prefix(TouchCodec.maxTouches))
            let active = f.touches.filter { $0.phase.isActive }
            if active.isEmpty, lastSnapshot != nil || !f.touches.isEmpty {
                liftResends = Self.liftResendCount
                liftSurface = f.surface
                liftTime = max(f.timestamp, lastFrameTime)
            } else if !active.isEmpty {
                liftResends = 0
            }
            lastSnapshot = active.isEmpty ? nil : TouchFrame(seq: 0, timestamp: f.timestamp, touches: active, surface: f.surface)
            sendTouches(f)
            speedUpKeepalive()
        }
    }

    /// Tests only: seals this JSON as one control message to the Mac, as a build with other
    /// message types would send it.
    func sendRawJSONForTesting(_ json: Data) {
        queue.async { [self] in
            guard case .connected = phase else { return }
            sendRaw(json)
        }
    }

    /// Sends a control message over TCP. Dropped while not connected.
    public func send(message: ControlMessage) {
        queue.async { [self] in
            guard case .connected = phase else { return }
            sendControl(message)
        }
    }

    // MARK: Connecting

    private func start(_ t: Target) {
        target = t
        attempt = 0
        peerToPeer = PeerToPeerWindow()
        connectFailures = ConnectFailureTracker()
        setIssue(nil)
        teardown()
        startPathMonitor()
        open()
    }

    /// Drops whatever is in progress and connects again with no delay.
    private func restartNow() {
        guard target != nil else { return }
        teardown()
        attempt = 0
        peerToPeer = PeerToPeerWindow()
        // A new network (or the app back in front) deserves a fresh look: forget earlier
        // failures, but keep a Local Network denial until the browser says otherwise.
        connectFailures = ConnectFailureTracker()
        if issue == .networkBlocksDevices { setIssue(nil) }
        open()
    }

    /// Tests only: stalls the client's queue, as if the phone app were suspended.
    func blockQueueForTesting(seconds: TimeInterval) {
        queue.async { Thread.sleep(forTimeInterval: seconds) }
    }

    // MARK: Network changes

    private func startPathMonitor() {
        guard pathMonitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in self?.pathUpdated(path) }
        pathMonitor = m
        m.start(queue: queue)
    }

    private func stopPathMonitor() {
        pathMonitor?.cancel()
        pathMonitor = nil
        lastPathSignature = nil
        lastGateways = ""
    }

    private func pathUpdated(_ path: NWPath) {
        let satisfied = path.status == .satisfied
        let names = Set(path.availableInterfaces.map(\.name))
        let gateways = path.gateways.map { "\($0)" }.sorted().joined(separator: ",")
        let signature = "\(satisfied)|" + names.sorted().joined(separator: ",") + "|" + gateways
        let previous = lastPathSignature, previousGateways = lastGateways
        lastPathSignature = signature
        lastGateways = gateways
        guard let previous else {
            if probeWhenPathKnown {
                probeWhenPathKnown = false
                if attempt == 0, channel == nil, probe == nil, case .bonjour? = target { probeLastAddressIfKnown() }
            }
            return
        }
        guard previous != signature else { return }
        // Joining another Wi-Fi network keeps the interface name (en0) but changes the router.
        let switched = previous.hasPrefix("false|") || (!previousGateways.isEmpty && previousGateways != gateways)
        if switched { Self.lastAddresses.mutate { $0.networkSwitched(to: gateways) } }
        networkChanged(satisfied: satisfied, interfaceNames: names, networkSwitched: switched)
    }

    /// Wi-Fi switched, an interface came or went, or the device woke. Not connected: retry now
    /// instead of waiting out the backoff. Connected, but the network changed under the session
    /// (another Wi-Fi, back from no network, or its interface is gone): the socket is dead, so
    /// start over now rather than waiting for TCP or the silence timeout to notice.
    func networkChanged(satisfied: Bool, interfaceNames: Set<String>, networkSwitched: Bool = false) {
        guard target != nil, satisfied else { return }
        if case .connected = phase, !networkSwitched,
           let used = channel?.connection.currentPath?.availableInterfaces.first?.name,
           interfaceNames.contains(used) {
            return
        }
        restartNow()
    }

    private func open() {
        generation += 1
        reachedMac = false
        switch target {
        case .bonjour?:
            // First try of a fresh start: also knock on the address the Mac last used.
            let probing = attempt == 0 && !usePeerToPeer && Self.lastAddresses.get().knows(pairing.macID)
            if probing {
                if lastPathSignature == nil { probeWhenPathKnown = true } else { probeLastAddressIfKnown() }
            }
            if probing, slowBonjourForTesting > 0 {
                let gen = generation
                queue.asyncAfter(deadline: .now() + slowBonjourForTesting) { [weak self] in
                    guard let self, gen == self.generation, self.channel == nil else { return }
                    self.browse()
                }
            } else {
                browse()
            }
        case .direct(let host, let port)?:
            guard let p = NWEndpoint.Port(rawValue: port) else { return setState(.failed("bad port")) }
            openTCP(.hostPort(host: NWEndpoint.Host(host), port: p))
        case nil: break
        }
    }

    /// Browses on the shared network first. Only if the Mac is not found there within
    /// `peerToPeerFallbackDelay` does it browse again with peer-to-peer Wi-Fi (AWDL) allowed,
    /// and only for `PeerToPeerWindow.length`: then it goes back to the shared network alone,
    /// so a Mac that is asleep or away does not keep AWDL on (and the radio hopping) for good.
    private func browse() {
        setState(.searching)
        let gen = generation
        let now = uptime()
        let p2p = peerToPeer.isOpen(now: now)
        let params = NWParameters()
        params.includePeerToPeer = p2p
        params.prohibitedInterfaceTypes = [.cellular]
        if peerToPeer.closesAt == nil {
            queue.asyncAfter(deadline: .now() + GlasspadService.peerToPeerFallbackDelay) { [weak self] in
                guard let self, gen == self.generation, self.browser != nil, self.peerToPeer.closesAt == nil else { return }
                GPLog.log("browse: not found on the shared network, also trying peer-to-peer Wi-Fi")
                self.browser?.cancel()
                self.browser = nil
                self.peerToPeer.open(now: uptime())
                self.generation += 1
                self.browse()
            }
        } else if p2p, let left = peerToPeer.remaining(now: now) {
            queue.asyncAfter(deadline: .now() + left) { [weak self] in
                guard let self, gen == self.generation, self.browser != nil else { return }
                GPLog.log("browse: not found over peer-to-peer Wi-Fi either, back to the shared network only")
                self.browser?.cancel()
                self.browser = nil
                self.generation += 1
                self.browse()
            }
        }
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: GlasspadService.bonjourType, domain: nil), using: params)
        let wanted = pairing.macID.uuidString.uppercased()
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, gen == self.generation, self.browser != nil else { return }
            GPLog.log("browse (\(p2p ? "peer-to-peer allowed" : "shared network")): \(results.count) result(s): \(results.map { r -> String in if case .bonjour(let t) = r.metadata { return "\(r.endpoint) id=\(t["id"] ?? "-")" }; return "\(r.endpoint)" }) wanted=\(wanted)")
            for r in results {
                if case .bonjour(let txt) = r.metadata, txt["id"]?.uppercased() == wanted {
                    self.browser?.cancel()
                    self.browser = nil
                    self.openTCP(r.endpoint)
                    return
                }
            }
        }
        b.stateUpdateHandler = { [weak self] st in
            guard let self, gen == self.generation else { return }
            GPLog.log("browser state: \(st)")
            switch st {
            case .failed(let e):
                if LinkIssue.isLocalNetworkDenied(e) { self.setIssue(.localNetworkDenied) }
                self.lost(gen, reason: "browse failed: \(e)")
            case .waiting(let e):
                // A denied Local Network permission parks the browser here for good. It keeps
                // waiting (it recovers by itself once the user allows access), but say why.
                if LinkIssue.isLocalNetworkDenied(e) { self.setIssue(.localNetworkDenied) }
            case .ready:
                if self.issue == .localNetworkDenied { self.setIssue(nil) }
            default:
                break
            }
        }
        browser = b
        b.start(queue: queue)
    }

    private func openTCP(_ endpoint: NWEndpoint) {
        GPLog.log("tcp: opening \(endpoint)")
        dropProbe()
        setState(.connecting)
        let gen = generation
        channelPeerToPeer = usePeerToPeer
        channelFromLastAddress = false
        let ch = ControlChannel(connection: NWConnection(to: endpoint, using: GlasspadService.tcpParameters(peerToPeer: channelPeerToPeer)), queue: queue)
        var opened = false
        ch.onReady = { [weak self] in
            opened = true
            self?.reachedMac = true
            self?.sendHello()
        }
        attach(ch, gen: gen) { [weak self, weak ch] reason in
            guard let self else { return }
            if !opened, gen == self.generation {
                self.connectFailed(reason: reason, path: ch?.connection.currentPath)
            }
        }
        ch.start()
        queue.asyncAfter(deadline: .now() + GlasspadService.handshakeTimeout) { [weak self] in
            guard let self, gen == self.generation else { return }
            if case .connected = self.phase { return }
            self.channel?.close("handshake timeout")
        }
    }

    /// Makes `ch` the session's channel: frames, liveness and loss go through the client.
    private func attach(_ ch: ControlChannel, gen: Int, beforeLost: @escaping (String?) -> Void = { _ in }) {
        ch.onFrame = { [weak self] data in self?.handleFrame(data) }
        // Part of a large message (a clipboard image on slow Wi-Fi) counts as hearing the Mac.
        ch.onBytes = { [weak self] in self?.lastReceived = uptime() }
        ch.onClosed = { [weak self] reason in
            guard let self else { return }
            beforeLost(reason)
            self.lost(gen, reason: reason ?? "closed")
        }
        channel = ch
    }

    /// Races the browse: TCP straight to where the Mac last answered. The first to reach the
    /// Mac wins. If this one opens first the browse stops and the handshake runs on it; the
    /// handshake proves it is the right Mac, as it does for a Bonjour result. A last address
    /// that does not open is left to the browse; one that opens on something that does not
    /// finish the handshake quickly is forgotten and the browse starts again.
    /// Knocks on the Mac's last address, if it was learned on the network the phone is on now.
    private func probeLastAddressIfKnown() {
        guard let last = Self.lastAddresses.get().address(for: pairing.macID, network: lastGateways) else { return }
        probeLastAddress(last)
    }

    private func probeLastAddress(_ endpoint: NWEndpoint) {
        let gen = generation
        GPLog.log("tcp: also trying the last address \(endpoint)")
        let ch = ControlChannel(connection: NWConnection(to: endpoint, using: GlasspadService.tcpParameters()), queue: queue)
        let macID = pairing.macID
        ch.onReady = { [weak self, weak ch] in
            guard let self, let ch, gen == self.generation, self.probe === ch, self.channel == nil else {
                ch?.close(nil)
                return
            }
            GPLog.log("tcp: the last address answered first, Bonjour not needed")
            self.probe = nil
            self.browser?.cancel()
            self.browser = nil
            setState(.connecting)
            self.channelPeerToPeer = false
            self.channelFromLastAddress = true
            self.reachedMac = true
            self.attach(ch, gen: gen) { [weak self] _ in
                // Closed before the session was up: that address is not the Mac any more.
                guard let self, gen == self.generation else { return }
                if case .connected = self.phase { return }
                Self.lastAddresses.mutate { $0.forget(macID) }
            }
            self.sendHello()
            self.queue.asyncAfter(deadline: .now() + Self.probeHandshakeTimeout) { [weak self] in
                guard let self, gen == self.generation, self.channelFromLastAddress else { return }
                if case .connected = self.phase { return }
                GPLog.log("tcp: no handshake on the last address, looking the Mac up instead")
                self.retryWithoutLastAddress()
            }
        }
        ch.onClosed = { [weak self, weak ch] reason in
            guard let self, let ch, self.probe === ch else { return }
            // Kept: right after unlocking, Wi-Fi may simply not be back yet. A session found by
            // Bonjour replaces it.
            self.probe = nil
            GPLog.log("tcp: last address did not answer (\(reason ?? "closed")), Bonjour carries on")
        }
        probe = ch
        ch.start()
        queue.asyncAfter(deadline: .now() + Self.probeTimeout) { [weak ch] in ch?.close("timed out") }
    }

    private func dropProbe() {
        let p = probe
        probe = nil
        p?.close(nil)
    }

    /// The last address led somewhere wrong: forget it and look the Mac up with Bonjour now.
    private func retryWithoutLastAddress() {
        Self.lastAddresses.mutate { $0.forget(pairing.macID) }
        teardown()
        open()
    }

    private func sendHello() {
        let nonce = randomBytes(16)
        phase = .hello(nonce: nonce)
        let hello = PhoneHello(phoneID: phoneID, phoneName: phoneName, macID: pairing.macID, nonce: nonce)
        if let json = try? JSONEncoder().encode(hello) { channel?.send(json) }
    }

    private func handleFrame(_ data: Data) {
        lastReceived = uptime()
        switch phase {
        case .hello(let nonce)?:
            guard let tag = try? JSONDecoder().decode(HandshakeTag.self, from: data) else {
                channel?.close("bad hello")
                return
            }
            if tag.t == "reject" {
                let reason = (try? JSONDecoder().decode(HandshakeReject.self, from: data))?.reason ?? "rejected"
                if channelFromLastAddress {
                    // Something else lives at that address now (another Mac). Not a refusal
                    // from this Mac: look it up properly.
                    GPLog.log("tcp: the last address refused (\(reason)), looking the Mac up instead")
                    return retryWithoutLastAddress()
                }
                target = nil                       // do not retry a refusal
                teardown()
                setState(.failed(reason))
                return
            }
            guard let hello = try? JSONDecoder().decode(MacHello.self, from: data), hello.nonce.count == 16 else {
                channel?.close("bad hello")
                return
            }
            crypto = SessionCrypto(pairKey: pairing.pairKey, phoneNonce: nonce, macNonce: hello.nonce, role: .phone)
            udpPort = hello.udpPort
            phase = .confirm
            sendRaw(handshakeConfirmToken)
        case .confirm?:
            guard crypto != nil, let plain = try? crypto!.openTCP(data), plain == handshakeConfirmToken else {
                channel?.close("mac failed key confirmation")
                return
            }
            phase = .connected
            attempt = 0
            connectFailures = ConnectFailureTracker()
            setIssue(nil)
            rttBox.set(RoundTripStats())
            pingSent = [:]
            lastPing = uptime()
            if let conn = channel?.connection {
                pathBox.set(LinkPath.classify(interface: conn.currentPath?.availableInterfaces.first,
                                              peerToPeer: channelPeerToPeer, endpoint: "\(conn.endpoint)"))
                // Remember where the Mac answered, for the next fresh start (shared network only).
                if case .bonjour? = target, !channelPeerToPeer, let remote = conn.currentPath?.remoteEndpoint,
                   case .hostPort = remote {
                    let network = lastGateways
                    Self.lastAddresses.mutate { $0.learn(remote, network: network, for: pairing.macID) }
                }
            }
            viaLastAddressBox.set(channelFromLastAddress)
            openUDP()
            lastTouchActivity = uptime()
            startKeepalive()
            setState(.connected(rttMs: nil))
        case .connected?:
            guard crypto != nil, let plain = try? crypto!.openTCP(data) else { return }
            guard let msg = try? ControlMessage.from(jsonData: plain) else { return }
            switch msg {
            case .unknown(let type):
                // The transport's own wake details, or a newer Mac's message: never delivered.
                if type == "wake", let wake = try? JSONDecoder().decode(WakeAnnouncement.self, from: plain) {
                    wakeBox.set(wake.target)
                    let handler = wakeHandler.get()
                    delegateQueue.async { handler?(wake.target) }
                }
            case .ping(let id): sendControl(.pong(id: id))
            case .pong(let id):
                if let sent = pingSent.removeValue(forKey: id) {
                    let ms = (uptime() - sent) * 1000
                    rttBox.mutate { $0.add(ms) }
                }
            case .bye(let reason) where reason == GlasspadService.replacedReason:
                // Another connection took over the Mac. Retrying would steal it back, and the
                // two phones would take turns forever.
                delegateQueue.async { [weak self] in self?.delegate?.link(didReceive: msg) }
                target = nil
                stopPathMonitor()
                teardown()
                setState(.failed(GlasspadService.replacedFailure))
            default: delegateQueue.async { [weak self] in self?.delegate?.link(didReceive: msg) }
            }
        case nil:
            break
        }
    }

    private func openUDP() {
        var host: NWEndpoint.Host?
        if case .hostPort(let h, _)? = channel?.connection.currentPath?.remoteEndpoint { host = h }
        if host == nil, case .direct(let h, _)? = target { host = NWEndpoint.Host(h) }
        guard let host, let port = NWEndpoint.Port(rawValue: udpPort) else { GPLog.log("udp: no host (\(String(describing: host))) or port \(udpPort)"); return }
        GPLog.log("udp: sending to \(host):\(port)")
        let c = NWConnection(host: host, port: port, using: GlasspadService.udpParameters(peerToPeer: channelPeerToPeer))
        c.stateUpdateHandler = { st in GPLog.log("udp state: \(st)") }
        c.start(queue: queue)
        udp = c
    }

    private func lost(_ gen: Int, reason: String) {
        GPLog.log("lost (gen \(gen) vs \(generation)): \(reason)")
        guard gen == generation else { return }
        teardown()
        scheduleReconnect(after: ReconnectBackoff.delay(attempt: attempt, reachedMac: reachedMac))
    }

    private func scheduleReconnect(after delay: TimeInterval) {
        guard target != nil else { return }
        attempt += 1
        if case .bonjour? = target { setState(.searching) } else { setState(.connecting) }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.target != nil, self.channel == nil, self.browser == nil else { return }
            self.stopWatching()
            self.open()
        }
        reconnectWork = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
        if delay >= ReconnectBackoff.watchFrom, case .bonjour? = target { watchForMac() }
    }

    /// During a long wait: a shared-network browse (cheap, the system's mDNS does the work)
    /// that tries again at once when the Mac's service appears or changes, as it does when the
    /// Mac wakes or its app restarts. The first answer within a second is what the system
    /// already knew (the record the last try failed with), so it does not count.
    private func watchForMac() {
        stopWatching()
        let gen = generation
        let started = uptime()
        let params = NWParameters()
        params.includePeerToPeer = false
        params.prohibitedInterfaceTypes = [.cellular]
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: GlasspadService.bonjourType, domain: nil), using: params)
        let wanted = pairing.macID.uuidString.uppercased()
        watchAnswers = 0
        b.browseResultsChangedHandler = { [weak self] _, changes in
            guard let self, gen == self.generation, self.watcher != nil else { return }
            self.watchAnswers += 1
            if self.watchAnswers == 1, uptime() - started < 1 { return }
            guard BrowseChange.mentions(wanted, in: changes) else { return }
            GPLog.log("watch: the Mac's service came back, trying now")
            self.stopWatching()
            self.reconnectWork?.cancel()
            self.reconnectWork = nil
            guard self.target != nil, self.channel == nil, self.browser == nil else { return }
            self.open()
        }
        watcher = b
        b.start(queue: queue)
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    private func teardown() {
        generation += 1
        reconnectWork?.cancel()
        reconnectWork = nil
        stopWatching()
        dropProbe()
        probeWhenPathKnown = false
        channelFromLastAddress = false
        browser?.cancel()
        browser = nil
        keepalive?.cancel()
        keepalive = nil
        keepaliveFast = false
        udp?.cancel()
        udp = nil
        let ch = channel
        channel = nil
        ch?.close(nil)
        phase = nil
        crypto = nil
        pathBox.set(nil)
        pingSent = [:]
        lastSnapshot = nil
        liftResends = 0
    }

    // MARK: Sending

    private func sendControl(_ m: ControlMessage) {
        guard let plain = try? m.jsonData() else { return }
        sendRaw(plain)
    }

    private func sendRaw(_ plain: Data) {
        guard crypto != nil, let sealed = try? crypto!.sealTCP(plain) else { return }
        channel?.send(sealed)
    }

    /// Each touch frame goes out once, the moment UIKit delivers it, on the WMM voice queue
    /// (`udpParameters`). A duplicate a couple of ms later was considered and left out: the
    /// losses seen on real links come in runs (the radio is away on AWDL channels or asleep for
    /// 16 to 200 ms), so a copy sent 2 ms after a lost frame is lost with it, while it doubles
    /// air time on the busiest queue (about 120 more datagrams a second). Frames are full
    /// snapshots, so an isolated loss costs only one sample interval of delay (the next frame
    /// carries the position), and the Mac's scheduler bridges the runs.
    private func sendTouches(_ f: TouchFrame) {
        var f = f
        seq &+= 1
        f.seq = seq
        lastFrameTime = f.timestamp
        sendDatagram(TouchCodec.encode(f))
    }

    private func sendDatagram(_ plain: Data) {
        guard let udp, crypto != nil, let sealed = try? crypto!.sealUDP(plain) else {
            GPLog.log("udp: datagram dropped (udp \(self.udp == nil ? "missing" : "ok"), crypto \(crypto == nil ? "missing" : "ok"))")
            return
        }
        udp.send(content: sealed, completion: .contentProcessed { err in
            if let err { GPLog.log("udp: send error \(err)") }
        })
        lastSend = uptime()
        let n = sentBox.mutate { c -> Int in c += 1; return c }
        if n == 1 || n % 500 == 0 { GPLog.log("udp: \(n) datagrams sent") }
    }

    private func startKeepalive() {
        scheduleKeepalive(fast: needsFastTick(uptime()))
    }

    /// The 50 Hz tick is needed only while a finger is down (snapshot resends), lift resends are
    /// pending, or heartbeats are on and the phone was touched recently. Otherwise a 1 s tick
    /// keeps the silence check and pings going without waking the CPU 50 times a second.
    private func needsFastTick(_ now: TimeInterval) -> Bool {
        if lastSnapshot != nil && now - lastAppFrame < Self.maxResendAge { return true }
        if liftResends > 0 { return true }
        return heartbeatsEnabled && now - lastTouchActivity < heartbeatIdleTimeout
    }

    private func speedUpKeepalive() {
        guard case .connected = phase, !keepaliveFast, needsFastTick(uptime()) else { return }
        scheduleKeepalive(fast: true)
    }

    private func scheduleKeepalive(fast: Bool) {
        keepalive?.cancel()
        keepaliveFast = fast
        let t = DispatchSource.makeTimerSource(flags: fast ? .strict : [], queue: queue)
        let i = fast ? GlasspadService.heartbeatInterval : min(1, silenceTimeout / 3)
        t.schedule(deadline: .now() + i, repeating: i, leeway: fast ? .milliseconds(2) : .milliseconds(100))
        t.setEventHandler { [weak self] in self?.keepaliveTick() }
        t.resume()
        keepalive = t
    }

    private func keepaliveTick() {
        guard case .connected = phase else { return }
        let now = uptime()
        if now - lastReceived > silenceTimeout {
            // The Mac pings every second; this many missed means it slept, changed network or
            // the socket died quietly. Reconnect now instead of waiting for TCP to give up.
            teardown()
            scheduleReconnect(after: 0)
            return
        }
        if measuresRoundTrip, now - lastPing >= GlasspadService.pingInterval { sendPing(now) }
        defer {
            // Drop to the slow tick once nothing needs the fast one.
            if case .connected = phase, keepaliveFast, !needsFastTick(now) { scheduleKeepalive(fast: false) }
        }
        guard now - lastSend >= GlasspadService.heartbeatInterval * 0.9 else { return }
        if var snap = lastSnapshot, now - lastAppFrame < Self.maxResendAge {
            snap.timestamp = now
            snap.touches = snap.touches.map { var t = $0; t.phase = .stationary; return t }
            sendTouches(snap)
        } else if liftResends > 0 {
            liftResends -= 1
            sendTouches(TouchFrame(seq: 0, timestamp: liftTime, touches: [], surface: liftSurface))
        } else if heartbeatsEnabled, now - lastTouchActivity < heartbeatIdleTimeout {
            seq &+= 1
            sendDatagram(TouchCodec.heartbeat(seq: seq, timestamp: now))
        }
    }

    /// One ping on the control channel; the Mac's `pong` gives a round-trip sample. Pings the
    /// Mac never answers (old ones, lost ones) are dropped after a few seconds.
    private func sendPing(_ now: TimeInterval) {
        lastPing = now
        pingID &+= 1
        pingSent = pingSent.filter { now - $0.value < 5 }
        pingSent[pingID] = now
        sendControl(.ping(id: pingID))
    }

    /// TCP never opened. After a Bonjour hit that usually means the network keeps devices apart
    /// (guest Wi-Fi with client isolation, a VPN, a firewall): allow peer-to-peer Wi-Fi for the
    /// next attempts, and after a few more say why. Retrying goes on in the background.
    private func connectFailed(reason: String?, path: NWPath?) {
        if path?.unsatisfiedReason == .localNetworkDenied || LinkIssue.isLocalNetworkDenied(reason: reason) {
            setIssue(.localNetworkDenied)
            return
        }
        let advice = connectFailures.record()
        if advice.tryPeerToPeer, case .bonjour? = target, peerToPeer.closesAt == nil {
            GPLog.log("tcp: \(connectFailures.failures) failed connects after finding the Mac, allowing peer-to-peer Wi-Fi")
            peerToPeer.open(now: uptime())
        }
        if advice.report, issue == nil { setIssue(.networkBlocksDevices) }
    }

    private func setIssue(_ new: LinkIssue?) {
        let changed = issueBox.mutate { cur -> Bool in
            guard cur != new else { return false }
            cur = new
            return true
        }
        guard changed else { return }
        GPLog.log("issue -> \(new.map { "\($0)" } ?? "none")")
        let handler = issueHandler.get()
        delegateQueue.async { handler?(new) }
    }

    private func setState(_ new: LinkState) {
        let changed = stateBox.mutate { st -> Bool in
            guard st != new else { return false }
            st = new
            return true
        }
        guard changed else { return }
        GPLog.log("state -> \(new)")
        delegateQueue.async { [weak self] in self?.delegate?.link(didChangeState: new) }
    }
}

/// Why the phone cannot reach its Mac, when the client can tell. Shown next to `LinkState`.
public enum LinkIssue: Equatable, Sendable {
    /// iOS Local Network access is off for Glasspad (the user tapped "Don't Allow", or turned
    /// it off in Settings > Privacy & Security > Local Network). Nothing on the network is
    /// visible until it is back on.
    case localNetworkDenied
    /// The Mac was found but a connection to it never opened, several times in a row: the
    /// network keeps devices apart (guest or hotel Wi-Fi, a VPN, or a firewall on the Mac).
    /// Peer-to-peer Wi-Fi has already been tried.
    case networkBlocksDevices

    /// A sentence for the phone to show.
    public var message: String {
        switch self {
        case .localNetworkDenied:
            "Glasspad is not allowed to use your local network. Turn on Local Network for Glasspad in Settings > Privacy & Security > Local Network."
        case .networkBlocksDevices:
            "Your Mac was found, but this network does not let devices connect to each other (common on guest, hotel and office Wi-Fi, or with a VPN or firewall on). Glasspad keeps trying."
        }
    }

    /// kDNSServiceErr_PolicyDenied (dns_sd.h): what a browse or a Bonjour resolve reports when
    /// Local Network access is denied.
    static let dnsPolicyDenied: Int32 = -65570

    static func isLocalNetworkDenied(_ error: NWError) -> Bool {
        if case .dns(let code) = error { return code == dnsPolicyDenied }
        return false
    }

    /// The same, from a closed channel's reason text (it carries the NWError's description).
    static func isLocalNetworkDenied(reason: String?) -> Bool {
        guard let reason else { return false }
        return reason.contains("PolicyDenied") || reason.contains("\(dnsPolicyDenied)")
    }
}

/// Counts connects that failed before TCP opened and says what to do next.
struct ConnectFailureTracker: Equatable {
    /// After this many failures in a row, allow peer-to-peer Wi-Fi (AWDL).
    static let peerToPeerAfter = 2
    /// After this many, tell the user why (`LinkIssue.networkBlocksDevices`).
    static let reportAfter = 4

    private(set) var failures = 0

    mutating func record() -> (tryPeerToPeer: Bool, report: Bool) {
        failures += 1
        return (failures >= Self.peerToPeerAfter, failures >= Self.reportAfter)
    }
}

/// Reading NWBrowser's change lists.
enum BrowseChange {
    /// Whether any change adds or alters the service of the Mac with this ID (TXT `id`, upper case).
    static func mentions(_ macID: String, in changes: Set<NWBrowser.Result.Change>) -> Bool {
        changes.contains { change in
            switch change {
            case .added(let r): return id(of: r) == macID
            case .changed(_, let new, _): return id(of: new) == macID
            default: return false
            }
        }
    }

    static func id(of result: NWBrowser.Result) -> String? {
        if case .bonjour(let txt) = result.metadata { return txt["id"]?.uppercased() }
        return nil
    }
}
