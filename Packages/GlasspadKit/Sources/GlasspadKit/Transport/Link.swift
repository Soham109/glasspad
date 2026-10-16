import Foundation
import Network

/// Connection state shown in both apps.
public enum LinkState: Equatable, Sendable {
    case idle
    /// Client: browsing Bonjour. Server: listening, no phone connected.
    case searching
    /// TCP open, handshake in progress.
    case connecting
    /// Handshake done. `rttMs` is the median RTT (server side; nil on the phone).
    case connected(rttMs: Double?)
    case failed(String)
}

/// Callbacks from `GlasspadServer` and `GlasspadClient`, delivered on the `delegateQueue`
/// given at init (main by default). `ping`/`pong` are handled by the transport and not delivered.
public protocol GlasspadLinkDelegate: AnyObject {
    func link(didChangeState state: LinkState)
    func link(didReceive message: ControlMessage)
    /// Server side only: a decoded touch frame from the paired phone.
    func link(didReceive frame: TouchFrame)
}

public extension GlasspadLinkDelegate {
    func link(didReceive frame: TouchFrame) {}
}

/// Counters for the Mac debug view.
public struct LinkStats: Equatable, Sendable {
    public var rttMedianMs: Double?
    public var rttP95Ms: Double?
    public var rttSamples: Int = 0
    public var framesReceived: Int = 0
    public var heartbeatsReceived: Int = 0
    /// Packets that failed authentication (wrong key or tampered). Dropped silently.
    public var authFailures: Int = 0
    /// Packets rejected by the replay check.
    public var replayDrops: Int = 0
    /// Packets that authenticated but did not decode.
    public var malformed: Int = 0
    public init() {}
}

/// A phone the Mac knows (or just learned through a pending pairing).
public struct PairedPhone: Equatable, Sendable {
    public var phoneID: String
    public var phoneName: String
    public var pairKey: Data
    public init(phoneID: String, phoneName: String, pairKey: Data) {
        self.phoneID = phoneID
        self.phoneName = phoneName
        self.pairKey = pairKey
    }
}

public enum GlasspadService {
    public static let bonjourType = "_glasspad._tcp"
    public static let protocolVersion = 1
    /// Reconnect delays in seconds; the last one repeats.
    public static let backoff: [TimeInterval] = [0.2, 0.5, 1, 2]
    /// Keep-awake heartbeat interval.
    public static let heartbeatInterval: TimeInterval = 0.02
    /// Heartbeats stop after this long without touches.
    public static let heartbeatIdleTimeout: TimeInterval = 120
    /// Server pings this often.
    public static let pingInterval: TimeInterval = 1
    /// Handshake must finish within this.
    public static let handshakeTimeout: TimeInterval = 5
    /// Largest TCP frame accepted (Dock icons and clipboard images fit).
    public static let maxFrameLength = 16 << 20
    /// Largest TCP frame the Mac accepts before the handshake is done (a hello or a key
    /// confirmation is well under 1 KB; a long phone name still fits).
    public static let maxHandshakeFrameLength = 8 << 10
    /// `bye` reason the Mac sends to a session that another connection replaced. A client that
    /// receives it stops reconnecting (otherwise two phones would take turns forever) and
    /// reports `failed(replacedFailure)`.
    public static let replacedReason = "replaced by another connection"
    public static let replacedFailure = "Another iPhone is now using this Mac"
    /// The phone treats the link as dead after this long without any frame from the Mac (the Mac
    /// pings every second), and reconnects at once.
    public static let clientSilenceTimeout: TimeInterval = 3.5
    /// The Mac closes a session after this long without hearing from the phone.
    public static let serverSilenceTimeout: TimeInterval = 6

    /// How long the phone browses on the shared Wi-Fi network before it also looks over
    /// peer-to-peer Wi-Fi (AWDL).
    public static let peerToPeerFallbackDelay: TimeInterval = 3

    /// TCP control parameters. `peerToPeer` allows AWDL (Apple's peer-to-peer Wi-Fi). The phone
    /// leaves it off unless no shared network works: while AWDL is in use the Wi-Fi chip hops
    /// to AWDL's channels several times a second, which shows up as periodic latency spikes on
    /// every packet, including ones sent over the normal network. The Mac's listeners keep it
    /// on so that the fallback can still reach them.
    static func tcpParameters(peerToPeer: Bool = false) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let p = NWParameters(tls: nil, tcp: tcp)
        p.includePeerToPeer = peerToPeer
        p.serviceClass = .responsiveData
        p.prohibitedInterfaceTypes = [.cellular]
        // Lets the Mac rebind its port right after a restart.
        p.allowLocalEndpointReuse = true
        return p
    }

    /// UDP touch parameters: the WMM voice queue (lowest air-time wait) and the same
    /// peer-to-peer rule as `tcpParameters`.
    static func udpParameters(peerToPeer: Bool = false) -> NWParameters {
        let p = NWParameters.udp
        p.includePeerToPeer = peerToPeer
        p.serviceClass = .interactiveVoice
        p.prohibitedInterfaceTypes = [.cellular]
        return p
    }
}

// MARK: - Internals shared by server and client

final class Locked<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    init(_ v: T) { value = v }
    func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ v: T) { lock.lock(); value = v; lock.unlock() }
    @discardableResult
    func mutate<R>(_ f: (inout T) -> R) -> R { lock.lock(); defer { lock.unlock() }; return f(&value) }
}

struct WeakDelegate {
    weak var value: (any GlasspadLinkDelegate)?
}

/// `UInt32 BE length || payload` framing for the TCP stream.
struct FrameAccumulator {
    private var buffer = Data()

    static func wrap(_ payload: Data) -> Data {
        var out = Data(capacity: 4 + payload.count)
        withUnsafeBytes(of: UInt32(payload.count).bigEndian) { out.append(contentsOf: $0) }
        out.append(payload)
        return out
    }

    enum FrameError: Error { case tooLarge }

    mutating func append(_ data: Data) throws -> [Data] {
        push(data)
        var frames: [Data] = []
        while let f = try next(limit: GlasspadService.maxFrameLength) { frames.append(f) }
        return frames
    }

    /// Buffers bytes read from the stream; take frames out with `next`.
    mutating func push(_ data: Data) { buffer.append(data) }

    /// The next whole frame, nil until one has arrived. Throws when the next frame announces more
    /// than `limit` bytes (checked on the header, so an oversized frame is never buffered).
    mutating func next(limit: Int) throws -> Data? {
        guard buffer.count >= 4 else { return nil }
        let b = buffer.startIndex
        let len = Int(buffer[b]) << 24 | Int(buffer[b + 1]) << 16 | Int(buffer[b + 2]) << 8 | Int(buffer[b + 3])
        guard len <= limit else { throw FrameError.tooLarge }
        guard buffer.count >= 4 + len else { return nil }
        let frame = Data(buffer[(b + 4)..<(b + 4 + len)])
        buffer = Data(buffer[(b + 4 + len)...])
        return frame
    }
}

/// A framed TCP connection. Every callback runs on `queue`.
final class ControlChannel: @unchecked Sendable {
    let connection: NWConnection
    private let queue: DispatchQueue
    var onReady: (() -> Void)?
    var onFrame: ((Data) -> Void)?
    /// Any bytes arrived from the peer, including part of a frame that is not complete yet.
    /// Liveness checks use it: a large message (a clipboard image) can take longer than the
    /// silence timeout to arrive on slow Wi-Fi, and the pings queued behind it arrive only
    /// after it, so counting whole frames alone dropped a link that was busy, not dead.
    var onBytes: (() -> Void)?
    var onClosed: ((String?) -> Void)?
    private var acc = FrameAccumulator()
    private(set) var closed = false
    /// Largest frame accepted from the peer; checked frame by frame, so a change made while one
    /// frame is handled applies to the next. The Mac keeps it small until the phone has proved
    /// it holds the pair key.
    var maxIncomingFrame = GlasspadService.maxFrameLength

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            switch st {
            case .ready:
                self.onReady?()
                self.receive()
            case .failed(let e):
                self.close("failed: \(e)")
            case .waiting(let e):
                self.close("unreachable: \(e)")
            case .cancelled:
                self.close(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self, !self.closed else { return }
            if let data, !data.isEmpty {
                self.onBytes?()
                do {
                    self.acc.push(data)
                    while let f = try self.acc.next(limit: self.maxIncomingFrame) {
                        self.onFrame?(f)
                        if self.closed { return }
                    }
                } catch {
                    self.close("oversized frame")
                    return
                }
            }
            if isComplete || error != nil {
                self.close(error.map { "\($0)" } ?? "closed by peer")
                return
            }
            self.receive()
        }
    }

    func send(_ payload: Data) {
        guard !closed else { return }
        // The peer closes the connection on a frame over the limit; dropping this one message
        // keeps the session (and anything held, like a drag) alive.
        guard payload.count <= GlasspadService.maxFrameLength else {
            GPLog.log("tcp: dropped a \(payload.count) byte message, over the \(GlasspadService.maxFrameLength) byte limit")
            return
        }
        connection.send(content: FrameAccumulator.wrap(payload), completion: .contentProcessed { [weak self] e in
            if let e { self?.close("send failed: \(e)") }
        })
    }

    /// Sends a last frame, then closes once it is handed to the network (cancel alone can drop it).
    func sendThenClose(_ payload: Data, reason: String) {
        guard !closed else { return }
        onFrame = nil
        onBytes = nil
        // Strong captures on purpose: the owner may already have dropped this channel.
        connection.send(content: FrameAccumulator.wrap(payload), completion: .contentProcessed { _ in
            self.close(reason)
        })
        queue.asyncAfter(deadline: .now() + 1) { self.close(reason) }
    }

    func close(_ reason: String?) {
        guard !closed else { return }
        closed = true
        connection.cancel()
        let cb = onClosed
        onClosed = nil
        onFrame = nil
        onBytes = nil
        onReady = nil
        cb?(reason)
    }
}

func uptime() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

func percentile(_ sorted: [Double], _ p: Double) -> Double? {
    guard !sorted.isEmpty else { return nil }
    let i = Int((p * Double(sorted.count)).rounded(.up)) - 1
    return sorted[min(max(i, 0), sorted.count - 1)]
}
