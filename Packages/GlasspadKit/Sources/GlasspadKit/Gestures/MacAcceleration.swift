import Foundation

/// One acceleration curve from the HID system (`HIDAccelCurves` / `HIDScrollAccelCurves` on the
/// trackpad's IORegistry entry). Values are the 16.16 fixed-point numbers divided by 65536.
public struct HIDAccelCurve: Equatable, Sendable {
    public var index: Double
    public var gainLinear: Double
    public var gainParabolic: Double
    public var gainCubic: Double
    public var gainQuartic: Double
    public var tangentSpeedLinear: Double
    public var tangentSpeedParabolicRoot: Double

    public init(index: Double, gainLinear: Double, gainParabolic: Double = 0, gainCubic: Double = 0,
                gainQuartic: Double = 0, tangentSpeedLinear: Double = 0, tangentSpeedParabolicRoot: Double = 0) {
        self.index = index
        self.gainLinear = gainLinear
        self.gainParabolic = gainParabolic
        self.gainCubic = gainCubic
        self.gainQuartic = gainQuartic
        self.tangentSpeedLinear = tangentSpeedLinear
        self.tangentSpeedParabolicRoot = tangentSpeedParabolicRoot
    }

    /// Builds a curve from the raw fixed-point integers as `ioreg` prints them.
    static func fixed(_ index: Int, linear: Int, parabolic: Int = 0, cubic: Int = 0, tangentLinear: Int,
                      tangentRoot: Int) -> HIDAccelCurve {
        let f = 65536.0
        return HIDAccelCurve(index: Double(index) / f, gainLinear: Double(linear) / f,
                             gainParabolic: Double(parabolic) / f, gainCubic: Double(cubic) / f,
                             tangentSpeedLinear: Double(tangentLinear) / f, tangentSpeedParabolicRoot: Double(tangentRoot) / f)
    }
}

/// The macOS parametric acceleration curve, re-implemented from Apple's open-source
/// IOHIDFamily (`IOHIDEventSystemPlugIns/IOHIDAccelerationAlgorithm.cpp`,
/// `IOHIDParametricAcceleration::CreateWithParameters` and `::multiplier`). Three segments:
/// a polynomial up to `tangentSpeedLinear`, its tangent line up to `tangentSpeedParabolicRoot`,
/// then a square root. The curve for a tracking speed between two table entries is a linear
/// blend of both. Apple's code raises the gain products to the power (for example
/// `pow(GainParabolic * x, 2)`), and that quirk is kept on purpose: it is what the Mac does.
public struct ParametricAcceleration: Equatable, Sendable {
    public private(set) var curve: HIDAccelCurve
    private var tangent: (Double, Double) = (.greatestFiniteMagnitude, .greatestFiniteMagnitude)
    private var m: (Double, Double) = (0, 0)
    private var b: (Double, Double) = (0, 0)

    public static func == (a: Self, b: Self) -> Bool { a.curve == b.curve }

    public init(curves: [HIDAccelCurve], index requested: Double) {
        let curves = curves.filter { $0.gainLinear != 0 || $0.gainParabolic != 0 || $0.gainCubic != 0 || $0.gainQuartic != 0 }
        guard !curves.isEmpty else {
            curve = HIDAccelCurve(index: 0, gainLinear: 1)
            return
        }
        let index = max(0, requested)
        var current = 0
        for (i, c) in curves.enumerated() where index >= c.index { current = i }
        let lo = curves[current]
        if lo.index < index, current + 1 < curves.count {
            let hi = curves[current + 1]
            let r = (index - lo.index) / (hi.index - lo.index)
            func mix(_ k: KeyPath<HIDAccelCurve, Double>) -> Double { lo[keyPath: k] + r * (hi[keyPath: k] - lo[keyPath: k]) }
            curve = HIDAccelCurve(index: mix(\.index), gainLinear: mix(\.gainLinear), gainParabolic: mix(\.gainParabolic),
                                  gainCubic: mix(\.gainCubic), gainQuartic: mix(\.gainQuartic),
                                  tangentSpeedLinear: mix(\.tangentSpeedLinear),
                                  tangentSpeedParabolicRoot: mix(\.tangentSpeedParabolicRoot))
        } else {
            curve = lo
        }
        let c = curve
        func f1(_ x: Double) -> Double {
            c.gainLinear * x + pow(c.gainParabolic * x, 2) + pow(c.gainCubic * x, 3) + pow(c.gainQuartic * x, 4)
        }
        func slope(_ x: Double) -> Double {
            c.gainLinear + 2 * x * pow(c.gainParabolic, 2) + 3 * pow(x, 2) * pow(c.gainCubic, 3)
                + 4 * pow(x, 3) * pow(c.gainQuartic, 4)
        }
        if c.tangentSpeedLinear != 0 {
            let y0 = f1(c.tangentSpeedLinear)
            m.0 = slope(c.tangentSpeedLinear)
            b.0 = y0 - m.0 * c.tangentSpeedLinear
            tangent.0 = c.tangentSpeedLinear
            if c.tangentSpeedParabolicRoot != 0 {
                let y1 = m.0 * c.tangentSpeedParabolicRoot + b.0
                m.1 = 2 * y1 * m.0
                b.1 = y1 * y1 - m.1 * c.tangentSpeedParabolicRoot
                tangent.1 = c.tangentSpeedParabolicRoot
            }
        } else if c.tangentSpeedParabolicRoot != 0 {
            let y0 = f1(c.tangentSpeedParabolicRoot)
            m.1 = slope(c.tangentSpeedParabolicRoot)
            b.1 = y0 * y0 - m.1 * c.tangentSpeedParabolicRoot
            tangent.0 = c.tangentSpeedParabolicRoot
        }
    }

    /// Accelerated speed for a standardized speed (Apple's `multiplier` before `kCursorScale`).
    public func accelerated(_ x: Double) -> Double {
        let c = curve
        if x <= tangent.0 {
            return c.gainLinear * x + pow(c.gainParabolic * x, 2) + pow(c.gainCubic * x, 3) + pow(c.gainQuartic * x, 4)
        }
        if x <= tangent.1, tangent.0 == c.tangentSpeedLinear {
            return m.0 * x + b.0
        }
        return (max(m.1 * x + b.1, 0)).squareRoot()
    }
}

/// How macOS turns trackpad motion into pointer and scroll motion, in physical units.
///
/// The HID system (`IOHIDPointerAccelerator::accelerate`) takes each report's delta in device
/// counts, measures speed as counts per report at the device's report rate (`velocity =
/// floor(|delta|)`, scaled by `period / dt` when reports come slower), standardizes it with
/// `resolution / 67`, runs the curve, and multiplies by `kCursorScale = 96 / 67`. Net effect:
/// one inch of travel moves the pointer `96 * f(v) / v` points, where `v` is the standardized
/// speed. With no acceleration (`f(v) = v`) that is 96 points per inch.
///
/// The constants and curves below were read from this project's reference Mac (MacBook Pro,
/// "Apple Internal Keyboard / Trackpad"): `HIDPointerResolution` 400 dpi, `HIDPointerReportRate`
/// 120 Hz, `HIDPointerAccelerationType` = `HIDTrackpadAcceleration`.
public enum MacAcceleration {
    /// Device counts per inch (`HIDPointerResolution` = 400 << 16).
    public static let countsPerInch: Double = 400
    /// Trackpad report rate (`HIDPointerReportRate`).
    public static let reportRate: Double = 120
    /// IOHIDFamily `FRAME_RATE` and `SCREEN_RESOLUTION`.
    public static let frameRate: Double = 67
    public static let screenResolution: Double = 96
    /// Smallest velocity Apple uses (`FIXED_TO_DOUBLE(1)`).
    static let minVelocity: Double = 1.0 / 65536

    /// `HIDAccelCurves` of the built-in trackpad, one per tracking-speed index 0...3.
    public static let trackpadPointerCurves: [HIDAccelCurve] = [
        .fixed(0, linear: 65536, tangentLinear: 484966, tangentRoot: 1376256),
        .fixed(8192, linear: 64881, parabolic: 32768, cubic: 5243, tangentLinear: 478413, tangentRoot: 1310720),
        .fixed(32768, linear: 64225, parabolic: 43254, cubic: 6554, tangentLinear: 471859, tangentRoot: 1245184),
        .fixed(45056, linear: 62915, parabolic: 54395, cubic: 7864, tangentLinear: 465306, tangentRoot: 1179648),
        .fixed(57344, linear: 61604, parabolic: 65536, cubic: 9830, tangentLinear: 458752, tangentRoot: 1114112),
        .fixed(65536, linear: 60293, parabolic: 75366, cubic: 11796, tangentLinear: 458752, tangentRoot: 1048576),
        .fixed(98304, linear: 58327, parabolic: 85197, cubic: 13763, tangentLinear: 458752, tangentRoot: 983040),
        .fixed(131072, linear: 56361, parabolic: 95027, cubic: 15729, tangentLinear: 458752, tangentRoot: 917504),
        .fixed(163840, linear: 54395, parabolic: 108790, cubic: 18350, tangentLinear: 458752, tangentRoot: 851968),
        .fixed(196608, linear: 65536, parabolic: 123208, cubic: 23593, tangentLinear: 458752, tangentRoot: 786432),
    ]

    /// `HIDScrollAccelCurves` of the built-in trackpad, one per scrolling-speed index 0...3.
    public static let trackpadScrollCurves: [HIDAccelCurve] = [
        .fixed(0, linear: 65536, tangentLinear: 393216, tangentRoot: 786432),
        .fixed(8192, linear: 62259, parabolic: 39322, tangentLinear: 406323, tangentRoot: 786432),
        .fixed(32768, linear: 58982, parabolic: 58982, tangentLinear: 419430, tangentRoot: 786432),
        .fixed(45056, linear: 55706, parabolic: 78643, tangentLinear: 432538, tangentRoot: 786432),
        .fixed(57344, linear: 52429, parabolic: 91750, tangentLinear: 445645, tangentRoot: 786432),
        .fixed(65536, linear: 49152, parabolic: 104858, tangentLinear: 458752, tangentRoot: 786432),
        .fixed(98304, linear: 45875, parabolic: 117965, tangentLinear: 471859, tangentRoot: 786432),
        .fixed(131072, linear: 42598, parabolic: 131072, tangentLinear: 484966, tangentRoot: 786432),
        .fixed(163840, linear: 39322, parabolic: 144179, tangentLinear: 498074, tangentRoot: 786432),
        .fixed(196608, linear: 36045, parabolic: 157286, tangentLinear: 511181, tangentRoot: 786432),
    ]

    /// Mac points per inch of finger travel at `inchesPerSecond`, for an acceleration curve.
    /// This is exactly `IOHIDPointerAccelerator` for a device reporting at `reportRate`.
    public static func gain(inchesPerSecond speed: Double, curve: ParametricAcceleration) -> Double {
        let countsPerReport = max(speed, 0) * countsPerInch / reportRate
        let velocity = max(countsPerReport.rounded(.down), minVelocity)
        let standardized = velocity / (countsPerInch / frameRate)
        let out = curve.accelerated(standardized) * (screenResolution / frameRate)
        // dx_out = dx_counts * out / velocity; per inch that is countsPerInch * out / velocity.
        return countsPerInch * out / velocity
    }

    /// The pointer curve for a tracking speed (`com.apple.trackpad.scaling`, 0...3).
    public static func pointerCurve(trackingSpeed: Double) -> ParametricAcceleration {
        ParametricAcceleration(curves: trackpadPointerCurves, index: min(max(trackingSpeed, 0), 3))
    }

    /// The scroll curve for a scrolling speed (`com.apple.trackpad.scrolling`, 0...3 in the
    /// table; System Settings writes 0...1).
    public static func scrollCurve(scrollSpeed: Double) -> ParametricAcceleration {
        ParametricAcceleration(curves: trackpadScrollCurves, index: min(max(scrollSpeed, 0), 3))
    }
}
