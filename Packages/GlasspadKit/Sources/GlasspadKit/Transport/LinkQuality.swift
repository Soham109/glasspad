import Foundation
import Network

/// Round trips the phone measured itself: it sends `ping` on the control channel about once a
/// second and the Mac answers `pong` (every Mac build does). Kept per session.
public struct RoundTripStats: Equatable, Sendable {
    /// The newest samples, oldest first, in milliseconds.
    public var samplesMs: [Double]

    /// How many samples are kept.
    public static let window = 20

    public init(samplesMs: [Double] = []) {
        self.samplesMs = Array(samplesMs.suffix(Self.window))
    }

    public var count: Int { samplesMs.count }
    public var medianMs: Double? { percentile(samplesMs.sorted(), 0.5) }
    public var p95Ms: Double? { percentile(samplesMs.sorted(), 0.95) }

    mutating func add(_ ms: Double) {
        samplesMs.append(ms)
        if samplesMs.count > Self.window { samplesMs.removeFirst(samplesMs.count - Self.window) }
    }
}

/// Round-trip time in plain words, for the phone's Connection screen and the Mac's menu.
/// The median says how the pointer feels most of the time, p95 how often it hitches.
public enum LinkQuality: String, Equatable, Sendable, CaseIterable {
    case excellent, good, fair, poor

    /// Fewer than this many samples says nothing yet.
    public static let minimumSamples = 3

    /// nil until there are enough samples.
    public init?(_ stats: RoundTripStats) {
        guard stats.count >= Self.minimumSamples, let median = stats.medianMs, let p95 = stats.p95Ms else { return nil }
        self.init(medianMs: median, p95Ms: p95)
    }

    public init(medianMs median: Double, p95Ms p95: Double) {
        if median < 20 && p95 < 50 {
            self = .excellent
        } else if median < 40 && p95 < 100 {
            self = .good
        } else if median < 80 {
            self = .fair
        } else {
            self = .poor
        }
    }

    public var title: String {
        switch self {
        case .excellent: "Excellent"
        case .good: "Good"
        case .fair: "Fair"
        case .poor: "Poor"
        }
    }

    /// What the user feels.
    public var detail: String {
        switch self {
        case .excellent: "The pointer keeps up with your finger."
        case .good: "Fine for pointing and typing."
        case .fair: "You may feel the pointer lag now and then."
        case .poor: "Expect lag. A busy or distant Wi-Fi network is the usual cause."
        }
    }
}

/// Which way the session reaches the Mac.
public enum LinkPath: String, Equatable, Sendable {
    /// The shared Wi-Fi network (the normal case).
    case wifi
    /// Apple's peer-to-peer Wi-Fi (AWDL), used only when the Mac is not found on a shared network.
    case peerToPeer
    /// A cable (USB or Ethernet).
    case wired
    /// The same machine (tests, the simulator talking to its own Mac).
    case loopback
    case other

    public var title: String {
        switch self {
        case .wifi: "Wi-Fi"
        case .peerToPeer: "Peer-to-peer Wi-Fi"
        case .wired: "Cable"
        case .loopback: "This computer"
        case .other: "Other network"
        }
    }

    /// Classifies a connection by the interface it uses. `peerToPeer` is whether AWDL was
    /// allowed for it; `endpoint` is the remote endpoint's description (AWDL endpoints carry
    /// `%awdl0`).
    static func classify(interface: NWInterface?, peerToPeer: Bool, endpoint: String) -> LinkPath {
        if peerToPeer, endpoint.contains("%awdl") || (interface?.name.hasPrefix("awdl") ?? false) {
            return .peerToPeer
        }
        guard let interface else { return .other }
        if interface.name.hasPrefix("awdl") || interface.name.hasPrefix("llw") { return .peerToPeer }
        switch interface.type {
        case .wifi: return .wifi
        case .wiredEthernet: return .wired
        case .loopback: return .loopback
        default: return .other
        }
    }
}
