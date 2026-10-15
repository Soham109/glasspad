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

    /// A fresh macOS install's trackpad settings.
    public static let macDefault = TrackpadSettings(
        trackingSpeed: 1.0, naturalScrolling: true, tapToClick: false, secondaryClick: .twoFinger,
        threeFingerDrag: false, lookUp: .forceClick, scrollMomentum: true, pinchToZoom: true, rotate: true,
        smartZoom: true, swipeBetweenPages: .twoFinger, swipeBetweenSpaces: .three, missionControl: .three,
        appExpose: .off, launchpadPinch: true, showDesktopSpread: true, notificationCenterEdge: true,
        clickPressure: .medium, hapticStrength: 0.7)
}
