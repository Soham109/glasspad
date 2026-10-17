import Foundation

/// A battery experiment: when the trackpad's keep-awake heartbeats stop after the last touch.
/// They hold the phone's Wi-Fi radio awake 50 times a second, so a touch after a pause arrives
/// on time; stopping them sooner saves battery, and the Mac's log
/// (`RestWakeProbe`) shows what that costs the first touch after a rest. Only the timing
/// changes, never the heartbeats themselves. The default is the shipped behaviour.
public enum HeartbeatRest: String, CaseIterable, Identifiable, Sendable {
    /// Two minutes after the last touch (`GlasspadService.heartbeatIdleTimeout`), as shipped.
    case twoMinutes = "120"
    /// Thirty seconds after the last touch.
    case thirtySeconds = "30"
    /// As soon as the trackpad dims, and two minutes after the last touch at the latest.
    case whenDimmed = "dim"

    public static let standard = HeartbeatRest.twoMinutes

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .twoMinutes: "2 Minutes"
        case .thirtySeconds: "30 Seconds"
        case .whenDimmed: "When the Trackpad Dims"
        }
    }

    /// Heartbeats stop after this long without a touch.
    public var idleTimeout: TimeInterval {
        switch self {
        case .twoMinutes, .whenDimmed: GlasspadService.heartbeatIdleTimeout
        case .thirtySeconds: 30
        }
    }

    /// Whether heartbeats may run while the trackpad is dimmed.
    public var runsWhileDimmed: Bool { self != .whenDimmed }
}
