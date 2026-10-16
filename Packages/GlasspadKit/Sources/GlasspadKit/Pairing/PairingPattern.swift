import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// The pairing code drawn as a living pattern: a real QR code whose dark modules are soft
/// round dots that drift and shimmer, and that can gather into a checkmark when pairing
/// finishes. The Mac draws it on screen and the iPhone draws it over the camera once it has
/// read the code, so both use this one description of where every dot is at any moment.
///
/// Geometry is in module units: the code is `size` modules wide, (0, 0) is its top left
/// corner and y grows downwards. The three finder squares stay solid (rounded, but exactly
/// where a reader looks for them); every other dark module is a dot that never strays more
/// than a small fraction of a module from its cell, so the code stays readable while it moves.
public struct PairingPattern: Sendable, Equatable {
    /// Modules per side.
    public let size: Int
    /// Row-major, true for a dark module.
    public let modules: [Bool]
    /// The data dots (every dark module outside the finder squares).
    public let dots: [Dot]

    /// One dark module drawn as a dot.
    public struct Dot: Sendable, Equatable {
        /// The center of its cell, in modules.
        public let home: CGPoint
        /// Random but fixed per dot, so the motion looks organic and every frame is repeatable.
        public let seed: SIMD4<Double>
        /// Where it lands in the checkmark when pairing finishes, in modules; nil fades away.
        public let target: CGPoint?
    }

    /// A dot as drawn at one moment.
    public struct DrawnDot: Sendable, Equatable {
        public var center: CGPoint
        public var radius: CGFloat
        /// 0...1, multiplied with the ink.
        public var alpha: CGFloat
        /// 0 is the ink, 1 the success color.
        public var success: CGFloat
    }

    /// The radius of a dot at rest, in modules. Large enough to read as the module it is.
    public static let dotRadius: CGFloat = 0.43
    /// How far a dot may wander from its cell, in modules.
    public static let drift: CGFloat = 0.07
    /// How long the dots take to gather into the checkmark, in seconds.
    public static let gatherDuration: Double = 1.25

    /// Makes the pattern for `message`. Nil only if Core Image cannot make a QR code from it.
    public init?(message: String) {
        guard let matrix = Self.matrix(for: message) else { return nil }
        self.init(size: matrix.size, modules: matrix.modules)
    }

    init(size: Int, modules: [Bool]) {
        self.size = size
        self.modules = modules
        dots = Self.makeDots(size: size, modules: modules)
    }

    public func isDark(row: Int, column: Int) -> Bool {
        guard row >= 0, column >= 0, row < size, column < size else { return false }
        return modules[row * size + column]
    }

    /// The top left corners (in modules) of the three 7 by 7 finder squares.
    public var finders: [CGPoint] {
        let far = CGFloat(size - 7)
        return [CGPoint(x: 0, y: 0), CGPoint(x: far, y: 0), CGPoint(x: 0, y: far)]
    }

    static func inFinder(row: Int, column: Int, size: Int) -> Bool {
        let nearTop = row < 7, nearLeft = column < 7
        let nearBottom = row >= size - 7, nearRight = column >= size - 7
        return (nearTop && nearLeft) || (nearTop && nearRight) || (nearBottom && nearLeft)
    }

    // MARK: Motion

    /// Every dot at time `t` (seconds). `motion` scales drift and shimmer (0 when Reduce Motion
    /// is on, so the dots stand still). `gather` is 0 while the code is up and runs to 1 as the
    /// dots fly into the checkmark.
    public func frame(time t: Double, motion: Double = 1, gather: Double = 0) -> [DrawnDot] {
        let g = min(1, max(0, gather))
        let n = Double(size)
        // A slow band of light that sweeps across the code from corner to corner.
        let sweep = (t * 0.16).truncatingRemainder(dividingBy: 1) * 2.6 - 0.8
        return dots.map { dot in
            let s = dot.seed
            let tau = 2 * Double.pi
            let dx = sin(t * (0.55 + 0.35 * s.x) + s.y * tau)
            let dy = cos(t * (0.45 + 0.35 * s.z) + s.w * tau)
            let drift = Double(Self.drift) * motion
            var center = CGPoint(x: dot.home.x + CGFloat(dx * drift), y: dot.home.y + CGFloat(dy * drift))

            let twinkle = 0.5 + 0.5 * sin(t * (1.1 + 0.9 * s.w) + s.x * tau)
            let u = (Double(dot.home.x) + Double(dot.home.y)) / (2 * n)
            let band = exp(-pow((u - sweep) / 0.09, 2))
            let shimmer = motion * (0.6 * twinkle + 0.4 * band)
            var alpha = 0.8 + 0.2 * shimmer
            var radius = Double(Self.dotRadius) * (0.95 + 0.06 * shimmer)
            var success = 0.0

            if g > 0 {
                // Each dot leaves a little after its neighbours nearer the middle, so the cloud
                // flows inwards rather than jumping.
                let delay = 0.35 * s.z
                let q = Self.easeInOut(min(1, max(0, (g - delay) / (1 - delay))))
                if let target = dot.target {
                    let settle = Self.easeInOut(min(1, max(0, (g - 0.55) / 0.45)))
                    let wobble = drift * (1 - q) + drift * 0.25 * settle * motion
                    let to = CGPoint(x: target.x + CGFloat(dx * wobble), y: target.y + CGFloat(dy * wobble))
                    center = CGPoint(x: center.x + (to.x - center.x) * CGFloat(q),
                                     y: center.y + (to.y - center.y) * CGFloat(q))
                    radius += (0.36 - radius) * q
                    alpha += (1 - alpha) * q
                    success = q
                } else {
                    // Drifts outward a touch while it fades.
                    let mid = n / 2
                    center = CGPoint(x: center.x + (center.x - mid) * CGFloat(0.12 * q),
                                     y: center.y + (center.y - mid) * CGFloat(0.12 * q))
                    alpha *= 1 - min(1, q * 1.4)
                    radius *= 1 - 0.5 * q
                }
            }
            return DrawnDot(center: center, radius: CGFloat(radius), alpha: CGFloat(alpha), success: CGFloat(success))
        }
    }

    /// How visible the finder squares are while gathering (they fade out first).
    public static func finderAlpha(gather: Double) -> CGFloat {
        CGFloat(1 - min(1, max(0, gather / 0.35)))
    }

    static func easeInOut(_ x: Double) -> Double {
        x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    // MARK: Drawing

    /// Draws the pattern into `rect` (a square) of a Core Graphics context whose origin is top
    /// left (flip a bottom-left context first). The Mac's view and the tests both draw with it.
    public func draw(in ctx: CGContext, rect: CGRect, time: Double, motion: Double = 1, gather: Double = 0,
                     ink: CGColor, success: CGColor? = nil) {
        let m = rect.width / CGFloat(size)
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let finderAlpha = Self.finderAlpha(gather: gather)
        if finderAlpha > 0 {
            ctx.setFillColor(ink.copy(alpha: ink.alpha * finderAlpha) ?? ink)
            for corner in finders {
                let origin = CGPoint(x: rect.minX + corner.x * m, y: rect.minY + corner.y * m)
                for path in Self.finderPaths(origin: origin, module: m) {
                    ctx.addPath(path)
                    ctx.fillPath(using: .evenOdd)
                }
            }
        }
        for dot in frame(time: time, motion: motion, gather: gather) where dot.alpha > 0.01 {
            let color = success.flatMap { Self.mix(ink, $0, dot.success) } ?? ink
            ctx.setFillColor(color.copy(alpha: color.alpha * dot.alpha) ?? color)
            let r = dot.radius * m
            ctx.fillEllipse(in: CGRect(x: rect.minX + dot.center.x * m - r, y: rect.minY + dot.center.y * m - r,
                                       width: r * 2, height: r * 2))
        }
    }

    /// A finder square as a rounded ring and a rounded center, both on the module grid.
    public static func finderPaths(origin: CGPoint, module m: CGFloat) -> [CGPath] {
        let outer = CGRect(x: origin.x, y: origin.y, width: 7 * m, height: 7 * m)
        let ring = CGMutablePath()
        ring.addRoundedRect(in: outer, cornerWidth: 2.1 * m, cornerHeight: 2.1 * m)
        ring.addRoundedRect(in: outer.insetBy(dx: m, dy: m), cornerWidth: 1.3 * m, cornerHeight: 1.3 * m)
        let center = CGPath(roundedRect: outer.insetBy(dx: 2 * m, dy: 2 * m), cornerWidth: 0.95 * m,
                            cornerHeight: 0.95 * m, transform: nil)
        return [ring, center]
    }

    static func mix(_ a: CGColor, _ b: CGColor, _ t: CGFloat) -> CGColor? {
        guard t > 0 else { return a }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ca = a.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              let cb = b.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              ca.count == 4, cb.count == 4 else { return a }
        let c = (0..<4).map { ca[$0] + (cb[$0] - ca[$0]) * t }
        return CGColor(colorSpace: space, components: c)
    }

    // MARK: Building

    /// The module matrix from Core Image's QR generator, without its quiet zone. Medium error
    /// correction keeps the modules large; the tests prove the rounding and motion still read.
    static func matrix(for message: String) -> (size: Int, modules: [Bool])? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(message.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage else { return nil }
        let w = Int(image.extent.width), h = Int(image.extent.height)
        guard w > 0, w == h else { return nil }
        var pixels = [UInt8](repeating: 255, count: w * h)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        pixels.withUnsafeMutableBytes { buffer in
            context.render(image, toBitmap: buffer.baseAddress!, rowBytes: w, bounds: image.extent,
                           format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
        }
        // The bitmap's first row is the image's top. Trim the white margin around the code.
        var minR = h, maxR = -1, minC = w, maxC = -1
        for r in 0..<h {
            for c in 0..<w where pixels[r * w + c] < 128 {
                minR = min(minR, r); maxR = max(maxR, r); minC = min(minC, c); maxC = max(maxC, c)
            }
        }
        let n = maxR - minR + 1
        guard n > 20, maxC - minC + 1 == n else { return nil }
        var modules = [Bool](repeating: false, count: n * n)
        for r in 0..<n {
            for c in 0..<n { modules[r * n + c] = pixels[(r + minR) * w + (c + minC)] < 128 }
        }
        return (n, modules)
    }

    /// The checkmark the dots gather into: a short stroke down and a long one up, centered.
    /// Points along it in modules, evenly spaced.
    static func checkmark(size: Int, count: Int) -> [CGPoint] {
        let n = CGFloat(size)
        let a = CGPoint(x: n * 0.27, y: n * 0.52)
        let b = CGPoint(x: n * 0.43, y: n * 0.68)
        let c = CGPoint(x: n * 0.74, y: n * 0.33)
        let l1 = hypot(b.x - a.x, b.y - a.y), l2 = hypot(c.x - b.x, c.y - b.y)
        let total = l1 + l2
        return (0..<count).map { i in
            let d = total * CGFloat(i) / CGFloat(max(1, count - 1))
            if d <= l1 {
                let f = d / l1
                return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
            }
            let f = (d - l1) / l2
            return CGPoint(x: b.x + (c.x - b.x) * f, y: b.y + (c.y - b.y) * f)
        }
    }

    /// Points around the ring that circles the checkmark, in modules, evenly spaced from the top.
    static func ring(size: Int, count: Int) -> [CGPoint] {
        let n = CGFloat(size), r = n * 0.42
        return (0..<count).map { i in
            let angle = -CGFloat.pi / 2 + 2 * .pi * CGFloat(i) / CGFloat(count)
            return CGPoint(x: n / 2 + r * cos(angle), y: n / 2 + r * sin(angle))
        }
    }

    private static func makeDots(size: Int, modules: [Bool]) -> [Dot] {
        var homes: [CGPoint] = []
        var seeds: [SIMD4<Double>] = []
        var rng = SplitMix(seed: UInt64(size) &* 0x9E37_79B9_7F4A_7C15)
        for r in 0..<size {
            for c in 0..<size where modules[r * size + c] && !inFinder(row: r, column: c, size: size) {
                homes.append(CGPoint(x: CGFloat(c) + 0.5, y: CGFloat(r) + 0.5))
                seeds.append(SIMD4(rng.unit(), rng.unit(), rng.unit(), rng.unit()))
            }
        }
        // Choose who lands where: the dots nearest the middle form the checkmark, a band of
        // dots near the ring's radius forms the ring, the rest fade. Inside each group the dots
        // keep their order (along the stroke, or around the circle), so nobody crosses the
        // whole code to get to its place.
        let n = CGFloat(size), mid = CGPoint(x: n / 2, y: n / 2)
        let byDistance = homes.indices.sorted {
            hypot(homes[$0].x - mid.x, homes[$0].y - mid.y) < hypot(homes[$1].x - mid.x, homes[$1].y - mid.y)
        }
        let checkCount = min(homes.count, max(24, size * 3))
        let ringCount = min(homes.count - checkCount, max(36, Int(2 * .pi * n * 0.42 / 0.95)))
        var targets = [CGPoint?](repeating: nil, count: homes.count)

        let checkIDs = Array(byDistance.prefix(checkCount))
        let checkPoints = checkmark(size: size, count: checkIDs.count)
        // Order the chosen dots left to right, which is how the stroke runs.
        for (i, id) in checkIDs.sorted(by: { homes[$0].x < homes[$1].x }).enumerated() { targets[id] = checkPoints[i] }

        let ringRadius = n * 0.42
        let ringIDs = byDistance.dropFirst(checkCount)
            .sorted { abs(hypot(homes[$0].x - mid.x, homes[$0].y - mid.y) - ringRadius)
                    < abs(hypot(homes[$1].x - mid.x, homes[$1].y - mid.y) - ringRadius) }
            .prefix(ringCount)
        let ringPoints = ring(size: size, count: ringIDs.count)
        func angle(_ p: CGPoint) -> CGFloat {
            var a = atan2(p.y - mid.y, p.x - mid.x) + .pi / 2
            if a < 0 { a += 2 * .pi }
            return a
        }
        for (i, id) in ringIDs.sorted(by: { angle(homes[$0]) < angle(homes[$1]) }).enumerated() {
            targets[id] = ringPoints[i]
        }
        return homes.indices.map { Dot(home: homes[$0], seed: seeds[$0], target: targets[$0]) }
    }
}

/// A tiny repeatable random source, so a code always moves the same way.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
