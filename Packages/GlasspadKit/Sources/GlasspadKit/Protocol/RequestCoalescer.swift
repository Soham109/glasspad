import Foundation

/// Drops a request the phone already sent a moment ago. Two panes of a layout that both show
/// now playing (Media and Remote) each ask for it when they appear, and every ask makes the
/// Mac send the whole state again, artwork included; one answer serves both. Only requests
/// that ask for state count. Commands always go out.
///
/// A new session, or a change of what is on screen (`modeSelected`, `modesShown`), starts
/// afresh, so a request that follows them is never mistaken for a repeat.
public struct RequestCoalescer: Equatable, Sendable {
    /// Requests closer together than this are one request.
    public static let window: TimeInterval = 0.5

    private var sent: [String: TimeInterval] = [:]

    public init() {}

    /// Whether to send `message` now, at uptime `now`; records it when so.
    public mutating func shouldSend(_ message: ModeMessage, now: TimeInterval) -> Bool {
        switch message {
        case .modeSelected, .modesShown:
            sent = [:]
            return true
        default:
            break
        }
        guard let key = Self.key(message) else { return true }
        if let last = sent[key], now - last < Self.window { return false }
        sent[key] = now
        return true
    }

    /// The connection changed: nothing sent before counts.
    public mutating func reset() { sent = [:] }

    /// Requests that only ask for state, by what they ask for.
    static func key(_ message: ModeMessage) -> String? {
        switch message {
        case .mediaRequest, .deckRequest, .dockRequest, .dockSync, .dockCatalogRequest, .deckCatalogRequest:
            return message.tag
        case .macro(.listMacros):
            return "listMacros"
        default:
            return nil
        }
    }
}
