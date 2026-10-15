import Foundation
import GlasspadKit

/// Reads the user's real macOS trackpad preferences (read only, never writes) and maps them
/// to `TrackpadSettings`.
///
/// Key names and values were confirmed on macOS 26.6 (build 25G72) with
/// `defaults read com.apple.AppleMultitouchTrackpad`,
/// `defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad` and `defaults read -g`.
/// System Settings writes the same keys to both trackpad domains; the built-in domain is
/// preferred, the Bluetooth (Magic Trackpad) domain fills in any key it lacks.
///
/// | TrackpadSettings field   | Domain | Key                                         | Mapping |
/// |--------------------------|--------|---------------------------------------------|---------|
/// | trackingSpeed            | -g     | com.apple.trackpad.scaling                  | Double, clamped 0...3 (observed "0.875") |
/// | naturalScrolling         | -g     | com.apple.swipescrolldirection              | 1 = natural (observed 1) |
/// | tapToClick               | tp     | Clicking                                    | 1 = on |
/// | secondaryClick           | tp     | TrackpadRightClick, TrackpadCornerSecondaryClick | RightClick 1 = twoFinger; else Corner 2 = bottomRight, 1 = bottomLeft; else off (observed RightClick 0, Corner 2) |
/// | threeFingerDrag          | tp     | TrackpadThreeFingerDrag                     | 1 = on |
/// | lookUp                   | tp, -g | TrackpadThreeFingerTapGesture, com.apple.trackpad.forceClick | Tap 2 = threeFingerTap; else forceClick 1 = forceClick; else off |
/// | scrollMomentum           | tp     | TrackpadMomentumScroll                      | 1 = on |
/// | pinchToZoom              | tp     | TrackpadPinch                               | 1 = on |
/// | rotate                   | tp     | TrackpadRotate                              | 1 = on |
/// | smartZoom                | tp     | TrackpadTwoFingerDoubleTapGesture           | 1 = on |
/// | swipeBetweenPages        | -g, tp | AppleEnableSwipeNavigateWithScrolls, TrackpadThreeFingerHorizSwipeGesture | scroll(default 1) + 3H==1 = twoOrThree; scroll only = twoFinger; 3H==1 only = threeFinger; neither = off |
/// | swipeBetweenSpaces       | tp     | TrackpadThreeFingerHorizSwipeGesture, TrackpadFourFingerHorizSwipeGesture | 3H==2 = three; else 4H==2 = four; else off (observed both 2) |
/// | missionControl           | tp, dock | Three/FourFingerVertSwipeGesture, showMissionControlGestureEnabled | 3V==2 = three; else 4V==2 = four; off if dock key is 0 (default on) |
/// | appExpose                | tp, dock | same vertical keys, showAppExposeGestureEnabled | as above, but dock key defaults to off |
/// | launchpadPinch           | tp, dock | TrackpadFourFingerPinchGesture / FiveFinger, showLaunchpadGestureEnabled | pinch==2 and dock key not 0 (default on) |
/// | showDesktopSpread        | tp, dock | TrackpadFourFingerPinchGesture / FiveFinger, showDesktopGestureEnabled | pinch==2 and dock key not 0 (default on) |
/// | notificationCenterEdge   | tp     | TrackpadTwoFingerFromRightEdgeSwipeGesture  | 3 = on, 0 = off (observed 3) |
/// | clickPressure            | tp     | FirstClickThreshold                         | 0 light, 1 medium, 2 firm (observed 1) |
/// | hapticStrength           | -      | phone-side only                             | left at the default |
///
/// `tp` = com.apple.AppleMultitouchTrackpad, falling back to
/// com.apple.driver.AppleBluetoothMultitouch.trackpad. `dock` = com.apple.dock.
/// Missing keys fall back to `TrackpadSettings.macDefault`.
public struct TrackpadPrefsSnapshot: @unchecked Sendable, Equatable {
    public var trackpad: [String: Any]
    public var bluetoothTrackpad: [String: Any]
    public var global: [String: Any]
    public var dock: [String: Any]

    public init(trackpad: [String: Any] = [:], bluetoothTrackpad: [String: Any] = [:],
                global: [String: Any] = [:], dock: [String: Any] = [:]) {
        self.trackpad = trackpad
        self.bluetoothTrackpad = bluetoothTrackpad
        self.global = global
        self.dock = dock
    }

    public static func == (a: Self, b: Self) -> Bool {
        NSDictionary(dictionary: a.trackpad).isEqual(to: b.trackpad)
            && NSDictionary(dictionary: a.bluetoothTrackpad).isEqual(to: b.bluetoothTrackpad)
            && NSDictionary(dictionary: a.global).isEqual(to: b.global)
            && NSDictionary(dictionary: a.dock).isEqual(to: b.dock)
    }
}

public enum TrackpadPrefsReader {
    public static let trackpadDomain = "com.apple.AppleMultitouchTrackpad"
    public static let bluetoothDomain = "com.apple.driver.AppleBluetoothMultitouch.trackpad"
    public static let dockDomain = "com.apple.dock"

    /// Global-domain keys we care about (reading the whole global domain is large).
    static let globalKeys = [
        "com.apple.trackpad.scaling",
        "com.apple.swipescrolldirection",
        "com.apple.trackpad.forceClick",
        "AppleEnableSwipeNavigateWithScrolls",
    ]
    static let dockKeys = [
        "showMissionControlGestureEnabled",
        "showAppExposeGestureEnabled",
        "showLaunchpadGestureEnabled",
        "showDesktopGestureEnabled",
    ]

    /// Reads the live preference domains through CFPreferences (read only).
    public static func readSnapshot() -> TrackpadPrefsSnapshot {
        func domain(_ name: String) -> [String: Any] {
            CFPreferencesAppSynchronize(name as CFString)
            let keys = CFPreferencesCopyKeyList(name as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            guard let keys,
                  let dict = CFPreferencesCopyMultiple(keys, name as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Any]
            else { return [:] }
            return dict
        }
        func values(_ keys: [String], app: CFString) -> [String: Any] {
            CFPreferencesAppSynchronize(app)
            var out: [String: Any] = [:]
            for k in keys {
                if let v = CFPreferencesCopyAppValue(k as CFString, app) { out[k] = v }
            }
            return out
        }
        return TrackpadPrefsSnapshot(
            trackpad: domain(trackpadDomain),
            bluetoothTrackpad: domain(bluetoothDomain),
            global: values(globalKeys, app: kCFPreferencesAnyApplication),
            dock: values(dockKeys, app: dockDomain as CFString)
        )
    }

    public static func read() -> TrackpadSettings { map(readSnapshot()) }

    /// Pure mapping, unit tested with sample dictionaries.
    public static func map(_ s: TrackpadPrefsSnapshot) -> TrackpadSettings {
        var out = TrackpadSettings.macDefault

        func tp(_ key: String) -> Int? { int(s.trackpad[key]) ?? int(s.bluetoothTrackpad[key]) }
        func tpBool(_ key: String) -> Bool? { tp(key).map { $0 != 0 } }

        if let speed = double(s.global["com.apple.trackpad.scaling"]) {
            out.trackingSpeed = min(3, max(0, speed))
        }
        if let natural = int(s.global["com.apple.swipescrolldirection"]) { out.naturalScrolling = natural != 0 }
        if let v = tpBool("Clicking") { out.tapToClick = v }

        let right = tp("TrackpadRightClick")
        let corner = tp("TrackpadCornerSecondaryClick")
        if right != nil || corner != nil {
            if right == 1 { out.secondaryClick = .twoFinger }
            else if corner == 2 { out.secondaryClick = .bottomRight }
            else if corner == 1 { out.secondaryClick = .bottomLeft }
            else { out.secondaryClick = .off }
        }

        if let v = tpBool("TrackpadThreeFingerDrag") { out.threeFingerDrag = v }

        let threeTap = tp("TrackpadThreeFingerTapGesture")
        let force = int(s.global["com.apple.trackpad.forceClick"])
        if threeTap != nil || force != nil {
            if threeTap == 2 { out.lookUp = .threeFingerTap }
            else if (force ?? 1) != 0 { out.lookUp = .forceClick }
            else { out.lookUp = .off }
        }

        if let v = tpBool("TrackpadMomentumScroll") { out.scrollMomentum = v }
        if let v = tpBool("TrackpadPinch") { out.pinchToZoom = v }
        if let v = tpBool("TrackpadRotate") { out.rotate = v }
        if let v = tpBool("TrackpadTwoFingerDoubleTapGesture") { out.smartZoom = v }

        let threeH = tp("TrackpadThreeFingerHorizSwipeGesture")
        let fourH = tp("TrackpadFourFingerHorizSwipeGesture")
        let navScroll = (int(s.global["AppleEnableSwipeNavigateWithScrolls"]) ?? 1) != 0
        switch (navScroll, threeH == 1) {
        case (true, true): out.swipeBetweenPages = .twoOrThree
        case (true, false): out.swipeBetweenPages = .twoFinger
        case (false, true): out.swipeBetweenPages = .threeFinger
        case (false, false): out.swipeBetweenPages = .off
        }
        if threeH != nil || fourH != nil {
            out.swipeBetweenSpaces = threeH == 2 ? .three : (fourH == 2 ? .four : .off)
        }

        let threeV = tp("TrackpadThreeFingerVertSwipeGesture")
        let fourV = tp("TrackpadFourFingerVertSwipeGesture")
        let vertical: FingerCount? = (threeV != nil || fourV != nil)
            ? (threeV == 2 ? .three : (fourV == 2 ? .four : .off)) : nil
        let mcOn = (int(s.dock["showMissionControlGestureEnabled"]) ?? 1) != 0
        let exposeOn = (int(s.dock["showAppExposeGestureEnabled"]) ?? 0) != 0
        if let vertical {
            out.missionControl = mcOn ? vertical : .off
            out.appExpose = exposeOn ? vertical : .off
        } else {
            if !mcOn { out.missionControl = .off }
            if !exposeOn { out.appExpose = .off }
        }

        let pinch4 = tp("TrackpadFourFingerPinchGesture")
        let pinch5 = tp("TrackpadFiveFingerPinchGesture")
        if pinch4 != nil || pinch5 != nil {
            let pinchOn = pinch4 == 2 || pinch5 == 2
            out.launchpadPinch = pinchOn && (int(s.dock["showLaunchpadGestureEnabled"]) ?? 1) != 0
            out.showDesktopSpread = pinchOn && (int(s.dock["showDesktopGestureEnabled"]) ?? 1) != 0
        }

        if let edge = tp("TrackpadTwoFingerFromRightEdgeSwipeGesture") { out.notificationCenterEdge = edge == 3 }

        switch tp("FirstClickThreshold") {
        case 0: out.clickPressure = .light
        case 1: out.clickPressure = .medium
        case 2: out.clickPressure = .firm
        default: break
        }
        return out
    }

    static func int(_ v: Any?) -> Int? {
        switch v {
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s) ?? Double(s).map { Int($0) }
        default: return nil
        }
    }

    static func double(_ v: Any?) -> Double? {
        switch v {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }
}
