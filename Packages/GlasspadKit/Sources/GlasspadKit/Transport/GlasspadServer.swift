#if os(macOS)
import Foundation
import Network

/// Mac side of the link: TCP control listener + UDP touch listener, Bonjour advertising,
/// handshake, one active phone session, ping/pong RTT stats.
///
/// Pairing: `keyLookup(phoneID)` returns the stored key for a known phone. If there is none and
/// a pairing code is armed (`armPairing`, the QR code is on screen and not expired), a phone that
/// proves it holds the code's key is a new phone. With protocol 2 the two sides then agree a new
/// pair key (`KeyAgreement`), `approveNewPhone` asks the person at the Mac, `saveKey` stores the
/// agreed key, and `onPaired` fires. The code's key is never kept as the phone's key.
///
/// Phones paired before protocol 2 keep their code's key until their next protocol 2
/// connection, which replaces it the same way (no question asked: they were allowed already).
/// `keyLookup` and `saveKey` run on the server's private queue; they must not call back into the
/// server synchronously.
///
/// Thread safety: every public member may be called from any thread.
public final class GlasspadServer: @unchecked Sendable {
    public let macID: UUID
    public let macName: String

    public weak var delegate: (any GlasspadLinkDelegate)? {
        get { delegateBox.get().value }
        set { delegateBox.set(WeakDelegate(value: newValue)) }
    }
    /// The key in the QR code currently shown, accepted once for a phone the Mac does not know yet,
    /// and only until the code expires (nil once it has). Setting it arms it for
    /// `GlasspadService.pairingCodeLifetime`; `armPairing` takes an explicit end.
    public var pendingPairKey: Data? {
        get { pendingKey.get().flatMap { Date() < $0.expiresAt ? $0.key : nil } }
        set { pendingKey.set(newValue.map { ($0, Date().addingTimeInterval(GlasspadService.pairingCodeLifetime)) }) }
    }
    /// Arms a pairing code's key until `expiresAt` (wall-clock time, so a Mac that slept past it,
    /// or a main thread that stalled, cannot keep the code alive).
    public func armPairing(key: Data, expiresAt: Date) { pendingKey.set((key, expiresAt)) }
    /// Asked on the delegate queue before a new phone is saved: answer true to allow it. Answer
    /// within `GlasspadService.approvalTimeout`; later, or never, counts as no. nil allows every
    /// phone that proved it holds the code (tests only).
    public var approveNewPhone: (@Sendable (PairedPhone, @escaping @Sendable (Bool) -> Void) -> Void)? {
        get { approver.get() }
        set { approver.set(newValue) }
    }
    /// Called on the delegate queue when a new phone that proved it holds the code was not
    /// saved: Don't Allow, no answer, the phone left while waiting, or the key could not be saved.
    public var onPairingFailed: (@Sendable (PairedPhone, PairingFailure) -> Void)? {
        get { failedHandler.get() }
        set { failedHandler.set(newValue) }
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

    private let keyLookup: @Sendable (String) -> PhoneKey?
    private let saveKey: (@Sendable (PairedPhone, PhoneKey) throws -> Void)?
    private let requestedTCPPort: UInt16
    private let requestedUDPPort: UInt16
    private let advertise: Bool
    private let queue = DispatchQueue(label: "glasspad.server", qos: .userInteractive)
    private let delegateQueue: DispatchQueue

    private let delegateBox = Locked(WeakDelegate())
    private let pendingKey = Locked<(key: Data, expiresAt: Date)?>(nil)
    private let approver = Locked<(@Sendable (PairedPhone, @escaping @Sendable (Bool) -> Void) -> Void)?>(nil)
    private let failedHandler = Locked<(@Sendable (PairedPhone, PairingFailure) -> Void)?>(nil)
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
    /// Restart bookkeeping per listener (key: true for TCP).
    private var listenerFailures: [Bool: Int] = [:]
    private var listenerRestart: [Bool: DispatchWorkItem] = [:]
    /// Why a listener is down, until it is back.
    private var listenerFailure: String?
    /// Pauses before replacing a failed listener; the last one repeats. Internal for tests.
    var listenerBackoff: [TimeInterval] = [0.5, 1, 2, 5, 10]
    /// Last authenticated TCP frame, touch datagram or partial frame from the active phone.
    private var lastHeard: TimeInterval = 0
    /// How late the first touch after a quiet spell arrives, for the log (queue-confined).
    private var restProbe = RestWakeProbe()
    /// The active session is closed after this long without hearing from the phone (it answers
    /// a ping every second, so this is several missed pongs). Internal so tests can shorten it.
    var silenceTimeout: TimeInterval = GlasspadService.serverSilenceTimeout
    /// Internal so tests can make the phone's liveness check fire.
    var pingInterval: TimeInterval = GlasspadService.pingInterval
    /// A connection that has not finished the handshake by then is closed. Internal for tests.
    var handshakeTimeout: TimeInterval = GlasspadService.handshakeTimeout
    /// Most connections allowed to be mid-handshake at once (anyone on the network can open
    /// one). Over the cap the oldest one that has not even sent its hello is dropped.
    static let maxPendingHandshakes = 8

    final class Session: @unchecked Sendable {
        enum Phase { case awaitingHello, awaitingConfirm, awaitingApproval, authenticated }
        /// Where a key the phone might hold came from.
        enum KeySource { case stored, previous, pending }
        /// One key the phone might hold, with the session keys it gives. The phone's
        /// confirmation shows which one it is.
        struct Candidate {
            var source: KeySource
            var key: Data
            var crypto: SessionCrypto
            /// The pair key agreed on this connection (protocol 2 with rekey).
            var newKey: Data?
        }
        let channel: ControlChannel
        var phase = Phase.awaitingHello
        var crypto: SessionCrypto?
        var candidates: [Candidate] = []
        /// The candidate the phone's confirmation matched.
        var matched: Candidate?
        var phone: PairedPhone?
        var isNewPairing = false
        /// After a rekey: the phone has not said it saved the new key yet.
        var awaitingKeySaved = false
        var udp: NWConnection?
        let acceptedAt = uptime()
        init(channel: ControlChannel) { self.channel = channel }
    }

    /// - Parameters:
    ///   - tcpPort, udpPort: 0 picks free ports.
    ///   - advertise: publish `_glasspad._tcp` over Bonjour (tests turn it off).
    ///   - keyLookup: phoneID -> what is stored for that phone, nil if unknown or revoked.
    ///   - saveKey: stores a phone's key (a new phone after it was allowed, an agreed key that
    ///     replaces a code's key, or the same key once the old one can go). Throwing refuses the
    ///     connection. nil keeps nothing: then only new phones get an agreed key (in `onPaired`).
    public init(macID: UUID, macName: String, tcpPort: UInt16 = 0, udpPort: UInt16 = 0, advertise: Bool = true,
                delegateQueue: DispatchQueue = .main, keyLookup: @escaping @Sendable (String) -> PhoneKey?,
                saveKey: (@Sendable (PairedPhone, PhoneKey) throws -> Void)?) {
        self.macID = macID
        self.macName = macName
        self.requestedTCPPort = tcpPort
        self.requestedUDPPort = udpPort
        self.advertise = advertise
        self.delegateQueue = delegateQueue
        self.keyLookup = keyLookup
        self.saveKey = saveKey
    }

    /// Tests: phones with fixed keys from pairing codes, and nothing saved.
    public convenience init(macID: UUID, macName: String, tcpPort: UInt16 = 0, udpPort: UInt16 = 0, advertise: Bool = true,
                            delegateQueue: DispatchQueue = .main, pairKeyLookup: @escaping @Sendable (String) -> Data?) {
        self.init(macID: macID, macName: macName, tcpPort: tcpPort, udpPort: udpPort, advertise: advertise,
                  delegateQueue: delegateQueue, keyLookup: { id in pairKeyLookup(id).map { PhoneKey(key: $0, agreed: false) } },
                  saveKey: nil)
    }

    deinit {
        tcpListener?.cancel()
        udpListener?.cancel()
        pingTimer?.cancel()
    }

    /// Starts both listeners. State becomes `.searching` once both are ready.
    public func start() throws {
        let tcp = try makeListener(tcp: true)
        let udp = try makeListener(tcp: false)
        queue.sync {
            running = true
            tcpListener = tcp
            udpListener = udp
            listenerFailures = [:]
            listenerFailure = nil
        }
        tcp.start(queue: queue)
        udp.start(queue: queue)
    }

    private func makeListener(tcp isTCP: Bool) throws -> NWListener {
        // Peer-to-peer stays allowed on the listeners so a phone with no shared network can
        // still connect; phones only use it as a fallback (GlasspadService.tcpParameters).
        let l = isTCP
            ? try NWListener(using: GlasspadService.tcpParameters(peerToPeer: true), on: Self.port(requestedTCPPort))
            : try NWListener(using: GlasspadService.udpParameters(peerToPeer: true), on: Self.port(requestedUDPPort))
        if isTCP, advertise {
            var txt = NWTXTRecord()
            txt["id"] = macID.uuidString
            txt["v"] = "\(GlasspadService.protocolVersion)"
            l.service = NWListener.Service(name: macName, type: GlasspadService.bonjourType, domain: nil, txtRecord: txt)
            l.serviceRegistrationUpdateHandler = { [weak self, weak l] change in
                guard let self, let l, l === self.tcpListener else { return }
                switch change {
                case .add: self.advertisingBox.set(true)
                case .remove: self.advertisingBox.set(false)
                @unknown default: break
                }
            }
        }
        // Callbacks from a listener that was already replaced are ignored.
        l.stateUpdateHandler = { [weak self, weak l] st in
            guard let self, let l else { return }
            self.listenerState(st, of: l, tcp: isTCP)
        }
        l.newConnectionHandler = { [weak self] c in
            if isTCP { self?.acceptTCP(c) } else { self?.acceptUDP(c) }
        }
        return l
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
                byeAndClose(s, reason: GlasspadService.stoppedReason)
            }
            for s in handshaking.values { s.channel.close("stopped") }
            handshaking = [:]
            tcpListener?.cancel()
            udpListener?.cancel()
            tcpListener = nil
            udpListener = nil
            for w in listenerRestart.values { w.cancel() }
            listenerRestart = [:]
            listenerFailures = [:]
            listenerFailure = nil
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

    /// Tests only: seals this JSON as one control message to the phone, as a build with other
    /// message types would send it.
    func sendRawJSONForTesting(_ json: Data) {
        queue.async { [self] in
            guard let s = active, s.phase == .authenticated else { return }
            sendRaw(json, on: s)
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

    private func listenerState(_ st: NWListener.State, of l: NWListener, tcp: Bool) {
        guard l === (tcp ? tcpListener : udpListener) else { return }
        switch st {
        case .ready:
            let port = l.port?.rawValue
            portsBox.mutate { if tcp { $0.tcp = port } else { $0.udp = port } }
            if !tcp { udpPort = port }
            listenerFailures[tcp] = 0
            guard tcpListener?.port != nil, udpPort != nil else { return }
            listenerFailure = nil
            if active == nil { setState(.searching) }
        case .failed(let e):
            listenerFailed(tcp: tcp, error: "\(e)")
        default:
            break
        }
    }

    /// A listener stopped for good (the network went away, the port was taken): replace it after
    /// a growing pause. The state shows the failure meanwhile, unless a phone is connected.
    private func listenerFailed(tcp: Bool, error: String) {
        let name = tcp ? "TCP" : "UDP"
        GPLog.log("server: \(name) listener failed: \(error)")
        if tcp {
            tcpListener?.cancel()
            tcpListener = nil
            advertisingBox.set(false)
            portsBox.mutate { $0.tcp = nil }
        } else {
            udpListener?.cancel()
            udpListener = nil
            udpPort = nil
            portsBox.mutate { $0.udp = nil }
        }
        guard running else { return }
        listenerFailure = "\(name) listener: \(error)"
        if !tcp, let s = active {
            // The phone's touch packets go to the old UDP port; make it reconnect and learn the
            // new one once the listener is back.
            active = nil
            phoneBox.set(nil)
            pingTimer?.cancel()
            pingTimer = nil
            s.udp?.cancel()
            byeAndClose(s, reason: "touch listener restarted")
        }
        if active == nil { setState(restingState) }
        let n = listenerFailures[tcp, default: 0]
        listenerFailures[tcp] = n + 1
        let delay = listenerBackoff[min(n, listenerBackoff.count - 1)]
        listenerRestart[tcp]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.restartListener(tcp: tcp) }
        listenerRestart[tcp] = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func restartListener(tcp: Bool) {
        listenerRestart[tcp] = nil
        guard running, (tcp ? tcpListener : udpListener) == nil else { return }
        do {
            let l = try makeListener(tcp: tcp)
            if tcp { tcpListener = l } else { udpListener = l }
            l.start(queue: queue)
        } catch {
            listenerFailed(tcp: tcp, error: "\(error)")
        }
    }

    /// The state with no active session.
    private var restingState: LinkState {
        guard running else { return .idle }
        return listenerFailure.map { .failed($0) } ?? .searching
    }

    /// Test hook: behave as if a listener reported `.failed`.
    func failListenerForTesting(tcp: Bool) {
        queue.async { [self] in
            guard let l = tcp ? tcpListener : udpListener else { return }
            listenerState(.failed(.posix(.ENETDOWN)), of: l, tcp: tcp)
        }
    }

    // MARK: TCP sessions

    private func acceptTCP(_ conn: NWConnection) {
        let viaAWDL = "\(conn.endpoint)".contains("%awdl")
        GPLog.log("server: tcp from \(conn.endpoint)\(viaAWDL ? " (peer-to-peer Wi-Fi: expect latency spikes)" : "")")
        guard running else { conn.cancel(); return }
        if handshaking.count >= Self.maxPendingHandshakes {
            // Drop the oldest connection still waiting for a hello (a real phone says hello as
            // soon as it connects); refuse this one when every slot is further along.
            guard let oldest = handshaking.values.filter({ $0.phase == .awaitingHello }).min(by: { $0.acceptedAt < $1.acceptedAt })
            else {
                GPLog.log("server: refused tcp from \(conn.endpoint), too many handshakes in progress")
                conn.cancel()
                return
            }
            oldest.channel.close("too many handshakes in progress")
        }
        let s = Session(channel: ControlChannel(connection: conn, queue: queue))
        s.channel.maxIncomingFrame = GlasspadService.maxHandshakeFrameLength
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
        // Bytes of a large message still on its way (a clipboard image pushed over slow Wi-Fi)
        // count as hearing the phone, but only on the active, authenticated session: its pongs
        // are queued behind that message.
        s.channel.onBytes = { [weak self, weak s] in
            guard let self, let s, s === self.active else { return }
            self.lastHeard = uptime()
        }
        s.channel.start()
        queue.asyncAfter(deadline: .now() + handshakeTimeout) { [weak s] in
            guard let s, s.phase == .awaitingHello || s.phase == .awaitingConfirm else { return }
            s.channel.close("handshake timeout")
        }
    }

    private func handleFrame(_ data: Data, from s: Session) {
        switch s.phase {
        case .awaitingHello:
            handleHello(data, from: s)
        case .awaitingConfirm:
            handleConfirm(data, from: s)
        case .awaitingApproval:
            // The phone sends nothing more until the Mac answers.
            s.channel.close("unexpected frame while waiting for approval")
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
            case .unknown(let type):
                // The phone saved the agreed key; anything else is a newer phone's message.
                if type == "keySaved" { keySaved(on: s) }
                return
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

    /// Tests only: refuse protocol 2 the way a 0.2.x Mac does. Set before phones connect.
    var acceptsOnlyProtocol1ForTesting = false

    private func handleHello(_ data: Data, from s: Session) {
        guard let hello = try? JSONDecoder().decode(PhoneHello.self, from: data), hello.t == "hello" else {
            return reject(s, "bad hello")
        }
        let legacy = hello.v == GlasspadService.legacyProtocolVersion
        guard hello.v == GlasspadService.protocolVersion || legacy, !(acceptsOnlyProtocol1ForTesting && !legacy) else {
            return reject(s, "unsupported version \(hello.v)")
        }
        guard hello.macID == macID else { return reject(s, "wrong mac") }
        guard hello.nonce.count == 16 else { return reject(s, "bad nonce") }
        guard let udpPort else { return reject(s, "not ready") }
        let stored = keyLookup(hello.phoneID)
        let pending = pendingPairKey
        let macNonce = randomBytes(16)
        let reply: MacHello
        if legacy {
            // A 0.2.x phone: only a key it was paired with before, and only while that key is
            // still a code's key. Pairing (or a phone already moved to an agreed key) needs 2.
            if acceptsOnlyProtocol1ForTesting, stored == nil, let pending {
                // As 0.2.x did: the code's key becomes the phone's key.
                s.candidates = [Session.Candidate(source: .pending, key: pending,
                                                  crypto: SessionCrypto(pairKey: pending, phoneNonce: hello.nonce,
                                                                        macNonce: macNonce, role: .mac))]
            }
            guard let stored else {
                if !s.candidates.isEmpty {
                    return finishHello(s, hello, MacHello(v: GlasspadService.legacyProtocolVersion, nonce: macNonce, udpPort: udpPort))
                }
                return reject(s, pending == nil ? "not paired" : GlasspadService.updatePhoneReason)
            }
            guard !stored.agreed else { return reject(s, GlasspadService.updatePhoneReason) }
            s.candidates = [Session.Candidate(source: .stored, key: stored.key,
                                              crypto: SessionCrypto(pairKey: stored.key, phoneNonce: hello.nonce,
                                                                    macNonce: macNonce, role: .mac))]
            reply = MacHello(v: GlasspadService.legacyProtocolVersion, nonce: macNonce, udpPort: udpPort)
        } else {
            guard let phonePublic = hello.kx, phonePublic.count == KeyAgreement.publicKeyLength else {
                return reject(s, "bad key")
            }
            // Rekey when the phone's key is still a code's key. Without a place to save keys
            // (tests) only a brand new phone is rekeyed, as `onPaired` hands its key over.
            let rekey = hello.rekey == true && (saveKey != nil || stored == nil)
            var keys: [(Session.KeySource, Data)] = []
            if let stored { keys.append((.stored, stored.key)) }
            if rekey, let previous = stored?.previous, previous != stored?.key { keys.append((.previous, previous)) }
            if rekey, let pending, pending != stored?.key { keys.append((.pending, pending)) }
            guard !keys.isEmpty else { return reject(s, "not paired") }
            let mine = KeyAgreement.makeKeyPair()
            let macPublic = mine.publicKey.rawRepresentation
            do {
                s.candidates = try keys.map { source, key in
                    let derived = try KeyAgreement.derive(privateKey: mine, peerPublicKey: phonePublic, pairKey: key,
                                                          phoneNonce: hello.nonce, macNonce: macNonce,
                                                          phonePublicKey: phonePublic, macPublicKey: macPublic, rekey: rekey)
                    return Session.Candidate(source: source, key: key,
                                             crypto: SessionCrypto(sessionKey: derived.sessionKey, role: .mac),
                                             newKey: derived.newPairKey)
                }
            } catch {
                return reject(s, "bad key")
            }
            reply = MacHello(nonce: macNonce, udpPort: udpPort, kx: macPublic, rekey: rekey)
        }
        finishHello(s, hello, reply)
    }

    private func finishHello(_ s: Session, _ hello: PhoneHello, _ reply: MacHello) {
        s.phone = PairedPhone(phoneID: hello.phoneID, phoneName: hello.phoneName, pairKey: Data())
        s.phase = .awaitingConfirm
        if active == nil { setState(.connecting) }
        if let json = try? JSONEncoder().encode(reply) {
            s.channel.send(json)
        }
    }

    /// The phone's key confirmation: find which key it holds, then let it in (a new phone once
    /// the person at the Mac allows it).
    private func handleConfirm(_ data: Data, from s: Session) {
        var found: Session.Candidate?
        for var c in s.candidates {
            if let plain = try? c.crypto.openTCP(data), plain == handshakeConfirmToken {
                found = c
                break
            }
        }
        s.candidates = []
        guard let match = found, var phone = s.phone else {
            statsBox.mutate { $0.authFailures += 1 }
            s.channel.close("key confirmation failed")
            return
        }
        s.crypto = match.crypto
        s.matched = match
        s.isNewPairing = match.source == .pending
        phone.pairKey = match.newKey ?? match.key
        s.phone = phone
        if !s.isNewPairing {
            // The phone may have been revoked since its hello: ask again, so a Forget that lands
            // mid-handshake never lets the phone in for the whole session.
            let now = keyLookup(phone.phoneID)
            let still = match.source == .stored ? now?.key == match.key : now?.previous == match.key
            guard still else {
                s.channel.close("revoked during handshake")
                return
            }
            return admit(s)
        }
        // A new phone: the code is used up, whatever the answer.
        pendingKey.mutate { if $0?.key == match.key { $0 = nil } }
        guard let approve = approver.get() else { return admit(s) }
        s.phase = .awaitingApproval
        sendRaw(approvalWaitToken, on: s)
        GPLog.log("server: asking whether to allow \(phone.phoneName)")
        queue.asyncAfter(deadline: .now() + GlasspadService.approvalTimeout + 5) { [weak self, weak s] in
            guard let self, let s else { return }
            self.approvalAnswered(s, allowed: false)
        }
        let answer: @Sendable (Bool) -> Void = { [weak self, weak s] allowed in
            guard let server = self else { return }
            server.queue.async { [weak s] in
                guard let s else { return }
                server.approvalAnswered(s, allowed: allowed)
            }
        }
        delegateQueue.async { approve(phone, answer) }
    }

    private func approvalAnswered(_ s: Session, allowed: Bool) {
        guard s.phase == .awaitingApproval, handshaking[ObjectIdentifier(s)] === s, let phone = s.phone else { return }
        if allowed { return admit(s) }
        GPLog.log("server: \(phone.phoneName) was not allowed")
        s.phase = .awaitingHello      // so closing it reports nothing more
        pairingFailed(phone, .notAllowed)
        guard s.crypto != nil, let sealed = try? s.crypto!.sealTCP(approvalDeniedToken) else {
            return s.channel.close("not allowed")
        }
        s.channel.sendThenClose(sealed, reason: "not allowed")
    }

    /// Saves what changed, confirms to the phone and makes the session the active one.
    private func admit(_ s: Session) {
        guard let match = s.matched, let phone = s.phone else { return }
        if let newKey = match.newKey {
            if let saveKey {
                do {
                    try saveKey(phone, PhoneKey(key: newKey, agreed: true, previous: match.key))
                } catch {
                    GPLog.log("server: could not save the key for \(phone.phoneName): \(error)")
                    if s.isNewPairing { pairingFailed(phone, .notSaved) }
                    s.phase = .awaitingHello
                    return s.channel.close("could not save the key")
                }
            }
            s.awaitingKeySaved = saveKey != nil
        } else if match.source == .stored, let saveKey, let now = keyLookup(phone.phoneID), now.previous != nil {
            // The phone connected with the agreed key, so it has it: the old one can go.
            try? saveKey(phone, PhoneKey(key: now.key, agreed: now.agreed))
        }
        s.phase = .authenticated
        s.channel.maxIncomingFrame = GlasspadService.maxFrameLength
        if s.isNewPairing {
            let handler = pairedHandler.get()
            delegateQueue.async { handler?(phone) }
        }
        sendRaw(handshakeConfirmToken, on: s)
        activate(s)
    }

    /// The phone saved the agreed key: forget the one it replaced (unless the phone was
    /// forgotten or paired again meanwhile).
    private func keySaved(on s: Session) {
        guard s.awaitingKeySaved, let phone = s.phone, let saveKey else { return }
        s.awaitingKeySaved = false
        guard let now = keyLookup(phone.phoneID), now.key == phone.pairKey, now.previous != nil else { return }
        try? saveKey(phone, PhoneKey(key: now.key, agreed: true))
    }

    private func pairingFailed(_ phone: PairedPhone, _ why: PairingFailure) {
        let handler = failedHandler.get()
        delegateQueue.async { handler?(phone, why) }
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
        restProbe.sessionStarted(at: lastHeard)
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
        if s.phase == .awaitingApproval, let phone = s.phone {
            s.phase = .awaitingHello
            pairingFailed(phone, .phoneLeft)
        }
        guard s === active else {
            if active == nil, running, case .connecting = stateBox.get(), handshaking.isEmpty { setState(restingState) }
            return
        }
        active = nil
        s.udp?.cancel()
        phoneBox.set(nil)
        pingTimer?.cancel()
        pingTimer = nil
        setState(restingState)
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
            if let rest = restProbe.touch(at: lastHeard, timestamp: frame.timestamp) { GPLog.log(rest.line) }
        case .heartbeat:
            let n = statsBox.mutate { st -> Int in st.heartbeatsReceived += 1; return st.heartbeatsReceived }
            if n == 1 || n % 500 == 0 { GPLog.log("server: \(n) heartbeats received") }
            if let rest = restProbe.heartbeat(at: lastHeard) { GPLog.log(rest.line) }
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
