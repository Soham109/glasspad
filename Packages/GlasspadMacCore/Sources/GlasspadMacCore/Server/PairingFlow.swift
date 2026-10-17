import Foundation

/// Where pairing is, as the Mac shows it: the code on screen, the phone that just paired, a
/// code that ran out, or a failure. Wording lives in the app; this is only the state.
public enum PairingPhase: Equatable, Sendable {
    case idle
    /// The QR code is up and the pending key is armed until `expiresAt`.
    case waiting(url: URL, expiresAt: Date)
    /// A phone proved it scanned the code; the Mac is asking whether to allow it.
    case approving(phoneName: String)
    /// A phone proved it scanned the code and was saved.
    case paired(phoneName: String)
    /// The person chose Don't Allow (or did not answer) for this phone.
    case declined(phoneName: String)
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

    public var isDeclined: Bool { if case .declined = self { true } else { false } }
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

    /// A phone holds the code: the code is used up while the Mac asks about it.
    public mutating func approving(phoneName: String) { phase = .approving(phoneName: phoneName) }

    public mutating func declined(phoneName: String) { phase = .declined(phoneName: phoneName) }

    /// A phone's name as the Mac shows it in a question: the phone chose it, so it is cut to one
    /// short line with no control characters (no extra lines that read like the Mac's own words).
    public static func displayName(_ raw: String) -> String {
        let flat = raw.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) ? " " : String($0) }.joined()
        let trimmed = flat.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        let name = trimmed.isEmpty ? "An iPhone" : trimmed
        return name.count > 40 ? String(name.prefix(39)) + "…" : name
    }

    public mutating func failed(_ message: String) { phase = .failed(message: message) }

    /// Cancel, or dismiss a result.
    public mutating func reset() { phase = .idle }
}
