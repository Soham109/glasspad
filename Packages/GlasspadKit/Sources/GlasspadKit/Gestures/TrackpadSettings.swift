import Foundation

public enum SecondaryClick: String, Codable, Sendable, CaseIterable { case twoFinger, bottomRight, bottomLeft, off }
public enum LookUp: String, Codable, Sendable, CaseIterable { case forceClick, threeFingerTap, off }
public enum SwipePages: String, Codable, Sendable, CaseIterable { case twoFinger, threeFinger, twoOrThree, off }
public enum FingerCount: String, Codable, Sendable, CaseIterable {
    case three, four, off
    /// True when a swipe with `n` fingers should trigger this gesture.
    public func matches(_ n: Int) -> Bool {
        switch self {
        case .three: return n == 3
        case .four: return n == 4
        case .off: return false
        }
    }
}
public enum ClickPressure: String, Codable, Sendable, CaseIterable { case light, medium, firm }

/// The user's macOS trackpad preferences, read on the Mac and pushed to the phone.
public struct TrackpadSettings: Codable, Equatable, Sendable {
    public var trackingSpeed: Double
    public var naturalScrolling: Bool
    public var tapToClick: Bool
    public var secondaryClick: SecondaryClick
    public var threeFingerDrag: Bool
    public var lookUp: LookUp
    public var scrollMomentum: Bool
    public var pinchToZoom: Bool
    public var rotate: Bool
    public var smartZoom: Bool
    public var swipeBetweenPages: SwipePages
    public var swipeBetweenSpaces: FingerCount
    public var missionControl: FingerCount
    public var appExpose: FingerCount
    public var launchpadPinch: Bool
    public var showDesktopSpread: Bool
    public var notificationCenterEdge: Bool
    public var clickPressure: ClickPressure
    public var hapticStrength: Double
    /// The Mac's trackpad scrolling speed (`com.apple.trackpad.scrolling`, 0...1; macOS default
    /// 0.3125, the `HIDTrackpadScrollAcceleration` the HID system reports). Added later: older
    /// peers omit it and it decodes as the default.
    public var scrollSpeed: Double = TrackpadSettings.defaultScrollSpeed
    /// Glasspad's own feel controls, set on the phone and sent to the Mac (see `TrackpadTuning`).
    /// Added later: older peers omit it and it decodes as `.default`.
    public var tuning: TrackpadTuning = .default

    /// macOS default trackpad scrolling speed.
    public static let defaultScrollSpeed: Double = 0.3125

    public init(trackingSpeed: Double, naturalScrolling: Bool, tapToClick: Bool, secondaryClick: SecondaryClick,
                threeFingerDrag: Bool, lookUp: LookUp, scrollMomentum: Bool, pinchToZoom: Bool, rotate: Bool,
                smartZoom: Bool, swipeBetweenPages: SwipePages, swipeBetweenSpaces: FingerCount,
                missionControl: FingerCount, appExpose: FingerCount, launchpadPinch: Bool, showDesktopSpread: Bool,
                notificationCenterEdge: Bool, clickPressure: ClickPressure, hapticStrength: Double) {
        self.trackingSpeed = trackingSpeed
        self.naturalScrolling = naturalScrolling
        self.tapToClick = tapToClick
        self.secondaryClick = secondaryClick
        self.threeFingerDrag = threeFingerDrag
        self.lookUp = lookUp
        self.scrollMomentum = scrollMomentum
        self.pinchToZoom = pinchToZoom
        self.rotate = rotate
        self.smartZoom = smartZoom
        self.swipeBetweenPages = swipeBetweenPages
        self.swipeBetweenSpaces = swipeBetweenSpaces
        self.missionControl = missionControl
        self.appExpose = appExpose
        self.launchpadPinch = launchpadPinch
        self.showDesktopSpread = showDesktopSpread
        self.notificationCenterEdge = notificationCenterEdge
        self.clickPressure = clickPressure
        self.hapticStrength = hapticStrength
    }

    private enum CodingKeys: String, CodingKey {
        case trackingSpeed, naturalScrolling, tapToClick, secondaryClick, threeFingerDrag, lookUp
        case scrollMomentum, pinchToZoom, rotate, smartZoom, swipeBetweenPages, swipeBetweenSpaces
        case missionControl, appExpose, launchpadPinch, showDesktopSpread, notificationCenterEdge
        case clickPressure, hapticStrength, scrollSpeed, tuning
    }

    /// Every field from before `scrollSpeed` and `tuning` is required; those two are optional so
    /// an older Mac or phone still talks to this one.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trackingSpeed = try c.decode(Double.self, forKey: .trackingSpeed)
        naturalScrolling = try c.decode(Bool.self, forKey: .naturalScrolling)
        tapToClick = try c.decode(Bool.self, forKey: .tapToClick)
        secondaryClick = try c.decode(SecondaryClick.self, forKey: .secondaryClick)
        threeFingerDrag = try c.decode(Bool.self, forKey: .threeFingerDrag)
        lookUp = try c.decode(LookUp.self, forKey: .lookUp)
        scrollMomentum = try c.decode(Bool.self, forKey: .scrollMomentum)
        pinchToZoom = try c.decode(Bool.self, forKey: .pinchToZoom)
        rotate = try c.decode(Bool.self, forKey: .rotate)
        smartZoom = try c.decode(Bool.self, forKey: .smartZoom)
        swipeBetweenPages = try c.decode(SwipePages.self, forKey: .swipeBetweenPages)
        swipeBetweenSpaces = try c.decode(FingerCount.self, forKey: .swipeBetweenSpaces)
        missionControl = try c.decode(FingerCount.self, forKey: .missionControl)
        appExpose = try c.decode(FingerCount.self, forKey: .appExpose)
        launchpadPinch = try c.decode(Bool.self, forKey: .launchpadPinch)
        showDesktopSpread = try c.decode(Bool.self, forKey: .showDesktopSpread)
        notificationCenterEdge = try c.decode(Bool.self, forKey: .notificationCenterEdge)
        clickPressure = try c.decode(ClickPressure.self, forKey: .clickPressure)
        hapticStrength = try c.decode(Double.self, forKey: .hapticStrength)
        scrollSpeed = try c.decodeIfPresent(Double.self, forKey: .scrollSpeed) ?? Self.defaultScrollSpeed
        tuning = (try? c.decodeIfPresent(TrackpadTuning.self, forKey: .tuning)) ?? .default
    }

    /// A fresh macOS install's trackpad settings.
    public static let macDefault = TrackpadSettings(
        trackingSpeed: 1.0, naturalScrolling: true, tapToClick: false, secondaryClick: .twoFinger,
        threeFingerDrag: false, lookUp: .forceClick, scrollMomentum: true, pinchToZoom: true, rotate: true,
        smartZoom: true, swipeBetweenPages: .twoFinger, swipeBetweenSpaces: .three, missionControl: .three,
        appExpose: .off, launchpadPinch: true, showDesktopSpread: true, notificationCenterEdge: true,
        clickPressure: .medium, hapticStrength: 0.7)
}

/// How finger speed changes pointer speed.
public enum PointerAcceleration: String, Codable, Sendable, CaseIterable {
    /// The Mac's own trackpad curve for the current tracking speed (the default).
    case mac
    /// A fixed gain, equal to the Mac curve's gain at a medium finger speed.
    case linear
    /// No acceleration at all: 96 points per inch of finger travel, as macOS does with
    /// acceleration disabled.
    case off
}

/// Glasspad's own feel controls, on top of the Mac's trackpad settings. Chosen on the phone,
/// sent to the Mac inside `ControlMessage.settings`, applied by the recognizer on both sides.
/// Every field is optional on the wire, so new fields can be added without breaking peers.
public struct TrackpadTuning: Codable, Equatable, Sendable {
    /// Multiplier on pointer speed after the Mac's curve. 1 = match the Mac.
    public var pointerSpeed: Double = 1
    public var acceleration: PointerAcceleration = .mac
    /// Multiplier on scroll distance after the Mac's scroll curve. 1 = match the Mac.
    public var scrollSpeed: Double = 1
    /// Multiplier on how long momentum coasts after a flick. 1 = match the Mac, 0 = no momentum.
    public var momentumStrength: Double = 1
    /// Haptic strength per kind, 0...1, multiplied with the overall strength.
    public var clickHaptic: Double = 1
    public var forceClickHaptic: Double = 1
    public var dragLockHaptic: Double = 1

    public static let `default` = TrackpadTuning()

    /// Allowed ranges, used by the settings rows and by `clamped`.
    public static let pointerSpeedRange: ClosedRange<Double> = 0.25...4
    public static let scrollSpeedRange: ClosedRange<Double> = 0.25...4
    public static let momentumRange: ClosedRange<Double> = 0...2

    public init(pointerSpeed: Double = 1, acceleration: PointerAcceleration = .mac, scrollSpeed: Double = 1,
                momentumStrength: Double = 1, clickHaptic: Double = 1, forceClickHaptic: Double = 1,
                dragLockHaptic: Double = 1) {
        self.pointerSpeed = pointerSpeed
        self.acceleration = acceleration
        self.scrollSpeed = scrollSpeed
        self.momentumStrength = momentumStrength
        self.clickHaptic = clickHaptic
        self.forceClickHaptic = forceClickHaptic
        self.dragLockHaptic = dragLockHaptic
    }

    /// Every value pulled into its allowed range (values come over the network).
    public var clamped: TrackpadTuning {
        func c(_ v: Double, _ r: ClosedRange<Double>) -> Double { v.isFinite ? min(max(v, r.lowerBound), r.upperBound) : 1 }
        var t = self
        t.pointerSpeed = c(pointerSpeed, Self.pointerSpeedRange)
        t.scrollSpeed = c(scrollSpeed, Self.scrollSpeedRange)
        t.momentumStrength = c(momentumStrength, Self.momentumRange)
        t.clickHaptic = c(clickHaptic, 0...1)
        t.forceClickHaptic = c(forceClickHaptic, 0...1)
        t.dragLockHaptic = c(dragLockHaptic, 0...1)
        return t
    }

    /// Strength multiplier for one haptic kind (kinds that no longer play return 0).
    public func hapticScale(for kind: HapticKind) -> Double {
        switch kind {
        case .click: clickHaptic
        case .forceClick: forceClickHaptic
        case .dragLock: dragLockHaptic
        case .detent, .snap, .error: 0
        }
    }

    private enum CodingKeys: String, CodingKey {
        case pointerSpeed, acceleration, scrollSpeed, momentumStrength, clickHaptic, forceClickHaptic, dragLockHaptic
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TrackpadTuning()
        pointerSpeed = (try? c.decodeIfPresent(Double.self, forKey: .pointerSpeed)) ?? d.pointerSpeed
        acceleration = (try? c.decodeIfPresent(PointerAcceleration.self, forKey: .acceleration)) ?? d.acceleration
        scrollSpeed = (try? c.decodeIfPresent(Double.self, forKey: .scrollSpeed)) ?? d.scrollSpeed
        momentumStrength = (try? c.decodeIfPresent(Double.self, forKey: .momentumStrength)) ?? d.momentumStrength
        clickHaptic = (try? c.decodeIfPresent(Double.self, forKey: .clickHaptic)) ?? d.clickHaptic
        forceClickHaptic = (try? c.decodeIfPresent(Double.self, forKey: .forceClickHaptic)) ?? d.forceClickHaptic
        dragLockHaptic = (try? c.decodeIfPresent(Double.self, forKey: .dragLockHaptic)) ?? d.dragLockHaptic
    }
}
