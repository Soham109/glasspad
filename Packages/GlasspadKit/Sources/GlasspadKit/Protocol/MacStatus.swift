import Foundation

/// Whether Glasspad may control Spotify and Music on the Mac (macOS Automation permission).
public enum AutomationState: String, Codable, Equatable, Sendable {
    /// Allowed for at least one of the players and refused for none.
    case granted
    /// Refused for at least one player. Media still works, without what is playing.
    case denied
    /// Not asked yet. macOS asks the first time Media talks to the player.
    case notDetermined
    /// Neither player is installed, so there is nothing to ask.
    case notNeeded
}

/// Mac -> phone: what the Mac can do right now. Sent as `ControlMessage.macStatus` right after
/// the handshake and again whenever any field changes, so the phone can warn when the pointer
/// cannot work (Accessibility off) instead of failing silently.
///
/// Every field but `accessibilityTrusted` is optional, and unknown fields and unknown
/// `automationMedia` values are ignored, so either side can add fields later.
public struct MacStatus: Codable, Equatable, Sendable {
    /// The Mac allows Glasspad under Privacy & Security > Accessibility. When false the Mac
    /// drops touches, so the pointer does not move and clicks do nothing.
    public var accessibilityTrusted: Bool
    /// Spotify and Music control (optional; only what is playing depends on it).
    public var automationMedia: AutomationState?
    /// The Mac's name as shown in its menu bar app.
    public var macName: String?
    /// The Mac reads `modesShown` and pushes Dock changes and the front app to every pane of a
    /// layout, so the phone need not ask again on a timer. nil from a Mac built before that.
    public var followsAllPanes: Bool?

    public init(accessibilityTrusted: Bool, automationMedia: AutomationState? = nil, macName: String? = nil,
                followsAllPanes: Bool? = nil) {
        self.accessibilityTrusted = accessibilityTrusted
        self.automationMedia = automationMedia
        self.macName = macName
        self.followsAllPanes = followsAllPanes
    }

    private enum Keys: String, CodingKey { case accessibilityTrusted, automationMedia, macName, followsAllPanes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        accessibilityTrusted = try c.decode(Bool.self, forKey: .accessibilityTrusted)
        // An automation value from a newer Mac reads as "unknown" rather than failing the message.
        automationMedia = (try? c.decodeIfPresent(String.self, forKey: .automationMedia))
            .flatMap { $0.flatMap(AutomationState.init(rawValue:)) }
        macName = try? c.decodeIfPresent(String.self, forKey: .macName)
        followsAllPanes = try? c.decodeIfPresent(Bool.self, forKey: .followsAllPanes)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(accessibilityTrusted, forKey: .accessibilityTrusted)
        try c.encodeIfPresent(automationMedia, forKey: .automationMedia)
        try c.encodeIfPresent(macName, forKey: .macName)
        try c.encodeIfPresent(followsAllPanes, forKey: .followsAllPanes)
    }
}
