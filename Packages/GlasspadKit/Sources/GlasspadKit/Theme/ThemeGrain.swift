import Foundation

/// A fine, still grain over a theme's surface, like good paper or film. The noise is made
/// once from a fixed seed and drawn as a small repeating tile at the screen's own pixel
/// density, so it is crisp, identical on every launch and costs nothing after the first draw.
public struct ThemeGrain: Hashable, Sendable {
    /// How far the grain moves a pixel's brightness either way at most (0...1 of full scale).
    public var amount: Double

    public init(amount: Double) {
        self.amount = amount
    }

    /// The surface colour where the grain value is `n` (0...1, 0.5 leaves it as it is). Linear
    /// light: the same lift or dip on every channel, so the grain has no colour of its own and
    /// shows evenly on light and dark surfaces.
    public func apply(_ n: Double, to color: RGBA) -> RGBA {
        let d = (n - 0.5) * 2 * amount
        func ch(_ v: Double) -> Double { min(1, max(0, v + d)) }
        return RGBA(r: ch(color.r), g: ch(color.g), b: ch(color.b), a: color.a)
    }

    /// The surface at the grain's darkest and lightest and as it is: anything drawn on the
    /// surface must read on all three.
    public func samples(of color: RGBA) -> [RGBA] {
        [apply(0, to: color), color, apply(1, to: color)]
    }

    /// Side of the tile, in pixels.
    public static let side = 256

    /// The grain values for a tile `side` pixels square, 0...1 with 0.5 the middle, row by row.
    /// `pixelsPerGrain` is how many screen pixels one grain spans (the screen's scale divided by
    /// two, so a grain is about half a point on any screen). Neighbouring pixels are blended by
    /// that much, wrapping at the edges so the tile repeats without a seam.
    public static func noise(side: Int = side, pixelsPerGrain: Double, seed: UInt64 = 0x6772_6169_6E21) -> [Double] {
        var state = seed
        func next() -> Double {
            // SplitMix64: small, fast and the same everywhere.
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
        let count = side * side
        // Three uniform draws averaged: a soft bell, so most pixels move a little and few a lot.
        let raw = (0..<count).map { _ in (next() + next() + next()) / 3 }
        let spread = min(1, max(0, pixelsPerGrain - 1))
        guard spread > 0 else { return stretched(raw) }
        // Blend each pixel with its eight neighbours, weighted by `spread`.
        var out = [Double](repeating: 0, count: count)
        for y in 0..<side {
            for x in 0..<side {
                var around = 0.0
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        around += raw[((y + dy + side) % side) * side + (x + dx + side) % side]
                    }
                }
                out[y * side + x] = raw[y * side + x] * (1 - spread * 0.6) + around / 8 * spread * 0.6
            }
        }
        return stretched(out)
    }

    /// Centres the values on 0.5 and scales them so the strongest grain reaches 0 or 1: the
    /// tile then shows exactly `amount` at most, whatever the blending did to the spread.
    static func stretched(_ values: [Double]) -> [Double] {
        let mean = values.reduce(0, +) / Double(max(1, values.count))
        let reach = values.map { abs($0 - mean) }.max() ?? 0
        guard reach > 0 else { return values.map { _ in 0.5 } }
        return values.map { 0.5 + ($0 - mean) / reach / 2 }
    }
}
