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
/// Staying connected: the client reconnects with backoff after any drop, at once when the
/// network changes (Wi-Fi switch, wake from sleep) or when the Mac goes silent for
/// `GlasspadService.clientSilenceTimeout` (the Mac pings every second). Call `reconnectNow()`
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
        set { heartbeatsBox.set(newValue) }
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

    private let queue = DispatchQueue(label: "glasspad.client", qos: .userInteractive)
    private let delegateQueue: DispatchQueue
    private let delegateBox = Locked(WeakDelegate())
    private let stateBox = Locked(LinkState.idle)
    private let heartbeatsBox = Locked(false)
    private let sentBox = Locked(0)
    private let wakeBox = Locked<WakeTarget?>(nil)
    private let wakeHandler = Locked<(@Sendable (WakeTarget) -> Void)?>(nil)

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
    private var lastAppFrame: TimeInterval = 0
    private var lastSend: TimeInterval = 0
    private var lastTouchActivity: TimeInterval = 0
    private var keepalive: DispatchSourceTimer?
    private var attempt = 0
    private var reconnectWork: DispatchWorkItem?
    private var lastReceived: TimeInterval = 0
    private var pathMonitor: NWPathMonitor?
    private var lastPathSignature: String?
    private var lastGateways = ""
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
            guard case .connected = phase else { GPLog.log("send(frame): dropped, phase \(phase)"); return }
            let now = uptime()
            lastAppFrame = now
            lastTouchActivity = now
            var f = frame
            f.touches = Array(f.touches.prefix(TouchCodec.maxTouches))
            let active = f.touches.filter { $0.phase.isActive }
            lastSnapshot = active.isEmpty ? nil : TouchFrame(seq: 0, timestamp: f.timestamp, touches: active, surface: f.surface)
            sendTouches(f)
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
        teardown()
        startPathMonitor()
        open()
    }

    /// Drops whatever is in progress and connects again with no delay.
    private func restartNow() {
        guard target != nil else { return }
        teardown()
        attempt = 0
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
        defer {
            lastPathSignature = signature
            lastGateways = gateways
        }
        guard let previous = lastPathSignature, previous != signature else { return }
        // Joining another Wi-Fi network keeps the interface name (en0) but changes the router.
        let switched = previous.hasPrefix("false|") || (!lastGateways.isEmpty && lastGateways != gateways)
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
        switch target {
        case .bonjour?: browse()
        case .direct(let host, let port)?:
            guard let p = NWEndpoint.Port(rawValue: port) else { return setState(.failed("bad port")) }
            openTCP(.hostPort(host: NWEndpoint.Host(host), port: p))
        case nil: break
        }
    }

    private func browse() {
        setState(.searching)
        let gen = generation
        let params = NWParameters()
        params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: GlasspadService.bonjourType, domain: nil), using: params)
        let wanted = pairing.macID.uuidString.uppercased()
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, gen == self.generation, self.browser != nil else { return }
            GPLog.log("browse: \(results.count) result(s): \(results.map { r -> String in if case .bonjour(let t) = r.metadata { return "\(r.endpoint) id=\(t["id"] ?? "-")" }; return "\(r.endpoint)" }) wanted=\(wanted)")
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
            if case .failed(let e) = st { self.lost(gen, reason: "browse failed: \(e)") }
            GPLog.log("browser state: \(st)")
        }
        browser = b
        b.start(queue: queue)
    }

    private func openTCP(_ endpoint: NWEndpoint) {
        GPLog.log("tcp: opening \(endpoint)")
        setState(.connecting)
        let gen = generation
        let ch = ControlChannel(connection: NWConnection(to: endpoint, using: GlasspadService.tcpParameters()), queue: queue)
        ch.onReady = { [weak self] in self?.sendHello() }
        ch.onFrame = { [weak self] data in self?.handleFrame(data) }
        ch.onClosed = { [weak self] reason in self?.lost(gen, reason: reason ?? "closed") }
        channel = ch
        ch.start()
        queue.asyncAfter(deadline: .now() + GlasspadService.handshakeTimeout) { [weak self] in
            guard let self, gen == self.generation else { return }
            if case .connected = self.phase { return }
            self.channel?.close("handshake timeout")
        }
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
            openUDP()
            lastTouchActivity = uptime()
            startKeepalive()
            setState(.connected(rttMs: nil))
        case .connected?:
            guard crypto != nil, let plain = try? crypto!.openTCP(data) else { return }
            guard let msg = try? ControlMessage.from(jsonData: plain) else {
                if let wake = try? JSONDecoder().decode(WakeAnnouncement.self, from: plain), wake.t == "wake" {
                    wakeBox.set(wake.target)
                    let handler = wakeHandler.get()
                    delegateQueue.async { handler?(wake.target) }
                }
                return
            }
            switch msg {
            case .ping(let id): sendControl(.pong(id: id))
            case .pong: break
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
        let c = NWConnection(host: host, port: port, using: GlasspadService.udpParameters())
        c.stateUpdateHandler = { st in GPLog.log("udp state: \(st)") }
        c.start(queue: queue)
        udp = c
    }

    private func lost(_ gen: Int, reason: String) {
        GPLog.log("lost (gen \(gen) vs \(generation)): \(reason)")
        guard gen == generation else { return }
        teardown()
        scheduleReconnect(after: GlasspadService.backoff[min(attempt, GlasspadService.backoff.count - 1)])
    }

    private func scheduleReconnect(after delay: TimeInterval) {
        guard target != nil else { return }
        attempt += 1
        if case .bonjour? = target { setState(.searching) } else { setState(.connecting) }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.target != nil, self.channel == nil, self.browser == nil else { return }
            self.open()
        }
        reconnectWork = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func teardown() {
        generation += 1
        reconnectWork?.cancel()
        reconnectWork = nil
        browser?.cancel()
        browser = nil
        keepalive?.cancel()
        keepalive = nil
        udp?.cancel()
        udp = nil
        let ch = channel
        channel = nil
        ch?.close(nil)
        phase = nil
        crypto = nil
        lastSnapshot = nil
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

    private func sendTouches(_ f: TouchFrame) {
        var f = f
        seq &+= 1
        f.seq = seq
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
        keepalive?.cancel()
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        let i = GlasspadService.heartbeatInterval
        t.schedule(deadline: .now() + i, repeating: i, leeway: .milliseconds(2))
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
        guard now - lastSend >= GlasspadService.heartbeatInterval * 0.9 else { return }
        if var snap = lastSnapshot, now - lastAppFrame < Self.maxResendAge {
            snap.timestamp = now
            snap.touches = snap.touches.map { var t = $0; t.phase = .stationary; return t }
            sendTouches(snap)
        } else if heartbeatsEnabled, now - lastTouchActivity < GlasspadService.heartbeatIdleTimeout {
            seq &+= 1
            sendDatagram(TouchCodec.heartbeat(seq: seq, timestamp: now))
        }
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
