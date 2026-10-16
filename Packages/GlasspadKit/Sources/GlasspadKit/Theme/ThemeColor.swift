import Foundation

/// A colour as plain numbers (sRGB, 0...1), so the themes can be checked for contrast without
/// UIKit. The phone turns these into `UIColor`s.
public struct RGBA: Hashable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// `0xRRGGBB`.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255,
                  b: Double(hex & 0xFF) / 255, a: alpha)
    }

    public init(white: Double, alpha: Double = 1) {
        self.init(r: white, g: white, b: white, a: alpha)
    }

    public static let white = RGBA(white: 1)
    public static let black = RGBA(white: 0)

    /// The same colour at another opacity.
    public func alpha(_ alpha: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: alpha) }

    /// This colour drawn over `base` (normal blending). Opaque when `base` is.
    public func over(_ base: RGBA) -> RGBA {
        let outA = a + base.a * (1 - a)
        guard outA > 0 else { return RGBA(r: 0, g: 0, b: 0, a: 0) }
        func ch(_ top: Double, _ bottom: Double) -> Double { (top * a + bottom * base.a * (1 - a)) / outA }
        return RGBA(r: ch(r, base.r), g: ch(g, base.g), b: ch(b, base.b), a: outA)
    }

    /// This colour moved `amount` (0...1) of the way to `other`, keeping this opacity.
    public func mixed(with other: RGBA, amount: Double) -> RGBA {
        let t = min(1, max(0, amount))
        return RGBA(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t, a: a)
    }

    /// Relative luminance as WCAG 2 defines it (opacity ignored).
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// WCAG contrast ratio between two opaque colours, 1...21.
    public func contrast(with other: RGBA) -> Double {
        let l1 = luminance, l2 = other.luminance
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// The lowest contrast of this colour (drawn over each surface) against those surfaces.
    public func worstContrast(on surfaces: [RGBA]) -> Double {
        surfaces.map { over($0).contrast(with: $0) }.min() ?? 21
    }

    /// This colour, moved toward `ink` only as far as needed to reach `minimum` contrast on
    /// every surface. A colour that already reads is returned as it is, so a theme keeps the
    /// system's own hues wherever they work.
    public func readable(on surfaces: [RGBA], toward ink: RGBA, minimum: Double) -> RGBA {
        var step = 0.0
        var c = self
        while c.worstContrast(on: surfaces) < minimum && step < 1 {
            step = min(1, step + 0.04)
            c = mixed(with: ink, amount: step)
        }
        return c
    }
}

/// The level a pair of colours must reach (WCAG 2).
public enum ContrastLevel: Double, Sendable {
    /// Body text, AA.
    case text = 4.5
    /// Large text, symbols and controls, AA.
    case ui = 3
    /// Body text, AAA.
    case enhanced = 7
}
