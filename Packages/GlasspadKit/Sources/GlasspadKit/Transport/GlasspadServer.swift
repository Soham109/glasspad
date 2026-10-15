#if os(macOS)
import Foundation
import Network

/// Mac side of the link: TCP control listener + UDP touch listener, Bonjour advertising,
/// handshake, one active phone session, ping/pong RTT stats.
///
/// Pairing: `pairKeyLookup(phoneID)` returns the stored key for a known phone. If it returns nil
/// and `pendingPairKey` is set (the QR code is on screen), the phone is accepted with that key
/// once it proves it holds it; then `onPaired` fires and `pendingPairKey` is cleared. The app
/// stores the new phone. `pairKeyLookup` runs on the server's private queue; it must not call
/// back into the server synchronously.
///
/// Thread safety: every public member may be called from any thread.
public final class GlasspadServer: @unchecked Sendable {
    public let macID: UUID
    public let macName: String

    public weak var delegate: (any GlasspadLinkDelegate)? {
        get { delegateBox.get().value }
        set { delegateBox.set(WeakDelegate(value: newValue)) }
    }
    /// The key in the QR code currently shown, accepted once for a phone the Mac does not know yet.
    public var pendingPairKey: Data? {
        get { pendingKey.get() }
        set { pendingKey.set(newValue) }
    }
    /// Called on the delegate queue after a new phone completed pairing.
    public var onPaired: (@Sendable (PairedPhone) -> Void)? {
        get { pairedHandler.get() }
        set { pairedHandler.set(newValue) }
    }
    /// Called on the delegate queue every time a session becomes the active one, including when a
    /// phone replaces another phone's session (the link state may stay `connected` through that).
    /// Reset per-phone state here: release buttons, send settings, push mode data.
    public var onSessionStarted: (@Sendable (PairedPhone) -> Void)? {
        get { sessionHandler.get() }
        set { sessionHandler.set(newValue) }
    }
    /// Wake-on-LAN details sent to the phone after each handshake. nil (the default) works them
    /// out from the interface the phone connected on; nothing is sent when that interface has no
    /// hardware or broadcast address (loopback, some VPNs).
    public var wakeTargetOverride: WakeTarget? {
        get { wakeOverride.get() }
        set { wakeOverride.set(newValue) }
    }

    public var state: LinkState { stateBox.get() }
    public var stats: LinkStats { statsBox.get() }
    /// Bound ports once listening.
    public var ports: (tcp: UInt16, udp: UInt16)? {
        let p = portsBox.get()
        guard let t = p.tcp, let u = p.udp else { return nil }
        return (t, u)
    }
    /// The phone of the active session.
    public var connectedPhone: PairedPhone? { phoneBox.get() }
    /// True once mDNSResponder confirmed the Bonjour service is published.
    public var isAdvertising: Bool { advertisingBox.get() }

    private let pairKeyLookup: @Sendable (String) -> Data?
    private let requestedTCPPort: UInt16
    private let requestedUDPPort: UInt16
    private let advertise: Bool
    private let queue = DispatchQueue(label: "glasspad.server", qos: .userInteractive)
    private let delegateQueue: DispatchQueue

    private let delegateBox = Locked(WeakDelegate())
    private let pendingKey = Locked<Data?>(nil)
    private let pairedHandler = Locked<(@Sendable (PairedPhone) -> Void)?>(nil)
    private let sessionHandler = Locked<(@Sendable (PairedPhone) -> Void)?>(nil)
    private let wakeOverride = Locked<WakeTarget?>(nil)
    private let stateBox = Locked(LinkState.idle)
    private let statsBox = Locked(LinkStats())
    private let portsBox = Locked<(tcp: UInt16?, udp: UInt16?)>((nil, nil))
    private let phoneBox = Locked<PairedPhone?>(nil)
    private let advertisingBox = Locked(false)

    // Queue-confined state.
    private var tcpListener: NWListener?
    private var udpListener: NWListener?
    private var udpPort: UInt16?
    private var handshaking: [ObjectIdentifier: Session] = [:]
    private var active: Session?
    private var pingTimer: DispatchSourceTimer?
    private var pingID: UInt32 = 0
    private var pingSent: [UInt32: TimeInterval] = [:]
    private var rtts: [Double] = []
    private var running = false
    /// Last authenticated TCP frame or touch datagram from the active phone.
    private var lastHeard: TimeInterval = 0
    /// The active session is closed after this long without hearing from the phone (it answers
    /// a ping every second, so this is several missed pongs). Internal so tests can shorten it.
    var silenceTimeout: TimeInterval = GlasspadService.serverSilenceTimeout
    /// Internal so tests can make the phone's liveness check fire.
    var pingInterval: TimeInterval = GlasspadService.pingInterval

    final class Session: @unchecked Sendable {
        enum Phase { case awaitingHello, awaitingConfirm, authenticated }
        let channel: ControlChannel
        var phase = Phase.awaitingHello
        var crypto: SessionCrypto?
        var phone: PairedPhone?
        var isNewPairing = false
        var udp: NWConnection?
        init(channel: ControlChannel) { self.channel = channel }
    }

    /// - Parameters:
    ///   - tcpPort, udpPort: 0 picks free ports.
    ///   - advertise: publish `_glasspad._tcp` over Bonjour (tests turn it off).
    ///   - pairKeyLookup: phoneID -> stored pair key, nil if unknown or revoked.
    public init(macID: UUID, macName: String, tcpPort: UInt16 = 0, udpPort: UInt16 = 0, advertise: Bool = true,
                delegateQueue: DispatchQueue = .main, pairKeyLookup: @escaping @Sendable (String) -> Data?) {
        self.macID = macID
        self.macName = macName
        self.requestedTCPPort = tcpPort
        self.requestedUDPPort = udpPort
        self.advertise = advertise
        self.delegateQueue = delegateQueue
        self.pairKeyLookup = pairKeyLookup
    }

    deinit {
        tcpListener?.cancel()
        udpListener?.cancel()
        pingTimer?.cancel()
    }

    /// Starts both listeners. State becomes `.searching` once the TCP listener is ready.
    public func start() throws {
        let tcp = try NWListener(using: GlasspadService.tcpParameters(), on: Self.port(requestedTCPPort))
        let udp = try NWListener(using: GlasspadService.udpParameters(), on: Self.port(requestedUDPPort))
        if advertise {
            var txt = NWTXTRecord()
            txt["id"] = macID.uuidString
            txt["v"] = "\(GlasspadService.protocolVersion)"
            tcp.service = NWListener.Service(name: macName, type: GlasspadService.bonjourType, domain: nil, txtRecord: txt)
            tcp.serviceRegistrationUpdateHandler = { [weak self] change in
                switch change {
                case .add: self?.advertisingBox.set(true)
                case .remove: self?.advertisingBox.set(false)
                @unknown default: break
                }
            }
        }
        tcp.stateUpdateHandler = { [weak self] st in self?.listenerState(st, tcp: true) }
        udp.stateUpdateHandler = { [weak self] st in self?.listenerState(st, tcp: false) }
        tcp.newConnectionHandler = { [weak self] c in self?.acceptTCP(c) }
        udp.newConnectionHandler = { [weak self] c in self?.acceptUDP(c) }
        queue.sync {
            running = true
            tcpListener = tcp
            udpListener = udp
        }
        tcp.start(queue: queue)
        udp.start(queue: queue)
    }

    /// Closes the session and both listeners.
    public func stop() {
        queue.sync {
            running = false
            if let s = active {
                active = nil
                phoneBox.set(nil)
                pingTimer?.cancel()
                pingTimer = nil
                s.udp?.cancel()
                byeAndClose(s, reason: "server stopped")
            }
            for s in handshaking.values { s.channel.close("stopped") }
            handshaking = [:]
            tcpListener?.cancel()
            udpListener?.cancel()
            tcpListener = nil
            udpListener = nil
            udpPort = nil
            portsBox.set((nil, nil))
            advertisingBox.set(false)
            setState(.idle)
        }
    }

    /// Sends a control message to the connected phone (dropped when none).
    public func send(_ message: ControlMessage) {
        queue.async { [self] in
            guard let s = active else { return }
            send(message, on: s)
        }
    }

    /// Sends `bye` and closes the active session; the phone will reconnect unless rejected.
    public func disconnect(reason: String) {
        queue.async { [self] in
            guard let s = active else { return }
            byeAndClose(s, reason: reason)
        }
    }

    // MARK: Listeners

    private static func port(_ p: UInt16) -> NWEndpoint.Port {
        p == 0 ? .any : NWEndpoint.Port(rawValue: p) ?? .any
    }

    private func listenerState(_ st: NWListener.State, tcp: Bool) {
        switch st {
        case .ready:
            let port = (tcp ? tcpListener?.port : udpListener?.port)?.rawValue
            portsBox.mutate { if tcp { $0.tcp = port } else { $0.udp = port } }
            if !tcp { udpPort = port }
            if tcp, active == nil { setState(.searching) }
        case .failed(let e):
            setState(.failed("\(tcp ? "TCP" : "UDP") listener: \(e)"))
        default:
            break
        }
    }

    // MARK: TCP sessions

    private func acceptTCP(_ conn: NWConnection) {
        GPLog.log("server: tcp from \(conn.endpoint)")
        guard running else { conn.cancel(); return }
        let s = Session(channel: ControlChannel(connection: conn, queue: queue))
        let key = ObjectIdentifier(s)
        handshaking[key] = s
        // Weak, not unowned: a replaced session is released while its last bye is still in
        // flight, and the channel's close callback arrives after that.
        s.channel.onFrame = { [weak self, weak s] data in
            guard let s else { return }
            self?.handleFrame(data, from: s)
        }
        s.channel.onClosed = { [weak self, weak s] reason in
            guard let s else { return }
            self?.closed(s, reason: reason)
        }
        s.channel.start()
        queue.asyncAfter(deadline: .now() + GlasspadService.handshakeTimeout) { [weak s] in
            guard let s, s.phase != .authenticated else { return }
            s.channel.close("handshake timeout")
        }
    }

    private func handleFrame(_ data: Data, from s: Session) {
        switch s.phase {
        case .awaitingHello:
            handleHello(data, from: s)
        case .awaitingConfirm:
            guard var c = s.crypto, let plain = try? c.openTCP(data), plain == handshakeConfirmToken else {
                statsBox.mutate { $0.authFailures += 1 }
                s.channel.close("key confirmation failed")
                return
            }
            s.crypto = c
            s.phase = .authenticated
            guard let phone = s.phone else { return }
            if s.isNewPairing {
                pendingKey.mutate { if $0 == phone.pairKey { $0 = nil } }
                let handler = pairedHandler.get()
                delegateQueue.async { handler?(phone) }
            }
            sendRaw(handshakeConfirmToken, on: s)
            activate(s)
        case .authenticated:
            guard s.crypto != nil else { return }
            let plain: Data
            do {
                plain = try s.crypto!.openTCP(data)
            } catch SessionCryptoError.replay {
                statsBox.mutate { $0.replayDrops += 1 }
                return
            } catch {
                statsBox.mutate { $0.authFailures += 1 }
                return
            }
            if s === active { lastHeard = uptime() }
            guard let msg = try? ControlMessage.from(jsonData: plain) else {
                statsBox.mutate { $0.malformed += 1 }
                return
            }
            switch msg {
            case .pong(let id): handlePong(id)
            case .ping(let id): send(.pong(id: id), on: s)
            case .bye:
                guard s === active else { return s.channel.close("bye") }
                delegateQueue.async { [weak self] in self?.delegate?.link(didReceive: msg) }
                s.channel.close("phone said bye")
            default:
                guard s === active else { return }
                delegateQueue.async { [weak self] in self?.delegate?.link(didReceive: msg) }
            }
        }
    }

    private func handleHello(_ data: Data, from s: Session) {
        guard let hello = try? JSONDecoder().decode(PhoneHello.self, from: data), hello.t == "hello" else {
            return reject(s, "bad hello")
        }
        guard hello.v == GlasspadService.protocolVersion else { return reject(s, "unsupported version \(hello.v)") }
        guard hello.macID == macID else { return reject(s, "wrong mac") }
        guard hello.nonce.count == 16 else { return reject(s, "bad nonce") }
        guard let udpPort else { return reject(s, "not ready") }
        var key = pairKeyLookup(hello.phoneID)
        var isNew = false
        if key == nil, let pend = pendingKey.get() {
            key = pend
            isNew = true
        }
        guard let key else { return reject(s, "not paired") }
        let macNonce = randomBytes(16)
        s.crypto = SessionCrypto(pairKey: key, phoneNonce: hello.nonce, macNonce: macNonce, role: .mac)
        s.phone = PairedPhone(phoneID: hello.phoneID, phoneName: hello.phoneName, pairKey: key)
        s.isNewPairing = isNew
        s.phase = .awaitingConfirm
        if active == nil { setState(.connecting) }
        if let json = try? JSONEncoder().encode(MacHello(nonce: macNonce, udpPort: udpPort)) {
            s.channel.send(json)
        }
    }

    private func reject(_ s: Session, _ reason: String) {
        GPLog.log("server: reject \(reason)")
        guard let json = try? JSONEncoder().encode(HandshakeReject(reason: reason)) else {
            return s.channel.close("rejected: \(reason)")
        }
        s.channel.sendThenClose(json, reason: "rejected: \(reason)")
    }

    private func activate(_ s: Session) {
        handshaking.removeValue(forKey: ObjectIdentifier(s))
        if let old = active {
            active = nil
            old.udp?.cancel()
            byeAndClose(old, reason: GlasspadService.replacedReason)
        }
        active = s
        phoneBox.set(s.phone)
        rtts = []
        pingSent = [:]
        lastHeard = uptime()
        statsBox.mutate { $0.rttMedianMs = nil; $0.rttP95Ms = nil; $0.rttSamples = 0 }
        setState(.connected(rttMs: nil))
        if let phone = s.phone {
            let handler = sessionHandler.get()
            delegateQueue.async { handler?(phone) }
        }
        sendWakeTarget(on: s)
        startPinging()
    }

    /// Tells the phone how to wake this Mac (sealed; handled inside the client, never delivered
    /// as a `ControlMessage`).
    private func sendWakeTarget(on s: Session) {
        var target = wakeOverride.get()
        if target == nil, case .hostPort(let host, _)? = s.channel.connection.currentPath?.localEndpoint {
            target = WakeOnLAN.target(forLocalAddress: Self.string(host))
        }
        guard let target, let json = try? JSONEncoder().encode(WakeAnnouncement(target: target)) else { return }
        sendRaw(json, on: s)
    }

    static func string(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let a): return "\(a)"
        case .ipv6(let a): return "\(a)"
        case .name(let n, _): return n
        @unknown default: return "\(host)"
        }
    }

    private func closed(_ s: Session, reason: String?) {
        handshaking.removeValue(forKey: ObjectIdentifier(s))
        guard s === active else {
            if active == nil, running, case .connecting = stateBox.get(), handshaking.isEmpty { setState(.searching) }
            return
        }
        active = nil
        s.udp?.cancel()
        phoneBox.set(nil)
        pingTimer?.cancel()
        pingTimer = nil
        setState(running ? .searching : .idle)
    }

    private func byeAndClose(_ s: Session, reason: String) {
        guard s.phase == .authenticated, s.crypto != nil,
              let plain = try? ControlMessage.bye(reason: reason).jsonData(),
              let sealed = try? s.crypto!.sealTCP(plain) else { return s.channel.close(reason) }
        s.channel.sendThenClose(sealed, reason: reason)
    }

    private func send(_ message: ControlMessage, on s: Session) {
        guard s.phase == .authenticated, let plain = try? message.jsonData() else { return }
        sendRaw(plain, on: s)
    }

    private func sendRaw(_ plain: Data, on s: Session) {
        guard s.crypto != nil, let sealed = try? s.crypto!.sealTCP(plain) else { return }
        s.channel.send(sealed)
    }

    // MARK: RTT

    private func startPinging() {
        pingTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + pingInterval, repeating: pingInterval)
        t.setEventHandler { [weak self] in self?.sendPing() }
        t.resume()
        pingTimer = t
    }

    private func sendPing() {
        guard let s = active else { return }
        if uptime() - lastHeard > silenceTimeout {
            // The phone slept, left Wi-Fi or was suspended. Close so the Mac shows it and
            // releases anything held; a live phone reconnects on its own.
            byeAndClose(s, reason: "phone went silent")
            return
        }
        pingID &+= 1
        pingSent[pingID] = uptime()
        if pingSent.count > 30, let oldest = pingSent.min(by: { $0.value < $1.value }) {
            pingSent.removeValue(forKey: oldest.key)
        }
        send(.ping(id: pingID), on: s)
    }

    private func handlePong(_ id: UInt32) {
        guard let sent = pingSent.removeValue(forKey: id) else { return }
        rtts.append((uptime() - sent) * 1000)
        if rtts.count > 120 { rtts.removeFirst(rtts.count - 120) }
        let sorted = rtts.sorted()
        let median = percentile(sorted, 0.5)
        statsBox.mutate {
            $0.rttMedianMs = median
            $0.rttP95Ms = percentile(sorted, 0.95)
            $0.rttSamples = sorted.count
        }
        setState(.connected(rttMs: median))
    }

    // MARK: UDP

    private func acceptUDP(_ conn: NWConnection) {
        guard running else { conn.cancel(); return }
        conn.start(queue: queue)
        receive(on: conn)
    }

    private func receive(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty { self.handleDatagram(data, from: conn) }
            if error == nil, conn.state != .cancelled { self.receive(on: conn) }
        }
    }

    private func handleDatagram(_ data: Data, from conn: NWConnection) {
        guard let s = active, s.crypto != nil else {
            GPLog.log("server: udp datagram with no active session")
            statsBox.mutate { $0.authFailures += 1 }
            conn.cancel()
            return
        }
        let plain: Data
        do {
            plain = try s.crypto!.openUDP(data)
        } catch SessionCryptoError.replay {
            statsBox.mutate { $0.replayDrops += 1 }
            return
        } catch {
            GPLog.log("server: udp open failed: \(error)")
            statsBox.mutate { $0.authFailures += 1 }
            if s.udp !== conn { conn.cancel() }
            return
        }
        lastHeard = uptime()
        if s.udp !== conn {          // learn (or re-learn after roaming) the phone's UDP address
            s.udp?.cancel()
            s.udp = conn
        }
        switch try? TouchCodec.decodePacket(plain) {
        case .touches(let frame):
            let n = statsBox.mutate { st -> Int in st.framesReceived += 1; return st.framesReceived }
            if n == 1 || n % 200 == 0 { GPLog.log("server: \(n) touch frames received") }
            delegateQueue.async { [weak self] in self?.delegate?.link(didReceive: frame) }
        case .heartbeat:
            let n = statsBox.mutate { st -> Int in st.heartbeatsReceived += 1; return st.heartbeatsReceived }
            if n == 1 || n % 500 == 0 { GPLog.log("server: \(n) heartbeats received") }
        case nil:
            statsBox.mutate { $0.malformed += 1 }
        }
    }

    // MARK: State

    private func setState(_ new: LinkState) {
        let changed = stateBox.mutate { st -> Bool in
            guard st != new else { return false }
            st = new
            return true
        }
        guard changed else { return }
        GPLog.log("server state -> \(new)")
        delegateQueue.async { [weak self] in self?.delegate?.link(didChangeState: new) }
    }
}
#endif
