import Foundation

/// Repeat setting of the Mac's player.
public enum MediaRepeatMode: String, Codable, Sendable, CaseIterable {
    case off, one, all

    /// Unknown values (from a newer Mac) read as `.off` instead of failing the whole state.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MediaRepeatMode(rawValue: raw) ?? .off
    }

    /// The next setting when the repeat button is tapped: off, all, one, off.
    public var next: MediaRepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

/// One sound output on the Mac (CoreAudio device).
public struct MediaOutput: Codable, Equatable, Sendable, Hashable, Identifiable {
    /// The device UID, stable across reboots.
    public var id: String
    public var name: String
    /// What kind of output, for the icon: builtIn, headphones, bluetooth, airPlay, usb, hdmi,
    /// displayPort, thunderbolt, virtual, aggregate or other. A string so new kinds never break
    /// decoding.
    public var kind: String
    /// The current default output.
    public var isCurrent: Bool

    public init(id: String, name: String, kind: String, isCurrent: Bool) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isCurrent = isCurrent
    }
}

/// Why Media mode shows less than it could. `kind` is a string so new kinds never break decoding.
public struct MediaNotice: Codable, Equatable, Sendable, Hashable {
    /// automationDenied: macOS Automation permission was refused for `app`.
    /// unavailable: the Mac cannot read now playing at all.
    public var kind: String
    /// One sentence to show the user.
    public var message: String
    /// App the notice is about (e.g. "Spotify").
    public var app: String?

    public static let automationDenied = "automationDenied"
    public static let unavailable = "unavailable"

    public init(kind: String, message: String, app: String? = nil) {
        self.kind = kind
        self.message = message
        self.app = app
    }
}

/// Phone -> Mac media controls beyond the plain transport commands.
public enum MediaControl: Codable, Equatable, Sendable {
    /// Jump to this position, in seconds.
    case seek(TimeInterval)
    case setShuffle(Bool)
    case setRepeat(MediaRepeatMode)
    /// Make the output with this `MediaOutput.id` the default.
    case selectOutput(id: String)
}
