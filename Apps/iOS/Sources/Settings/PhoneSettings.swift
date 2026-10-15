import Foundation
import Observation

/// Settings that belong to the phone. Trackpad behaviour (speed, scrolling direction,
/// gestures) comes from the Mac and is never stored here.
@MainActor
@Observable
final class PhoneSettings {
    static let shared = PhoneSettings()

    /// Choices for how long the trackpad waits before dimming.
    static let dimDelayChoices: [TimeInterval] = [30, 60, 120, 300]

    var theme: ThemeChoice { didSet { defaults.set(theme.rawValue, forKey: Key.theme) } }
    /// 0...1. Multiplied by the Mac's click firmness.
    var hapticStrength: Double { didSet { defaults.set(hapticStrength, forKey: Key.hapticStrength) } }
    var showDots: Bool { didSet { defaults.set(showDots, forKey: Key.showDots) } }
    var leftHanded: Bool { didSet { defaults.set(leftHanded, forKey: Key.leftHanded) } }
    var dimDelay: TimeInterval { didSet { defaults.set(dimDelay, forKey: Key.dimDelay) } }
    var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: Key.hasOnboarded) } }
    /// The name the Mac shows for this phone. iOS no longer tells apps the device's own name.
    var phoneName: String { didSet { defaults.set(phoneName, forKey: Key.phoneName) } }
    var lastMode: AppMode { didSet { defaults.set(lastMode.rawValue, forKey: Key.lastMode) } }
    /// Applies to every screen. The trackpad is the reason it exists: held sideways, the
    /// phone is the shape of a real trackpad.
    var orientation: OrientationChoice {
        didSet {
            guard orientation != oldValue else { return }
            defaults.set(orientation.rawValue, forKey: Key.orientation)
            OrientationLock.apply()
        }
    }

    private let defaults: UserDefaults

    private enum Key {
        static let theme = "theme", hapticStrength = "hapticStrength", showDots = "showDots"
        static let leftHanded = "leftHanded", dimDelay = "dimDelay", hasOnboarded = "hasOnboarded"
        static let phoneName = "phoneName", lastMode = "lastMode", orientation = "orientation"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = ThemeChoice(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .paper
        hapticStrength = defaults.object(forKey: Key.hapticStrength) as? Double ?? 0.7
        showDots = defaults.object(forKey: Key.showDots) as? Bool ?? true
        leftHanded = defaults.bool(forKey: Key.leftHanded)
        let delay = defaults.double(forKey: Key.dimDelay)
        dimDelay = Self.dimDelayChoices.contains(delay) ? delay : 60
        hasOnboarded = defaults.bool(forKey: Key.hasOnboarded)
        phoneName = defaults.string(forKey: Key.phoneName) ?? "iPhone"
        lastMode = AppMode(rawValue: defaults.string(forKey: Key.lastMode) ?? "") ?? .trackpad
        orientation = OrientationChoice(rawValue: defaults.string(forKey: Key.orientation) ?? "") ?? .automatic
    }
}
