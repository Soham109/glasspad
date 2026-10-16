import Foundation

/// Every look Glasspad ships with, as plain data: names, groups and each theme's colours in
/// light and dark. Kept here, away from UIKit, so a test can check every theme's contrast.
/// The phone builds its `Palette` from these (Apps/iOS/Sources/Design/Theme.swift).
public enum ThemeChoice: String, CaseIterable, Identifiable, Sendable {
    // Classic
    case system, paper, graphite, mono, pureBlack, highContrast
    // Glass
    case glass, glassDark, clear, aurora, ocean, dusk, rose, mint, lavender, ember, citrus, smoke
    // Colour
    case sand, midnight, forest, plum, slate, espresso, solar, frost, dawn

    public var id: String { rawValue }

    /// A saved choice from any build. Names this build does not know fall back to System.
    public init(saved raw: String?) {
        self = raw.flatMap(ThemeChoice.init(rawValue:)) ?? .system
    }

    public var title: String {
        switch self {
        case .system: "System"
        case .paper: "Paper"
        case .graphite: "Graphite"
        case .mono: "Mono"
        case .pureBlack: "Pure Black"
        case .highContrast: "High Contrast"
        case .glass: "Glass"
        case .glassDark: "Glass Dark"
        case .clear: "Clear"
        case .aurora: "Aurora"
        case .ocean: "Ocean"
        case .dusk: "Dusk"
        case .rose: "Rose"
        case .mint: "Mint"
        case .lavender: "Lavender"
        case .ember: "Ember"
        case .citrus: "Citrus"
        case .smoke: "Smoke"
        case .sand: "Sand"
        case .midnight: "Midnight"
        case .forest: "Forest"
        case .plum: "Plum"
        case .slate: "Slate"
        case .espresso: "Espresso"
        case .solar: "Solar"
        case .frost: "Frost"
        case .dawn: "Dawn"
        }
    }

    public enum Group: String, CaseIterable, Identifiable, Sendable {
        case classic, glass, colour

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .classic: "Classic"
            case .glass: "Glass"
            case .colour: "Colour"
            }
        }

        public var themes: [ThemeChoice] { ThemeChoice.allCases.filter { $0.group == self } }
    }

    public var group: Group {
        switch self {
        case .system, .paper, .graphite, .mono, .pureBlack, .highContrast: .classic
        case .glass, .glassDark, .clear, .aurora, .ocean, .dusk, .rose, .mint, .lavender, .ember, .citrus, .smoke: .glass
        case .sand, .midnight, .forest, .plum, .slate, .espresso, .solar, .frost, .dawn: .colour
        }
    }

    public enum Appearance: Sendable {
        case light, dark
        /// Light or dark with the iPhone.
        case followsPhone
    }

    public var appearance: Appearance {
        switch self {
        case .system, .mono, .highContrast, .clear: .followsPhone
        case .paper, .glass, .ocean, .rose, .mint, .lavender, .citrus, .sand, .slate, .solar, .dawn: .light
        case .graphite, .pureBlack, .glassDark, .aurora, .dusk, .ember, .smoke,
             .midnight, .forest, .plum, .espresso, .frost: .dark
        }
    }

    /// No colour anywhere: tiles, symbols and accents all draw in the ink.
    public var isMonochrome: Bool { self == .mono }

    /// Translucent surfaces over a soft coloured backdrop.
    public var isGlass: Bool { group == .glass }

    /// Text must reach AAA (7:1) rather than AA.
    public var isHighContrast: Bool { self == .highContrast }

    /// The colours in one appearance. A theme with a single appearance returns the same
    /// colours for both, so nothing can resolve to another theme's colour.
    public func tokens(dark: Bool) -> ThemeTokens {
        switch appearance {
        case .light: lightTokens
        case .dark: darkTokens
        case .followsPhone: dark ? darkTokens : lightTokens
        }
    }

    private var lightTokens: ThemeTokens {
        switch self {
        case .system, .paper, .graphite: .paper
        case .mono: .monoLight
        case .highContrast: .highContrastLight
        case .clear: .clearLight
        case .glass: .glassLight
        case .ocean: .ocean
        case .rose: .rose
        case .mint: .mint
        case .lavender: .lavender
        case .citrus: .citrus
        case .sand: .sand
        case .slate: .slate
        case .solar: .solar
        case .dawn: .dawn
        default: darkTokens
        }
    }

    private var darkTokens: ThemeTokens {
        switch self {
        case .system, .paper, .graphite: .graphite
        case .mono: .monoDark
        case .pureBlack: .pureBlack
        case .highContrast: .highContrastDark
        case .clear: .clearDark
        case .glassDark: .glassDark
        case .aurora: .aurora
        case .dusk: .dusk
        case .ember: .ember
        case .smoke: .smoke
        case .midnight: .midnight
        case .forest: .forest
        case .plum: .plum
        case .espresso: .espresso
        case .frost: .frost
        default: lightTokens
        }
    }
}

/// A glass theme's backdrop: large soft pools of colour on a base, drawn into a square tile.
/// Pools away from the diagonal are mirrored across it, so portrait and landscape crops of the
/// tile look alike.
public struct ThemeBackdrop: Hashable, Sendable {
    public struct Pool: Hashable, Sendable {
        /// Centre as a fraction of the tile, radius as a fraction of its side.
        public var x: Double, y: Double, radius: Double
        public var color: RGBA
    }

    public var base: RGBA
    public var pools: [Pool]

    /// Opacity at a pool's centre.
    public static let peak = 0.85

    /// `pools` are (x, y, radius, colour); each one off the diagonal also gets its mirror.
    init(base: UInt32, _ pools: [(Double, Double, Double, UInt32)]) {
        self.base = RGBA(hex: base)
        self.pools = pools.flatMap { x, y, r, c -> [Pool] in
            let pool = Pool(x: x, y: y, radius: r, color: RGBA(hex: c))
            return x == y ? [pool] : [pool, Pool(x: y, y: x, radius: r, color: RGBA(hex: c))]
        }
    }

    /// The shared arrangement: one large pool in the corner, one across the middle, a pair
    /// down the sides and a pair at the far edges.
    init(base: UInt32, corner: UInt32, middle: UInt32, side: UInt32, edge: UInt32) {
        self.init(base: base, [
            (0.05, 0.05, 0.55, corner),
            (0.36, 0.36, 0.42, middle),
            (0.12, 0.64, 0.42, side),
            (0.0, 0.94, 0.38, edge),
        ])
    }

    /// Plain colours standing for every part of the backdrop: the base and each pool at full
    /// strength. Anything drawn over the backdrop must read on all of them.
    public var samples: [RGBA] {
        [base] + pools.map(\.color)
    }
}

/// One theme's colours in one appearance.
public struct ThemeTokens: Hashable, Sendable {
    public var isDark: Bool
    /// The surface. In the glass themes it is the backdrop's base and `backdrop` is drawn over it.
    public var background: RGBA
    public var backdrop: ThemeBackdrop?
    /// Cards and buttons on the surface; translucent in the glass themes.
    public var raised: RGBA
    public var raisedPressed: RGBA
    public var line: RGBA
    public var ink: RGBA
    public var inkSoft: RGBA
    /// The finger dot before the user's opacity setting.
    public var dot: RGBA
    /// A plain colour matching the surface, for text on an ink filled button.
    public var solid: RGBA
    /// The theme's own colour: controls, switches and links.
    public var accent: RGBA

    /// Plain colours for every part of the surface.
    public var surfaces: [RGBA] { backdrop?.samples ?? [background] }

    /// Raised cards as they look over every part of the surface.
    public var raisedSurfaces: [RGBA] { surfaces.map { raised.over($0) } }

    /// Everything text and symbols are drawn on.
    public var allSurfaces: [RGBA] { surfaces + raisedSurfaces }

    /// A colour (a mode's accent, a status) made readable for UI on this theme: moved toward
    /// the ink only as far as 3:1 on every surface needs.
    public func readable(_ color: RGBA, minimum: Double = ContrastLevel.ui.rawValue) -> RGBA {
        color.readable(on: allSurfaces, toward: ink, minimum: minimum)
    }

    /// Connected, passed, done.
    public var good: RGBA { readable(SystemHue.green.value(dark: isDark)) }
    /// Waiting or needs a look.
    public var caution: RGBA { readable(SystemHue.orange.value(dark: isDark)) }
    /// Failed or recording.
    public var bad: RGBA { readable(SystemHue.red.value(dark: isDark)) }
}

/// Apple's system colours, for checking the mode accents and status colours on every theme.
public enum SystemHue: CaseIterable, Sendable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray

    public func value(dark: Bool) -> RGBA {
        let pair: (UInt32, UInt32) = switch self {
        case .red: (0xFF3B30, 0xFF453A)
        case .orange: (0xFF9500, 0xFF9F0A)
        case .yellow: (0xFFCC00, 0xFFD60A)
        case .green: (0x34C759, 0x30D158)
        case .mint: (0x00C7BE, 0x63E6E2)
        case .teal: (0x30B0C7, 0x40C8E0)
        case .cyan: (0x32ADE6, 0x64D2FF)
        case .blue: (0x007AFF, 0x0A84FF)
        case .indigo: (0x5856D6, 0x5E5CE6)
        case .purple: (0xAF52DE, 0xBF5AF2)
        case .pink: (0xFF2D55, 0xFF375F)
        case .brown: (0xA2845E, 0xAC8E68)
        case .gray: (0x8E8E93, 0x8E8E93)
        }
        return RGBA(hex: dark ? pair.1 : pair.0)
    }
}

// MARK: - The colours

extension ThemeTokens {
    /// A flat theme: opaque surface and cards. Lines, secondary text and dots are the ink
    /// at lower opacity.
    static func flat(dark: Bool, background: UInt32, raised: UInt32, pressed: UInt32, ink: UInt32, accent: UInt32,
                     soft: Double, line: Double? = nil, dot: Double? = nil, lineColor: UInt32? = nil, dotColor: UInt32? = nil) -> ThemeTokens {
        let i = RGBA(hex: ink)
        return ThemeTokens(isDark: dark, background: RGBA(hex: background), backdrop: nil, raised: RGBA(hex: raised),
                           raisedPressed: RGBA(hex: pressed),
                           line: RGBA(hex: lineColor ?? ink, alpha: line ?? (dark ? 0.1 : 0.08)),
                           ink: i, inkSoft: i.alpha(soft),
                           dot: RGBA(hex: dotColor ?? ink, alpha: dot ?? (dark ? 0.2 : 0.14)),
                           solid: RGBA(hex: background), accent: RGBA(hex: accent))
    }

    /// A glass theme: frosted, translucent cards over a backdrop.
    static func glass(dark: Bool, _ backdrop: ThemeBackdrop, solid: UInt32, ink: UInt32, accent: UInt32, soft: Double,
                      raised: Double? = nil, pressed: Double? = nil, line: Double? = nil) -> ThemeTokens {
        let i = RGBA(hex: ink)
        return ThemeTokens(isDark: dark, background: backdrop.base, backdrop: backdrop,
                           raised: RGBA(white: 1, alpha: raised ?? (dark ? 0.085 : 0.52)),
                           raisedPressed: RGBA(white: 1, alpha: pressed ?? (dark ? 0.16 : 0.3)),
                           line: RGBA(white: 1, alpha: line ?? (dark ? 0.12 : 0.7)),
                           ink: i, inkSoft: i.alpha(soft),
                           dot: dark ? RGBA(white: 1, alpha: 0.2) : i.alpha(0.14),
                           solid: RGBA(hex: solid), accent: RGBA(hex: accent))
    }

    // Classic

    static let paper = flat(dark: false, background: 0xF2F1EE, raised: 0xFBFAF8, pressed: 0xE6E4DF,
                            ink: 0x1A1A1A, accent: 0x1A1A1A, soft: 0.66)
    static let graphite = flat(dark: true, background: 0x141414, raised: 0x1F1F1F, pressed: 0x2C2C2C,
                               ink: 0xF2F1EE, accent: 0xF2F1EE, soft: 0.6, dot: 0.18, lineColor: 0xFFFFFF, dotColor: 0xFFFFFF)
    static let monoLight = flat(dark: false, background: 0xFFFFFF, raised: 0xF4F4F4, pressed: 0xE4E4E4,
                                ink: 0x000000, accent: 0x000000, soft: 0.6, line: 0.1)
    static let monoDark = flat(dark: true, background: 0x000000, raised: 0x141414, pressed: 0x262626,
                               ink: 0xFFFFFF, accent: 0xFFFFFF, soft: 0.6, line: 0.14)
    /// True black, so an OLED screen leaves most pixels off.
    static let pureBlack = flat(dark: true, background: 0x000000, raised: 0x101010, pressed: 0x1E1E1E,
                                ink: 0xF5F5F7, accent: 0xF5F5F7, soft: 0.62, line: 0.12, dot: 0.18)
    /// Text at 7:1 or more everywhere, with firm edges on every card.
    static let highContrastLight = flat(dark: false, background: 0xFFFFFF, raised: 0xF0F0F2, pressed: 0xDCDCE0,
                                        ink: 0x000000, accent: 0x0040DD, soft: 0.8, line: 0.45, dot: 0.22)
    static let highContrastDark = flat(dark: true, background: 0x000000, raised: 0x1C1C1E, pressed: 0x323236,
                                       ink: 0xFFFFFF, accent: 0x6CB4FF, soft: 0.84, line: 0.5, dot: 0.26)

    // Glass

    static let glassLight = glass(dark: false, ThemeBackdrop(base: 0xEDEFF6, [
        (0.05, 0.05, 0.55, 0xB9CFFF), (0.36, 0.36, 0.42, 0xE3D3FF), (0.12, 0.62, 0.42, 0xFFDCCB), (0.0, 0.92, 0.4, 0xC6EBE4),
    ]), solid: 0xEEF0F7, ink: 0x11141C, accent: 0x11141C, soft: 0.68)
    static let glassDark = glass(dark: true, ThemeBackdrop(base: 0x0B0D16, [
        (0.05, 0.05, 0.55, 0x2B3A8C), (0.36, 0.36, 0.4, 0x4A2A78), (0.12, 0.66, 0.42, 0x0E5560), (0.0, 0.95, 0.36, 0x5A2050),
    ]), solid: 0x10121C, ink: 0xF3F4F9, accent: 0xF3F4F9, soft: 0.8)
    /// As much see-through as legibility allows, like the clear icons on the Home Screen.
    static let clearLight = glass(dark: false, ThemeBackdrop(base: 0xE4E9EF, corner: 0xC9D6E6, middle: 0xE2DCEB,
                                                             side: 0xD6E6E1, edge: 0xE9E1D8),
                                  solid: 0xE6EBF1, ink: 0x0B0D12, accent: 0x0B0D12, soft: 0.68, raised: 0.24, pressed: 0.42, line: 0.9)
    static let clearDark = glass(dark: true, ThemeBackdrop(base: 0x08090C, corner: 0x1C2431, middle: 0x231E2E,
                                                           side: 0x15262A, edge: 0x2A221E),
                                 solid: 0x0C0D11, ink: 0xF5F6F8, accent: 0xF5F6F8, soft: 0.66, raised: 0.05, pressed: 0.12, line: 0.24)
    static let aurora = glass(dark: true, ThemeBackdrop(base: 0x050C12, corner: 0x0F4A3C, middle: 0x261E56,
                                                        side: 0x0A3E4F, edge: 0x185A40),
                              solid: 0x08131A, ink: 0xEEF7F4, accent: 0x8CF0CB, soft: 0.8)
    static let ocean = glass(dark: false, ThemeBackdrop(base: 0xE4EEF6, corner: 0xA8D2F4, middle: 0xC6DBFF,
                                                        side: 0xA6E4E0, edge: 0xD2EEF0),
                             solid: 0xE6F0F7, ink: 0x0A1A28, accent: 0x0B5F9E, soft: 0.68)
    static let dusk = glass(dark: true, ThemeBackdrop(base: 0x120B1A, corner: 0x42205A, middle: 0x662748,
                                                      side: 0x733424, edge: 0x26245E),
                            solid: 0x170F20, ink: 0xF8F0F2, accent: 0xFFC499, soft: 0.8)
    static let rose = glass(dark: false, ThemeBackdrop(base: 0xF7ECEE, corner: 0xFFC9D5, middle: 0xF2CDE8,
                                                       side: 0xFFDCCB, edge: 0xFBE6DA),
                            solid: 0xF8EEF0, ink: 0x2A1219, accent: 0xB02D5E, soft: 0.68)
    static let mint = glass(dark: false, ThemeBackdrop(base: 0xE8F4EE, corner: 0xB6EAD2, middle: 0xCBEFC4,
                                                       side: 0xB4E2E8, edge: 0xE2F2D4),
                            solid: 0xEAF5EF, ink: 0x0D231A, accent: 0x0D7351, soft: 0.68)
    static let lavender = glass(dark: false, ThemeBackdrop(base: 0xEFEDF8, corner: 0xD4CBFF, middle: 0xEACBF4,
                                                           side: 0xC8D5FF, edge: 0xE2E6FF),
                                solid: 0xF0EEF8, ink: 0x19142E, accent: 0x5B3FC4, soft: 0.68)
    static let ember = glass(dark: true, ThemeBackdrop(base: 0x130705, corner: 0x66200F, middle: 0x561724,
                                                       side: 0x6E3E0D, edge: 0x3E130B),
                             solid: 0x170A07, ink: 0xFBF1EA, accent: 0xFFC89C, soft: 0.8)
    static let citrus = glass(dark: false, ThemeBackdrop(base: 0xF6F3E3, corner: 0xFFEC9E, middle: 0xFFD9B8,
                                                         side: 0xDDF0AE, edge: 0xFFE7C2),
                              solid: 0xF7F4E6, ink: 0x221D0E, accent: 0x7A5200, soft: 0.68)
    static let smoke = glass(dark: true, ThemeBackdrop(base: 0x0D0E10, corner: 0x2E3138, middle: 0x3A3C42,
                                                       side: 0x23272D, edge: 0x34363B),
                             solid: 0x111214, ink: 0xF2F3F5, accent: 0xF2F3F5, soft: 0.72)

    // Colour

    static let sand = flat(dark: false, background: 0xECE4D6, raised: 0xF7F2E9, pressed: 0xDFD4C2,
                           ink: 0x2E261D, accent: 0x8A4B22, soft: 0.68, line: 0.1, dot: 0.16, lineColor: 0x3B2F22, dotColor: 0x3B2F22)
    static let midnight = flat(dark: true, background: 0x0B111D, raised: 0x151D2D, pressed: 0x1F2A3F,
                               ink: 0xE8EDF7, accent: 0x8FB2FF, soft: 0.62, line: 0.13, dot: 0.2, lineColor: 0xA9BCE6, dotColor: 0xC4D3F5)
    static let forest = flat(dark: true, background: 0x0E1812, raised: 0x17241C, pressed: 0x213126,
                             ink: 0xE6F0E8, accent: 0x86D19C, soft: 0.62, line: 0.12, lineColor: 0xCFE8D6)
    static let plum = flat(dark: true, background: 0x190F1F, raised: 0x24172E, pressed: 0x32213D,
                           ink: 0xF4EAF7, accent: 0xD9A3F2, soft: 0.62, line: 0.12, lineColor: 0xE8CDF2)
    static let slate = flat(dark: false, background: 0xE3E7EC, raised: 0xF3F5F8, pressed: 0xD3D9E0,
                            ink: 0x1B2430, accent: 0x34608F, soft: 0.68, line: 0.1)
    static let espresso = flat(dark: true, background: 0x19120F, raised: 0x251B16, pressed: 0x33261F,
                               ink: 0xF4EAE2, accent: 0xDDA672, soft: 0.62, line: 0.12, lineColor: 0xF0D9C6)
    static let solar = flat(dark: false, background: 0xFBF2DE, raised: 0xFFFAEE, pressed: 0xEFE3C8,
                            ink: 0x23343B, accent: 0xB04A12, soft: 0.7, line: 0.1)
    static let frost = flat(dark: true, background: 0x2E3440, raised: 0x3B4252, pressed: 0x454E61,
                            ink: 0xECEFF4, accent: 0x88C0D0, soft: 0.74, line: 0.12, dot: 0.22)
    static let dawn = flat(dark: false, background: 0xFAF4ED, raised: 0xFFFAF3, pressed: 0xF0E7DD,
                           ink: 0x4A4569, accent: 0x7A5C9E, soft: 0.8, line: 0.1)
}
