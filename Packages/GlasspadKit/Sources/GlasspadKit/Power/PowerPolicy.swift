import Foundation

/// How hard the phone app may work, from the phone's heat and Low Power Mode. Pure, so the
/// rules are tested here; the app feeds it `ProcessInfo.thermalState` and
/// `isLowPowerModeEnabled` and asks it before running anything that costs battery but is not
/// what the user is doing right now (moving text, art, keep-awake, heartbeats).
///
/// What the user is doing is never slowed: pointer traffic, click haptics and taps go out as
/// before in every state. Only extras give way.
public struct PowerPolicy: Equatable, Sendable {
    /// Mirrors `ProcessInfo.ThermalState`, which this package cannot see on every platform.
    public enum Heat: Int, Comparable, Sendable {
        case nominal, fair, serious, critical
        public static func < (a: Heat, b: Heat) -> Bool { a.rawValue < b.rawValue }
    }

    public var heat: Heat
    public var lowPower: Bool

    public init(heat: Heat = .nominal, lowPower: Bool = false) {
        self.heat = heat
        self.lowPower = lowPower
    }

    /// `serious` or worse: haptics and keep-awake heartbeats pause until the phone cools.
    public var isWarm: Bool { heat >= .serious }

    /// Haptics play (the engine stays off while warm).
    public var allowsHaptics: Bool { !isWarm }

    /// Keep-awake heartbeats may run (they hold the Wi-Fi radio awake 50 times a second).
    public var allowsHeartbeats: Bool { !isWarm }

    /// Heartbeats stop after this long without a touch.
    public var heartbeatIdleTimeout: TimeInterval {
        lowPower ? Self.lowPowerHeartbeatIdle : GlasspadService.heartbeatIdleTimeout
    }
    public static let lowPowerHeartbeatIdle: TimeInterval = 10

    /// Frames a second for motion that only decorates (scrolling titles, onboarding art).
    /// 0 means hold still.
    public var decorativeFrameRate: Double {
        if isWarm { return 0 }
        if lowPower || heat == .fair { return 30 }
        return 60
    }

    /// The smallest step between frames of decorative motion, for
    /// `TimelineView(.animation(minimumInterval:))`; nil when it should not move at all.
    public var decorativeFrameInterval: TimeInterval? {
        let rate = decorativeFrameRate
        return rate > 0 ? 1 / rate : nil
    }

    /// How many times a title too long for its line scrolls by before it rests at its start.
    public var marqueePasses: Int {
        if isWarm { return 0 }
        return lowPower ? 1 : 3
    }

    /// How often a playing song's progress bar and clock redraw.
    public var progressInterval: TimeInterval { lowPower || isWarm ? 1 : 0.25 }

    /// Without a touch for this long, a screen that keeps the phone awake lets it lock again
    /// on its normal Auto-Lock. A touch keeps it awake again.
    public var keepAwakeLimit: TimeInterval {
        if heat == .critical { return 60 }
        if lowPower || isWarm { return 3 * 60 }
        return 10 * 60
    }

    /// Whether the screen should be held on now. Only a screen that needs it (the trackpad or
    /// Present), only with nothing on top, only while connected (nothing to control otherwise),
    /// and only until the user has left it alone for `keepAwakeLimit`.
    public func keepsScreenAwake(_ s: KeepAwakeInputs) -> Bool {
        s.sceneActive && s.enabled && s.screenNeedsIt && !s.coveredBySheet && s.connected
            && s.idle < keepAwakeLimit
    }
}

/// What `PowerPolicy.keepsScreenAwake` looks at.
public struct KeepAwakeInputs: Equatable, Sendable {
    /// The app is in front and active.
    public var sceneActive: Bool
    /// The user's Keep Screen On setting (and onboarding is done).
    public var enabled: Bool
    /// The trackpad or Present is showing.
    public var screenNeedsIt: Bool
    /// Settings, pairing, setup or Clipboard is on top.
    public var coveredBySheet: Bool
    /// A Mac is connected.
    public var connected: Bool
    /// Seconds since the last touch on the screen.
    public var idle: TimeInterval

    public init(sceneActive: Bool, enabled: Bool, screenNeedsIt: Bool, coveredBySheet: Bool,
                connected: Bool, idle: TimeInterval) {
        self.sceneActive = sceneActive
        self.enabled = enabled
        self.screenNeedsIt = screenNeedsIt
        self.coveredBySheet = coveredBySheet
        self.connected = connected
        self.idle = idle
    }
}

/// When the dimming screens' idle check should look next. Touches only note the time; the
/// check runs at the next moment something can change (the screen dims, or Keep Screen On lets
/// go), finds out how long the screen has really been left alone, and sets itself again.
public enum IdleDeadline {
    /// While a sheet or the editor is on top nothing dims, but whether it is still there is
    /// looked at this often (closing one also starts a fresh look).
    public static let blockedPoll: TimeInterval = 5
    /// Never sooner than this, so a deadline just passed does not spin.
    public static let minimumWait: TimeInterval = 0.25

    /// Seconds until the next look, or nil when nothing can change before the next touch.
    /// - Parameters:
    ///   - idle: seconds since the last touch.
    ///   - dimDelay: the Dim After setting, 0 for never.
    ///   - dimmed: the screen is dimmed already.
    ///   - holdingAwake: Keep Screen On holds the phone awake now.
    ///   - keepAwakeLimit: `PowerPolicy.keepAwakeLimit`.
    ///   - blocked: something on top holds the screen as it is.
    public static func next(idle: TimeInterval, dimDelay: TimeInterval, dimmed: Bool, holdingAwake: Bool,
                            keepAwakeLimit: TimeInterval, blocked: Bool) -> TimeInterval? {
        if blocked { return blockedPoll }
        var waits: [TimeInterval] = []
        if !dimmed, dimDelay > 0 { waits.append(dimDelay - idle) }
        if holdingAwake { waits.append(keepAwakeLimit - idle) }
        return waits.min().map { max(minimumWait, $0) }
    }
}
