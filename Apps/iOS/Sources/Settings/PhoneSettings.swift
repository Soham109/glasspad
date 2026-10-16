import Foundation
import GlasspadKit
import Observation

/// How the dot under each finger looks.
enum DotStyle: String, CaseIterable, Identifiable, Sendable {
    /// A soft-edged blur, like a fingertip on frosted glass.
    case soft
    /// A crisp filled circle.
    case solid
    /// An outline only.
    case ring

    var id: String { rawValue }
}

/// How big the dot under each finger is: three sizes, as points across.
enum DotSize: Double, CaseIterable, Identifiable, Sendable {
    case small = 34, medium = 44, large = 56

    var id: Double { rawValue }
    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// The size closest to a stored diameter (older builds saved any value from a slider).
    init(points: Double) {
        self = Self.allCases.min { abs($0.rawValue - points) < abs($1.rawValue - points) } ?? .medium
    }
}

/// Where the mode pill sits.
enum PillPosition: String, CaseIterable, Identifiable, Sendable {
    case top, bottom
    var id: String { rawValue }
    var title: String { self == .top ? "Top" : "Bottom" }
}

/// Which haptics play. Each can be turned off on its own.
enum HapticChannel: String, CaseIterable, Identifiable, Sendable {
    case click, forceClick, detent, snap, error, buttons
    var id: String { rawValue }

    var title: String {
        switch self {
        case .click: "Clicks"
        case .forceClick: "Force Click"
        case .detent: "Action Done"
        case .snap: "Paired, Copied or Saved"
        case .error: "Errors"
        case .buttons: "Button Taps"
        }
    }

    var symbol: String {
        switch self {
        case .click: "cursorarrow.click"
        case .forceClick: "hand.point.up.braille"
        case .detent: "checkmark.circle"
        case .snap: "checkmark.seal"
        case .error: "exclamationmark.triangle"
        case .buttons: "square.grid.2x2"
        }
    }

    init(_ cue: HapticCue) {
        switch cue {
        case .click, .dragLock: self = .click
        case .forceClickRamp, .forceClickDeep: self = .forceClick
        case .detent: self = .detent
        case .snap: self = .snap
        case .error: self = .error
        }
    }

    init(_ kind: HapticKind) {
        switch kind {
        case .click, .dragLock: self = .click
        case .forceClick: self = .forceClick
        case .detent: self = .detent
        case .snap: self = .snap
        case .error: self = .error
        }
    }
}

/// Settings that belong to the phone. Trackpad behaviour (speed, scrolling direction,
/// gestures) comes from the Mac and is never stored here.
@MainActor
@Observable
final class PhoneSettings {
    static let shared = PhoneSettings()

    /// Choices for how long the trackpad waits before dimming. 0 means never.
    static let dimDelayChoices: [TimeInterval] = [30, 60, 120, 300, 0]
    static let dotSizeRange: ClosedRange<Double> = 28...72

    // Look
    var theme: ThemeChoice { didSet { defaults.set(theme.rawValue, forKey: Key.theme) } }
    /// Goes up each time a new photo is made the Photo theme's backdrop. Setting the theme to
    /// the value it already has tells no view, so screens watch this to redraw with the photo.
    var photoVersion = 0
    var showDots: Bool { didSet { defaults.set(showDots, forKey: Key.showDots) } }
    var dotSizeChoice: DotSize { didSet { defaults.set(dotSizeChoice.rawValue, forKey: Key.dotSize) } }
    /// Points across.
    var dotSize: Double { dotSizeChoice.rawValue }
    /// The dot's look and opacity are the theme's own. Settings for them existed once; any
    /// value they saved is ignored.
    let dotStyle: DotStyle = .soft
    let dotOpacity: Double = 1
    var pillPosition: PillPosition { didSet { defaults.set(pillPosition.rawValue, forKey: Key.pillPosition) } }
    var leftHanded: Bool { didSet { defaults.set(leftHanded, forKey: Key.leftHanded) } }

    // Feel
    /// 0...1. Multiplied by the Mac's click firmness.
    var hapticStrength: Double { didSet { defaults.set(hapticStrength, forKey: Key.hapticStrength) } }
    var hapticsOff: Set<HapticChannel> {
        didSet { defaults.set(hapticsOff.map(\.rawValue).sorted(), forKey: Key.hapticsOff) }
    }

    // Screen
    var dimDelay: TimeInterval { didSet { defaults.set(dimDelay, forKey: Key.dimDelay) } }
    /// Keep the screen on while the trackpad or Present is showing.
    var keepScreenAwake: Bool { didSet { defaults.set(keepScreenAwake, forKey: Key.keepScreenAwake) } }

    // Modes
    /// nil = open the last used mode.
    var launchMode: AppMode? { didSet { defaults.set(launchMode?.rawValue ?? "", forKey: Key.launchMode) } }
    var dockDensity: DockDensity { didSet { defaults.set(dockDensity.rawValue, forKey: Key.dockDensity) } }
    /// Dock icons follow `dockDensity` alone. A fine tune slider used to sit under it; any
    /// value it saved is ignored.
    let dockIconScale: Double = 1
    var dockShowsNames: Bool { didSet { defaults.set(dockShowsNames, forKey: Key.dockShowsNames) } }
    var dockShowsRecent: Bool { didSet { defaults.set(dockShowsRecent, forKey: Key.dockShowsRecent) } }
    /// The phone's own Dock order, hidden apps and kept apps.
    var dockArrangement: DockArrangement {
        didSet { if let d = try? JSONEncoder().encode(dockArrangement) { defaults.set(d, forKey: Key.dockArrangement) } }
    }
    var keysShowsShortcuts: Bool { didSet { defaults.set(keysShowsShortcuts, forKey: Key.keysShowsShortcuts) } }
    /// Keyboard shows F1 to F12, brightness and volume in place of the shortcut row.
    var keysShowsFunctionRow: Bool { didSet { defaults.set(keysShowsFunctionRow, forKey: Key.keysShowsFunctionRow) } }
    /// The first-run checklist was finished; it never opens by itself again.
    var setupComplete: Bool { didSet { defaults.set(setupComplete, forKey: Key.setupComplete) } }
    var presentStartsTimer: Bool { didSet { defaults.set(presentStartsTimer, forKey: Key.presentStartsTimer) } }
    var deckShowsTitles: Bool { didSet { defaults.set(deckShowsTitles, forKey: Key.deckShowsTitles) } }
    /// Deck tile size, 0.85...1.3 (multiplies the compact base size).
    var deckTileScale: Double { didSet { defaults.set(deckTileScale, forKey: Key.deckTileScale) } }
    /// Which front-app buttons Actions shows, in order, per Mac app bundle id (keys from
    /// `FrontAppItem.id`). An app without an entry shows its first eight.
    var frontAppPicks: [String: [String]] {
        didSet { if let d = try? JSONEncoder().encode(frontAppPicks) { defaults.set(d, forKey: Key.frontAppPicks) } }
    }
    /// Macs whose Deck was already moved to the one-screen Actions layout (Mac ids).
    var pinnedMigratedMacs: Set<String> {
        didSet { defaults.set(Array(pinnedMigratedMacs).sorted(), forKey: Key.pinnedMigratedMacs) }
    }
    /// Which modes show, their order, and whether Actions is split up.
    var modeList: ModeListLayout {
        didSet { if let d = try? JSONEncoder().encode(modeList) { defaults.set(d, forKey: Key.modeList) } }
    }
    /// First-run tips already shown, by id.
    var seenTips: Set<String> { didSet { defaults.set(Array(seenTips).sorted(), forKey: Key.seenTips) } }

    // Other
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
        static let dotSize = "dotSize"
        static let pillPosition = "pillPosition", hapticsOff = "hapticsOff", keepScreenAwake = "keepScreenAwake"
        static let launchMode = "launchMode", dockDensity = "dockDensity"
        static let dockShowsNames = "dockShowsNames", dockShowsRecent = "dockShowsRecent"
        static let dockArrangement = "dockArrangement", keysShowsShortcuts = "keysShowsShortcuts"
        static let keysShowsFunctionRow = "keysShowsFunctionRow", setupComplete = "setupComplete"
        static let presentStartsTimer = "presentStartsTimer"
        static let deckShowsTitles = "deckShowsTitles"
        static let deckTileScale = "deckTileScale", modeList = "modeList", seenTips = "seenTips"
        static let frontAppPicks = "frontAppPicks", pinnedMigratedMacs = "pinnedMigratedMacs"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        func double(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
            (defaults.object(forKey: key) as? Double).map { min(range.upperBound, max(range.lowerBound, $0)) } ?? fallback
        }
        // A theme this build does not know (from a newer build) falls back to System.
        theme = defaults.string(forKey: Key.theme).map(ThemeChoice.init(saved:)) ?? .paper
        hapticStrength = double(Key.hapticStrength, 0.7, 0...1)
        showDots = bool(Key.showDots, true)
        dotSizeChoice = DotSize(points: double(Key.dotSize, DotSize.medium.rawValue, Self.dotSizeRange))
        pillPosition = PillPosition(rawValue: defaults.string(forKey: Key.pillPosition) ?? "") ?? .top
        leftHanded = defaults.bool(forKey: Key.leftHanded)
        hapticsOff = Set((defaults.stringArray(forKey: Key.hapticsOff) ?? []).compactMap(HapticChannel.init(rawValue:)))
        let delay = defaults.object(forKey: Key.dimDelay) as? Double ?? 60
        dimDelay = Self.dimDelayChoices.contains(delay) ? delay : 60
        keepScreenAwake = bool(Key.keepScreenAwake, true)
        launchMode = AppMode(rawValue: defaults.string(forKey: Key.launchMode) ?? "")
        dockDensity = DockDensity(rawValue: defaults.string(forKey: Key.dockDensity) ?? "") ?? .regular
        dockShowsNames = bool(Key.dockShowsNames, true)
        dockShowsRecent = bool(Key.dockShowsRecent, true)
        dockArrangement = defaults.data(forKey: Key.dockArrangement)
            .flatMap { try? JSONDecoder().decode(DockArrangement.self, from: $0) } ?? DockArrangement()
        keysShowsShortcuts = bool(Key.keysShowsShortcuts, true)
        keysShowsFunctionRow = bool(Key.keysShowsFunctionRow, false)
        setupComplete = bool(Key.setupComplete, false)
        presentStartsTimer = bool(Key.presentStartsTimer, true)
        deckShowsTitles = bool(Key.deckShowsTitles, true)
        deckTileScale = double(Key.deckTileScale, 1, 0.85...1.3)
        frontAppPicks = defaults.data(forKey: Key.frontAppPicks)
            .flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
        pinnedMigratedMacs = Set(defaults.stringArray(forKey: Key.pinnedMigratedMacs) ?? [])
        // Actions is always one mode now; a list saved split shows Actions in their place.
        modeList = (defaults.data(forKey: Key.modeList).flatMap { try? JSONDecoder().decode(ModeListLayout.self, from: $0) }
            ?? ModeListLayout()).actionsCombined
        seenTips = Set(defaults.stringArray(forKey: Key.seenTips) ?? [])
        hasOnboarded = defaults.bool(forKey: Key.hasOnboarded)
        phoneName = defaults.string(forKey: Key.phoneName) ?? "iPhone"
        lastMode = AppMode(rawValue: defaults.string(forKey: Key.lastMode) ?? "") ?? .trackpad
        orientation = OrientationChoice(rawValue: defaults.string(forKey: Key.orientation) ?? "") ?? .automatic
    }

    /// The mode to open at launch.
    var startMode: AppMode { (launchMode ?? lastMode).shown }

    /// False when that kind of haptic is switched off.
    func allowsHaptic(_ kind: HapticKind) -> Bool { !hapticsOff.contains(HapticChannel(kind)) }

    func setHaptic(_ channel: HapticChannel, on: Bool) {
        if on { hapticsOff.remove(channel) } else { hapticsOff.insert(channel) }
    }

    /// Haptics that the trackpad's own strength sliders cover (each slider turns its kind off
    /// at 0), so Settings has no separate switch for them.
    static let slidersCoverHaptics: Set<HapticChannel> = [.click, .forceClick]

    /// Clicks and Force Click once had a switch as well as a slider. A switch left off becomes
    /// its slider at 0, so nothing starts buzzing that was silent.
    func moveHapticSwitches(into store: TrackpadTuningStore) {
        let off = hapticsOff.intersection(Self.slidersCoverHaptics)
        guard !off.isEmpty else { return }
        var t = store.tuning
        if off.contains(.click) { t.clickHaptic = 0; t.dragLockHaptic = 0 }
        if off.contains(.forceClick) { t.forceClickHaptic = 0 }
        store.tuning = t
        hapticsOff.subtract(off)
    }

    /// Puts every look and feel setting back to how Glasspad ships.
    func resetLookAndFeel() {
        theme = .paper
        showDots = true
        dotSizeChoice = .medium
        pillPosition = .top
        hapticStrength = 0.7
        hapticsOff = []
        dockDensity = .regular
        dockShowsNames = true
        dockShowsRecent = true
    }
}
