import Foundation
import Network

/// How long the phone waits before trying its Mac again after a failed attempt. The first
/// tries come fast (a dropped link usually heals at once); after a few failures in a row the
/// Mac is asleep, off or behind a network that keeps devices apart, so the waits grow to
/// 5, 10 and then 30 seconds. Retrying every 2 s forever kept the Wi-Fi radio busy, and with a
/// Bonjour Sleep Proxy on the network each try could wake the sleeping Mac.
///
/// The long waits are spread by up to `jitter` either way, so phones (or one phone and a Mac
/// restarting) that failed together do not retry in lock step. The first four stay exact:
/// they are the ones that heal a dropped link, and they are over in under four seconds.
///
/// Long waits are not dead time: while one runs the client keeps a quiet Bonjour browse open
/// and tries at once when the Mac's service appears or changes (`GlasspadClient`), and a
/// network change or the app coming back to the front starts over from the first step.
public enum ReconnectBackoff {
    /// The waits in seconds, by failures in a row; the last one repeats.
    public static let steps: [TimeInterval] = [0.2, 0.5, 1, 2, 5, 10, 30]
    /// Each long wait is moved by up to this share of itself, earlier or later.
    public static let jitter = 0.2
    /// Waits at least this long watch Bonjour for the Mac coming back.
    public static let watchFrom: TimeInterval = 4

    /// The wait before attempt `attempt` (0 = the first retry). `random` is uniform in 0..<1.
    public static func delay(attempt: Int, random: Double) -> TimeInterval {
        let base = steps[min(max(attempt, 0), steps.count - 1)]
        guard base >= watchFrom else { return base }
        let spread = (min(max(random, 0), 1) * 2 - 1) * jitter
        return base * (1 + spread)
    }

    /// Once the last try opened a connection to the Mac (it answered, then closed: busy or
    /// restarting its listeners), the waits stay short; they grow only while the Mac cannot be
    /// reached at all.
    public static let reachedCap = 3

    public static func delay(attempt: Int, reachedMac: Bool = false, random: Double = Double.random(in: 0..<1)) -> TimeInterval {
        delay(attempt: reachedMac ? min(attempt, reachedCap) : attempt, random: random)
    }
}

/// When the phone may use peer-to-peer Wi-Fi (AWDL) to look for its Mac. It is the fallback
/// for networks that keep devices apart, and it is expensive: while it is on, the Wi-Fi chip
/// leaves the network's channel several times a second, which costs battery and adds latency
/// spikes to every packet. So it opens for `length` seconds after the shared network found
/// nothing in `GlasspadService.peerToPeerFallbackDelay` (or connections to a found Mac kept
/// failing), and then closes until something new happens: the network changes, the app
/// comes back to the front, or the person asks to try again. A Mac that AWDL can reach is
/// found within a few seconds, so a minute is plenty; past that the Mac is asleep or away.
public struct PeerToPeerWindow: Equatable, Sendable {
    public static let length: TimeInterval = 60

    /// Uptime when the window closes; nil while it has not opened.
    public private(set) var closesAt: TimeInterval?

    public init() {}

    /// Opens the window now, once. Later calls keep the first deadline, so a retry cannot
    /// stretch it.
    public mutating func open(now: TimeInterval) {
        if closesAt == nil { closesAt = now + Self.length }
    }

    /// Peer-to-peer may be used now.
    public func isOpen(now: TimeInterval) -> Bool {
        guard let closesAt else { return false }
        return now < closesAt
    }

    /// It opened and has closed again: browse the shared network only, and do not open it again.
    public func isSpent(now: TimeInterval) -> Bool {
        guard let closesAt else { return false }
        return now >= closesAt
    }

    /// Seconds until it closes (0 once closed, nil before it opened).
    public func remaining(now: TimeInterval) -> TimeInterval? {
        closesAt.map { max(0, $0 - now) }
    }
}

/// Where each paired Mac last answered, and on which network. The phone knocks on that address
/// again only on the same network (same router), so on another Wi-Fi its hello, which names
/// the phone and the Mac, never goes to whatever device has that address there. Kept in
/// memory only: it outlives one connection, as the app does while the phone is locked.
struct LastAddressBook: Sendable {
    private var entries: [UUID: (endpoint: NWEndpoint, network: String)] = [:]

    /// Remembers `endpoint` for `macID` on `network` (the path's routers). Nothing is kept
    /// without a known network.
    mutating func learn(_ endpoint: NWEndpoint, network: String, for macID: UUID) {
        guard !network.isEmpty else { return }
        entries[macID] = (endpoint, network)
    }

    /// The address to try on `network`, only if it was learned on that same network.
    func address(for macID: UUID, network: String) -> NWEndpoint? {
        guard !network.isEmpty, let e = entries[macID], e.network == network else { return nil }
        return e.endpoint
    }

    mutating func forget(_ macID: UUID) { entries[macID] = nil }

    /// The phone joined another network: addresses learned elsewhere are dropped.
    mutating func networkSwitched(to network: String) {
        entries = entries.filter { $0.value.network == network && !network.isEmpty }
    }

    func knows(_ macID: UUID) -> Bool { entries[macID] != nil }

    /// The network an address was learned on (tests).
    func network(of macID: UUID) -> String? { entries[macID]?.network }
}
