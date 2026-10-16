import Foundation
import GlasspadKit

/// Decides when the Mac sends `ControlMessage.macStatus`: always on a new session, then only
/// when a field changed. Pure, so the rule is tested without a server.
public struct MacStatusReporter: Equatable, Sendable {
    public private(set) var lastSent: MacStatus?

    public init() {}

    /// The status to send now, or nil when the phone already has it.
    public mutating func update(_ status: MacStatus, newSession: Bool = false) -> MacStatus? {
        guard newSession || status != lastSent else { return nil }
        lastSent = status
        return status
    }

    /// The session ended: the next phone must get a fresh copy.
    public mutating func sessionEnded() { lastSent = nil }
}

/// Watches the Accessibility permission both ways. The user can turn it off in System Settings
/// while Glasspad runs; then the Mac drops touches, so the phone must be told at once.
public struct AccessibilityMonitor: Sendable {
    private let check: @Sendable () -> Bool
    public private(set) var trusted: Bool

    /// `check` is `AXIsProcessTrusted` in the app; tests pass their own.
    public init(check: @escaping @Sendable () -> Bool) {
        self.check = check
        trusted = check()
    }

    /// Re-reads the permission. Returns the new value when it changed, nil otherwise.
    public mutating func poll() -> Bool? {
        let now = check()
        guard now != trusted else { return nil }
        trusted = now
        return now
    }

    /// Records a value read elsewhere (the system prompt's answer).
    public mutating func set(_ value: Bool) { trusted = value }
}
