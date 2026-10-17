import Foundation

/// What the phone's screen after the scan should say. It never says Paired before the Mac has
/// let this phone in at least once: until then the Mac may still be asking, or may say no.
public enum PairingStage: Equatable, Sendable {
    /// Not connected yet, and the Mac has not answered.
    case reaching
    /// The Mac is asking the person there whether to allow this phone.
    case awaitingApproval
    /// The pairing ended with this failure reason (for example, not allowed on the Mac).
    case failed(String)
    /// Connected now.
    case connected
    /// Paired (it has connected before), now connecting again.
    case reconnecting

    public init(state: LinkState, issue: LinkIssue?, hasConnected: Bool) {
        if case .connected = state {
            self = .connected
        } else if case .failed(let reason) = state {
            self = .failed(reason)
        } else if issue == .awaitingApproval {
            self = .awaitingApproval
        } else {
            self = hasConnected ? .reconnecting : .reaching
        }
    }
}
