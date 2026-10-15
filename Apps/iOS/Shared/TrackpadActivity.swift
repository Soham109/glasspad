import ActivityKit
import Foundation

/// The Live Activity shown while the trackpad is in use. Shared by the app (which starts,
/// updates and ends it) and the widget extension (which draws it).
struct TrackpadActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        enum Status: String, Codable, Hashable, Sendable {
            case connected, connecting, paused, offline
        }

        var status: Status
        var macName: String

        var title: String {
            switch status {
            case .connected: "Connected"
            case .connecting: "Connecting"
            case .paused: "Paused"
            case .offline: "Not connected"
            }
        }

        var detail: String {
            switch status {
            case .connected: "Controlling \(macName)"
            case .connecting: "Looking for \(macName)"
            case .paused: "Open Glasspad to keep controlling \(macName)"
            case .offline: "Cannot reach \(macName)"
            }
        }
    }
}

/// Deep links the app understands. Widgets and the Live Activity use `trackpad`.
enum GlasspadLink {
    static let trackpad = URL(string: "glasspad://trackpad")!
}
