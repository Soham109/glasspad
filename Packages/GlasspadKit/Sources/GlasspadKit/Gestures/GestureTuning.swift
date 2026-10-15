import Foundation

/// Every gesture threshold in one place. Distances are phone points unless noted,
/// times are seconds, speeds are phone points per second.
public enum GestureTuning {
    // MARK: Taps and clicks
    /// Longest finger-down time that still counts as a tap.
    public static let tapMaxDuration: TimeInterval = 0.30
    /// Farthest any finger may travel and still count as a tap.
    public static let tapSlop: Double = 10
    /// Taps closer together than this (and near each other) raise the click count.
    public static let doubleClickInterval: TimeInterval = 0.45
    /// Max distance between taps for a double or triple click.
    public static let doubleClickRadius: Double = 30
    /// Highest click count reported.
    public static let maxClickCount = 3
    /// After a tap, touching again within this window and moving starts a drag.
    public static let tapDragWindow: TimeInterval = 0.25
    /// Max distance from the tap for the tap-drag second touch.
    public static let tapDragRadius: Double = 60
    /// Bottom-corner secondary click zone, as fractions of surface width and height.
    public static let cornerWidthFraction: Double = 0.4
    public static let cornerHeightFraction: Double = 0.25
    /// Gap allowed between two two-finger taps for smart magnify; a pending right click waits this long.
    public static let smartZoomGap: TimeInterval = 0.25

    // MARK: Force click (press and hold)
    /// Hold still this long for force click stage 1 (left button goes down).
    public static let forceClickStage1Delay: TimeInterval = 0.45
    /// Further hold after stage 1 for stage 2 (deep press).
    public static let forceClickStage2Delay: TimeInterval = 0.25
    /// Movement allowed while holding.
    public static let holdSlop: Double = 8

    // MARK: Pointer
    /// One finger must move this far before the pointer starts moving.
    public static let pointerStartSlop: Double = 4
    /// Movement past which a held button (tap-drag, hold, three-finger) starts dragging.
    public static let dragStartSlop: Double = 4
    /// Display width assumed until the Mac sets `GestureRecognizer.displayWidth` (Mac points).
    /// Pointer gain no longer depends on it (it follows the Mac's curve in physical units).
    public static let defaultDisplayWidth: Double = 1512
    /// Phone screen points per inch. iPhone Pro screens are 460 pixels per inch at 3x, so
    /// 153.3 points per inch (6.04 points per mm). Turns touch travel into physical travel,
    /// which is what the Mac's acceleration curve is defined on.
    public static let phonePointsPerInch: Double = 460.0 / 3.0
    /// Finger speed is travel per frame over at least this much time: one report of the Mac's
    /// own trackpad (120 Hz), so the curve sees the same speeds it does on the real trackpad.
    public static let speedWindow: TimeInterval = 1.0 / 120
    /// `PointerAcceleration.linear` uses the Mac curve's gain at this finger speed (inches/s).
    public static let linearReferenceSpeed: Double = 2.0
    /// Scroll pixels per inch, relative to the Mac pointer formula at the same speed on the
    /// scroll curve. First knob to tune if scrolling feels uniformly fast or slow.
    public static let scrollCalibration: Double = 1.5
    /// Frame interval clamp for speed estimates.
    public static let minFrameInterval: TimeInterval = 0.004
    public static let maxFrameInterval: TimeInterval = 0.05

    // MARK: Scroll
    /// Two fingers must translate this far together to start scrolling.
    public static let scrollStartDistance: Double = 8
    /// Velocity is measured over this much history before lift.
    public static let momentumSampleWindow: TimeInterval = 0.08
    /// If the fingers were still for this long before lifting, there is no momentum.
    public static let momentumStillCutoff: TimeInterval = 0.06
    /// Min release speed (pixels/s) to start momentum.
    public static let momentumMinSpeed: Double = 60
    /// Momentum ends below this speed (pixels/s).
    public static let momentumStopSpeed: Double = 12
    /// Momentum velocity kept per millisecond at momentum strength 1: the platform's normal
    /// scroll deceleration (UIScrollView.DecelerationRate.normal, 0.998), a time constant of
    /// about 0.5 s. Momentum strength s uses 0.998^(1/s).
    public static let momentumDecayPerMillisecond: Double = 0.998
    /// Longest tick gap integrated in one momentum step.
    public static let momentumMaxStep: TimeInterval = 0.1
    /// When one of two scrolling fingers lifts, the other has this long to follow for momentum.
    public static let scrollLiftGrace: TimeInterval = 0.12

    // MARK: Pinch and rotate
    /// Change in finger distance that starts a pinch.
    public static let pinchStartDistance: Double = 14
    /// Arc length (angle times half the finger distance) that starts rotation.
    public static let rotateStartArc: Double = 16

    // MARK: Swipes
    /// Average finger travel that locks a swipe's axis.
    public static let axisLockDistance: Double = 12
    /// Travel for progress 1.0 on a translation swipe.
    public static let swipeFullDistance: Double = 150
    /// Mean radial change that starts a launchpad pinch or show-desktop spread (4+ fingers).
    public static let spreadStartDistance: Double = 16
    /// Mean radial change for progress 1.0 on launchpad or show desktop.
    public static let spreadFullDistance: Double = 60
    /// Travel at which a three-finger page swipe fires `navigate`.
    public static let navigateDistance: Double = 50
    /// Fewest fingers for launchpad pinch / show desktop spread (thumb + three).
    public static let spreadMinFingers = 4

    // MARK: Edges
    /// Width of the right-edge zone that starts the notification-center swipe.
    public static let rightEdgeZone: Double = 24
    /// Leftward travel that opens notification center.
    public static let notificationCenterDistance: Double = 40

    // MARK: Robustness
    /// With fingers down and no frame for this long, everything is cancelled and buttons released.
    /// The client resends the last snapshot every 20 ms while fingers are down.
    public static let staleTouchTimeout: TimeInterval = 0.5
    /// A frame clock that jumps back more than this is treated as a new phone clock.
    public static let clockJumpTolerance: TimeInterval = 1.0
    /// A sequence number this far behind the last one is a sender restart, not a late packet.
    public static let seqResetDistance: UInt32 = 1024
    /// The learned phone-to-Mac clock offset may creep upward this fast (seconds per second),
    /// so the two clocks drifting apart never leaves it stale. 200 ppm is well above crystal drift.
    public static let clockOffsetCreep: Double = 0.0002
}
