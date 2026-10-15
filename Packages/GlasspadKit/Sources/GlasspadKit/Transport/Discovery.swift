import Foundation
import Network

/// A Mac advertising Glasspad on the local network.
public struct DiscoveredMac: Equatable, Hashable, Sendable {
    public var macID: UUID
    /// The Bonjour service name (the Mac's name).
    public var name: String
    /// TXT `v`, nil if missing.
    public var protocolVersion: Int?

    public init(macID: UUID, name: String, protocolVersion: Int?) {
        self.macID = macID
        self.name = name
        self.protocolVersion = protocolVersion
    }
}

/// Browses `_glasspad._tcp` and lists every Mac in reach, so the phone can show which paired
/// Macs are on this network right now. Connecting stays `GlasspadClient`'s job.
///
/// Thread safety: every public member may be called from any thread. Callbacks arrive on the
/// `delegateQueue` given at init.
public final class GlasspadDiscovery: @unchecked Sendable {
    /// Called with the full list whenever it changes.
    public var onChange: (@Sendable ([DiscoveredMac]) -> Void)? {
        get { changeHandler.get() }
        set { changeHandler.set(newValue) }
    }
    /// Called when browsing fails (for example Local Network access was denied on iPhone).
    public var onFailure: (@Sendable (String) -> Void)? {
        get { failureHandler.get() }
        set { failureHandler.set(newValue) }
    }
    public var macs: [DiscoveredMac] { macsBox.get() }

    private let queue = DispatchQueue(label: "glasspad.discovery")
    private let delegateQueue: DispatchQueue
    private let changeHandler = Locked<(@Sendable ([DiscoveredMac]) -> Void)?>(nil)
    private let failureHandler = Locked<(@Sendable (String) -> Void)?>(nil)
    private let macsBox = Locked<[DiscoveredMac]>([])
    private var browser: NWBrowser?

    public init(delegateQueue: DispatchQueue = .main) {
        self.delegateQueue = delegateQueue
    }

    deinit { browser?.cancel() }

    public func start() {
        queue.async { [self] in
            guard browser == nil else { return }
            let params = NWParameters()
            // Shared network only: browsing with peer-to-peer on wakes AWDL, which costs every
            // Wi-Fi packet periodic latency spikes (see GlasspadService.tcpParameters).
            params.includePeerToPeer = false
            let b = NWBrowser(for: .bonjourWithTXTRecord(type: GlasspadService.bonjourType, domain: nil), using: params)
            b.browseResultsChangedHandler = { [weak self] results, _ in self?.update(results) }
            b.stateUpdateHandler = { [weak self] st in
                guard let self else { return }
                switch st {
                case .failed(let e), .waiting(let e):
                    let handler = self.failureHandler.get()
                    self.delegateQueue.async { handler?("\(e)") }
                default:
                    break
                }
            }
            browser = b
            b.start(queue: queue)
        }
    }

    public func stop() {
        queue.async { [self] in
            browser?.cancel()
            browser = nil
            macsBox.set([])
        }
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        var seen: [UUID: DiscoveredMac] = [:]
        for r in results {
            guard case .bonjour(let txt) = r.metadata, let idText = txt["id"], let id = UUID(uuidString: idText) else { continue }
            var name = idText
            if case .service(let n, _, _, _) = r.endpoint { name = n }
            seen[id] = DiscoveredMac(macID: id, name: name, protocolVersion: txt["v"].flatMap { Int($0) })
        }
        let list = seen.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let changed = macsBox.mutate { cur -> Bool in
            guard cur != list else { return false }
            cur = list
            return true
        }
        guard changed else { return }
        let handler = changeHandler.get()
        delegateQueue.async { handler?(list) }
    }
}

/// The phone's link to whichever of its paired Macs it is using: connects to a chosen Mac,
/// auto-connects to the last used one, remembers when each Mac connected and how to wake it.
///
/// It owns one `GlasspadClient` at a time and forwards its callbacks to `delegate`, dropping
/// any that arrive late from a client it already replaced.
public final class MacConnector: @unchecked Sendable {
    public let store: KnownMacsStore
    public let phoneID: String
    public let phoneName: String

    public weak var delegate: (any GlasspadLinkDelegate)? {
        get { delegateBox.get().value }
        set { delegateBox.set(WeakDelegate(value: newValue)) }
    }
    /// Optional fixed address per Mac (a manual address, or tests). nil or a nil result uses Bonjour.
    public var manualAddress: (@Sendable (UUID) -> (host: String, port: UInt16)?)? {
        get { addressBox.get() }
        set { addressBox.set(newValue) }
    }
    /// The client for the Mac in use, if any.
    public var client: GlasspadClient? { lock.withLock { current?.client } }
    /// The Mac in use.
    public var activeMacID: UUID? { lock.withLock { current?.macID } }
    public var state: LinkState { client?.state ?? .idle }

    private let delegateQueue: DispatchQueue
    private let delegateBox = Locked(WeakDelegate())
    private let addressBox = Locked<(@Sendable (UUID) -> (host: String, port: UInt16)?)?>(nil)
    private let lock = NSLock()
    private var current: (macID: UUID, client: GlasspadClient, proxy: Proxy)?

    public init(store: KnownMacsStore, phoneID: String, phoneName: String, delegateQueue: DispatchQueue = .main) {
        self.store = store
        self.phoneID = phoneID
        self.phoneName = phoneName
        self.delegateQueue = delegateQueue
    }

    /// Connects to the last used Mac. Returns false when nothing is paired.
    @discardableResult
    public func connectToLastUsed() -> Bool {
        guard let mac = store.current.lastUsed else { return false }
        connect(to: mac.id)
        return true
    }

    /// Makes this Mac the one in use and connects to it (dropping any other Mac's session).
    public func connect(to macID: UUID) {
        guard let mac = store.current[macID] else { return }
        store.update { $0.select(macID) }
        let client = GlasspadClient(phoneID: phoneID, phoneName: phoneName, pairing: mac.pairing, delegateQueue: delegateQueue)
        let proxy = Proxy(owner: self, macID: macID)
        client.delegate = proxy
        client.onWakeTarget = { [weak self] target in
            self?.store.update { $0.setWakeTarget(target, for: macID) }
        }
        let old = lock.withLock { () -> GlasspadClient? in
            let previous = current?.client
            current = (macID, client, proxy)
            return previous
        }
        old?.delegate = nil
        old?.disconnect()
        if let address = manualAddress?(macID) {
            client.connect(host: address.host, port: address.port)
        } else {
            client.connect()
        }
    }

    /// Says bye to the Mac in use and stops.
    public func disconnect() {
        let old = lock.withLock { () -> GlasspadClient? in
            defer { current = nil }
            return current?.client
        }
        old?.delegate = nil
        old?.disconnect()
    }

    /// Skips any backoff wait (call when the app returns to the foreground).
    public func reconnectNow() { client?.reconnectNow() }

    /// Sends a Wake-on-LAN magic packet to a paired Mac (default: the one in use, else the last
    /// used). Throws `noWakeTarget` when that Mac has never sent its wake details.
    @discardableResult
    public func wake(_ macID: UUID? = nil) throws -> [String] {
        let macs = store.current
        guard let id = macID ?? activeMacID ?? macs.lastUsed?.id, let mac = macs[id] else {
            throw MacConnectorError.notPaired
        }
        guard let target = mac.wakeTarget else { throw MacConnectorError.noWakeTarget }
        return try WakeOnLAN.send(to: target)
    }

    fileprivate func isCurrent(_ proxy: Proxy) -> Bool { lock.withLock { current?.proxy === proxy } }

    fileprivate final class Proxy: GlasspadLinkDelegate {
        weak var owner: MacConnector?
        let macID: UUID
        init(owner: MacConnector, macID: UUID) {
            self.owner = owner
            self.macID = macID
        }

        func link(didChangeState state: LinkState) {
            guard let owner, owner.isCurrent(self) else { return }
            if case .connected = state { owner.store.update { $0.markConnected(macID) } }
            owner.delegate?.link(didChangeState: state)
        }

        func link(didReceive message: ControlMessage) {
            guard let owner, owner.isCurrent(self) else { return }
            owner.delegate?.link(didReceive: message)
        }
    }
}

public enum MacConnectorError: Error, Equatable, Sendable {
    case notPaired
    case noWakeTarget
}
