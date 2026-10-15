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

    static func tcpParameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let p = NWParameters(tls: nil, tcp: tcp)
        p.includePeerToPeer = true
        p.serviceClass = .responsiveData
        return p
    }

    static func udpParameters() -> NWParameters {
        let p = NWParameters.udp
        p.includePeerToPeer = true
        p.serviceClass = .interactiveVoice
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
        buffer.append(data)
        var frames: [Data] = []
        while buffer.count >= 4 {
            let b = buffer.startIndex
            let len = Int(buffer[b]) << 24 | Int(buffer[b + 1]) << 16 | Int(buffer[b + 2]) << 8 | Int(buffer[b + 3])
            guard len <= GlasspadService.maxFrameLength else { throw FrameError.tooLarge }
            guard buffer.count >= 4 + len else { break }
            frames.append(Data(buffer[(b + 4)..<(b + 4 + len)]))
            buffer = Data(buffer[(b + 4 + len)...])
        }
        return frames
    }
}

/// A framed TCP connection. Every callback runs on `queue`.
final class ControlChannel: @unchecked Sendable {
    let connection: NWConnection
    private let queue: DispatchQueue
    var onReady: (() -> Void)?
    var onFrame: ((Data) -> Void)?
    var onClosed: ((String?) -> Void)?
    private var acc = FrameAccumulator()
    private(set) var closed = false

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
                do {
                    for f in try self.acc.append(data) {
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
        connection.send(content: FrameAccumulator.wrap(payload), completion: .contentProcessed { [weak self] e in
            if let e { self?.close("send failed: \(e)") }
        })
    }

    /// Sends a last frame, then closes once it is handed to the network (cancel alone can drop it).
    func sendThenClose(_ payload: Data, reason: String) {
        guard !closed else { return }
        onFrame = nil
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
