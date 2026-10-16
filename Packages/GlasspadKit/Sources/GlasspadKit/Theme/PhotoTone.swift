import Foundation

/// How the Photo theme sits on a picked photo: whether the photo reads as light or dark, and
/// how strong a veil (white over a light photo, black over a dark one) it needs so text reads
/// everywhere on it. Worked out from colours sampled across the blurred photo.
public struct PhotoTone: Hashable, Sendable {
    public var isDark: Bool
    /// Opacity of the veil drawn over the photo, 0...0.9.
    public var veil: Double
    /// The sampled colours with the veil applied.
    public var samples: [RGBA]

    /// The veil colour for this tone.
    public var veilColor: RGBA { isDark ? .black : .white }

    /// The tone needing the lightest veil for the theme's colours to pass every contrast check.
    /// A photo that is mostly dark gets light text, a mostly light one dark text; when both
    /// work equally well, the one closer to the photo's own brightness wins.
    public static func fit(samples raw: [RGBA]) -> PhotoTone {
        let samples = raw.isEmpty ? [RGBA(white: 0.5)] : raw.map { $0.alpha(1) }
        func tone(dark: Bool) -> PhotoTone {
            var veil = 0.0
            while true {
                let veiled = samples.map { (dark ? RGBA.black : RGBA.white).alpha(veil).over($0) }
                let t = PhotoTone(isDark: dark, veil: veil, samples: veiled)
                if t.tokens.meetsContrast() || veil >= 0.9 { return t }
                veil = min(0.9, veil + 0.02)
            }
        }
        let dark = tone(dark: true), light = tone(dark: false)
        if abs(dark.veil - light.veil) < 0.001 {
            let mean = samples.map(\.luminance).reduce(0, +) / Double(samples.count)
            return mean < 0.4 ? dark : light
        }
        return dark.veil < light.veil ? dark : light
    }

    /// The theme's colours on this photo: frosted cards like the glass themes, the ink, a plain
    /// stand-in for the surface (the photo's average colour) and an accent taken from the
    /// photo's most colourful part, made readable.
    public var tokens: ThemeTokens {
        let ink = isDark ? RGBA(hex: 0xF5F6F8) : RGBA(hex: 0x101216)
        let average = Self.average(samples)
        var t = ThemeTokens(isDark: isDark, background: average, backdrop: nil,
                            raised: RGBA(white: 1, alpha: isDark ? 0.085 : 0.52),
                            raisedPressed: RGBA(white: 1, alpha: isDark ? 0.16 : 0.3),
                            line: RGBA(white: 1, alpha: isDark ? 0.12 : 0.7),
                            ink: ink, inkSoft: ink.alpha(0.8),
                            dot: isDark ? RGBA(white: 1, alpha: 0.2) : ink.alpha(0.14),
                            solid: average, accent: ink, photoSamples: samples)
        // Text on an ink filled button: the photo's average, or plain white or black when the
        // average sits too close to the ink.
        if t.solid.contrast(with: ink) < ContrastLevel.text.rawValue { t.solid = isDark ? RGBA(hex: 0x101216) : .white }
        if let vivid = samples.max(by: { $0.saturation < $1.saturation }), vivid.saturation > 0.25 {
            let accent = vivid.mixed(with: ink, amount: 0.15).readable(on: t.raisedSurfaces + t.surfaces, toward: ink,
                                                                       minimum: ContrastLevel.text.rawValue)
            if accent.worstContrast(on: t.raisedSurfaces) >= ContrastLevel.text.rawValue { t.accent = accent }
        }
        return t
    }

    static func average(_ colors: [RGBA]) -> RGBA {
        let n = Double(max(1, colors.count))
        return RGBA(r: colors.map(\.r).reduce(0, +) / n, g: colors.map(\.g).reduce(0, +) / n, b: colors.map(\.b).reduce(0, +) / n)
    }
}

extension RGBA {
    /// HSB saturation, 0...1.
    var saturation: Double {
        let hi = max(r, g, b), lo = min(r, g, b)
        return hi == 0 ? 0 : (hi - lo) / hi
    }
}
