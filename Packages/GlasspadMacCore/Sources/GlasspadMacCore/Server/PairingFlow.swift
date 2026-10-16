import Foundation

/// Where pairing is, as the Mac shows it: the code on screen, the phone that just paired, a
/// code that ran out, or a failure. Wording lives in the app; this is only the state.
public enum PairingPhase: Equatable, Sendable {
    case idle
    /// The QR code is up and the pending key is armed until `expiresAt`.
    case waiting(url: URL, expiresAt: Date)
    /// A phone proved it scanned the code and was saved.
    case paired(phoneName: String)
    /// The code was up for `PairingFlow.codeLifetime` without a scan; the key is disarmed.
    case expired
    /// Pairing could not finish (for example the Keychain refused the new phone).
    case failed(message: String)

    /// The link in the QR code, only while it can still be scanned.
    public var url: URL? {
        if case .waiting(let url, _) = self { return url }
        return nil
    }

    /// Something to show: the code, or the result of the last attempt.
    public var isActive: Bool { self != .idle }
}

/// The pairing state machine, kept free of the transport and the clock so it can be tested.
/// `GlasspadController` drives it and arms or disarms the server's pending key to match.
public struct PairingFlow: Equatable, Sendable {
    /// How long one code stays valid. Long enough to find the phone and open the app, short
    /// enough that a code left on screen (or a copied link) does not stay usable for hours.
    public static let codeLifetime: TimeInterval = 5 * 60

    public private(set) var phase: PairingPhase = .idle

    public init() {}

    public mutating func begin(url: URL, now: Date) {
        phase = .waiting(url: url, expiresAt: now.addingTimeInterval(Self.codeLifetime))
    }

    /// Returns true exactly once, when a waiting code runs out (the caller disarms the key).
    public mutating func tick(now: Date) -> Bool {
        guard case .waiting(_, let expiresAt) = phase, now >= expiresAt else { return false }
        phase = .expired
        return true
    }

    /// Seconds left on the code, or nil when no code is up.
    public func remaining(now: Date) -> TimeInterval? {
        guard case .waiting(_, let expiresAt) = phase else { return nil }
        return max(0, expiresAt.timeIntervalSince(now))
    }

    public mutating func completed(phoneName: String) { phase = .paired(phoneName: phoneName) }

    public mutating func failed(_ message: String) { phase = .failed(message: message) }

    /// Cancel, or dismiss a result.
    public mutating func reset() { phase = .idle }
}
