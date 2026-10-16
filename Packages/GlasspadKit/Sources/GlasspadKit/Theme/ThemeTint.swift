import Foundation

/// The one colour a tinted theme is made of. Every colour in the theme (the surface, cards,
/// text, accents, mode colours and app icons) is this hue at some lightness, the way the
/// tinted Home Screen on iOS shows everything in one colour.
public struct ThemeTint: Hashable, Sendable {
    /// Hue, 0...1 around the colour wheel.
    public var hue: Double
    /// How colourful the theme is, 0 (grey) ... 1.
    public var saturation: Double

    public init(hue: Double, saturation: Double) {
        self.hue = hue - floor(hue)
        self.saturation = min(1, max(0, saturation))
    }

    /// The hue and saturation of any colour (HSL).
    public init(_ color: RGBA) {
        let hi = max(color.r, color.g, color.b), lo = min(color.r, color.g, color.b), d = hi - lo
        let l = (hi + lo) / 2
        guard d > 0.0001 else {
            self.init(hue: 0, saturation: 0)
            return
        }
        let s = d / (1 - abs(2 * l - 1))
        var h: Double
        if hi == color.r {
            h = (color.g - color.b) / d
        } else if hi == color.g {
            h = (color.b - color.r) / d + 2
        } else {
            h = (color.r - color.g) / d + 4
        }
        h /= 6
        self.init(hue: h < 0 ? h + 1 : h, saturation: s)
    }

    /// The Custom Tint theme's colour, which the person picks. Set by the app when it loads
    /// the setting and whenever it changes.
    public static var custom: ThemeTint {
        get { customBox.lock.withLock { customBox.value } }
        set { customBox.lock.withLock { customBox.value = newValue } }
    }

    /// Custom Tint before the person picks a colour: a calm teal.
    public static let defaultCustom = ThemeTint(RGBA(hex: 0x2A8C8C))

    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var value = ThemeTint.defaultCustom
    }

    private static let customBox = Box()

    /// The colour as `0xRRGGBB` at the lightness that shows it best, for saving and pickers.
    public var hex: UInt32 { color(luminance: 0.2, saturation: saturation).hex }

    // MARK: Colours along the hue

    /// This hue at the HSL lightness that gives `luminance` (WCAG), with `saturation`.
    public func color(luminance target: Double, saturation s: Double) -> RGBA {
        let target = min(1, max(0, target))
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if Self.hsl(hue, min(1, max(0, s)), mid).luminance < target { lo = mid } else { hi = mid }
        }
        return Self.hsl(hue, min(1, max(0, s)), (lo + hi) / 2)
    }

    /// Any colour moved onto this hue, keeping its luminance: what a mode's colour or a
    /// tile's colour becomes in a tinted theme.
    public func mapped(_ c: RGBA) -> RGBA {
        color(luminance: c.luminance, saturation: saturation).alpha(c.a)
    }

    static func hsl(_ h: Double, _ s: Double, _ l: Double) -> RGBA {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h * 6
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) = switch hp {
        case ..<1: (c, x, 0)
        case ..<2: (x, c, 0)
        case ..<3: (0, c, x)
        case ..<4: (0, x, c)
        case ..<5: (x, 0, c)
        default: (c, 0, x)
        }
        let m = l - c / 2
        return RGBA(r: min(1, max(0, r + m)), g: min(1, max(0, g + m)), b: min(1, max(0, b + m)))
    }

    // MARK: The theme

    /// The theme in one appearance. Light: a pale wash of the hue with cards lighter still,
    /// text in its deepest shade and the accent at full colour. Dark: the hue's deepest shades
    /// with text in a pale tint.
    public func tokens(dark: Bool) -> ThemeTokens {
        let s = saturation
        func c(_ luminance: Double, _ share: Double) -> RGBA { color(luminance: luminance, saturation: s * share) }
        let background = dark ? c(0.0105, 0.55) : c(0.8, 0.5)
        let ink = dark ? c(0.8, 0.42) : c(0.024, 0.75)
        return ThemeTokens(isDark: dark, background: background, backdrop: nil,
                           raised: dark ? c(0.026, 0.5) : c(0.93, 0.55),
                           raisedPressed: dark ? c(0.048, 0.5) : c(0.68, 0.5),
                           line: ink.alpha(dark ? 0.13 : 0.1),
                           ink: ink, inkSoft: ink.alpha(dark ? 0.66 : 0.72),
                           dot: ink.alpha(dark ? 0.2 : 0.16),
                           solid: background, accent: dark ? c(0.36, 1) : c(0.115, 1), tint: self)
    }

    // MARK: Icons

    /// Steps in `iconRamp`.
    public static let rampSteps = 256

    /// What app icons and website logos are drawn in: the icon's own brightness (0 black ...
    /// 1 white) looked up along this ramp, from a deep shade of the hue to a pale tint. Dark
    /// themes stop well short of white so icons do not glare. The steps are even in perceived
    /// brightness, so an icon keeps all its detail.
    public func iconRamp(dark: Bool) -> [RGBA] {
        (0..<Self.rampSteps).map { iconColor(at: Double($0) / Double(Self.rampSteps - 1), dark: dark) }
    }

    /// One step of `iconRamp`: `t` 0 for an icon's black, 1 for its white.
    public func iconColor(at t: Double, dark: Bool) -> RGBA {
        let (shadow, highlight) = dark ? (0.008, 0.45) : (0.018, 0.9)
        func gamma(_ l: Double) -> Double { pow(l, 1 / 2.2) }
        let l = pow(gamma(shadow) + (gamma(highlight) - gamma(shadow)) * t, 2.2)
        // Most colourful in the middle, calmer at the ends.
        return color(luminance: l, saturation: saturation * (0.55 + 0.4 * sin(.pi * t)))
    }

    /// Mono's icons: plain grey, black to white.
    public static let grayRamp: [RGBA] = (0..<rampSteps).map { RGBA(white: Double($0) / Double(rampSteps - 1)) }
}

extension RGBA {
    /// `0xRRGGBB`, rounded.
    public var hex: UInt32 {
        func ch(_ v: Double) -> UInt32 { UInt32((min(1, max(0, v)) * 255).rounded()) }
        return ch(r) << 16 | ch(g) << 8 | ch(b)
    }
}
