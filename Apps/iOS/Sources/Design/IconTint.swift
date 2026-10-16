import CoreImage
import GlasspadKit
import ObjectiveC
import SwiftUI
import UIKit

/// App icons and website logos in Mono and the tinted themes, the way the tinted Home Screen
/// shows them: each pixel's brightness looked up along a ramp of the theme's hue (grey in
/// Mono), so the icon keeps its detail and its shape but takes the theme's one colour.
///
/// Each icon is recoloured once per look, on the GPU, and the result is kept with the icon
/// itself, so drawing it again (every frame of a scroll, every redraw) costs nothing more than
/// drawing the original. Only the latest look is kept, so switching themes never piles up copies.
@MainActor
enum IconTint {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    /// Colour cubes by look; there are only ever a few.
    private static var cubes: [String: Data] = [:]
    nonisolated(unsafe) private static var variantKey: UInt8 = 0

    private final class Variant {
        let key: String
        let image: UIImage
        init(key: String, image: UIImage) {
            self.key = key
            self.image = image
        }
    }

    /// `icon` recoloured along `ramp`, named by `key`.
    static func image(_ icon: UIImage, key: String, ramp: () -> [RGBA]) -> UIImage {
        if let v = objc_getAssociatedObject(icon, &variantKey) as? Variant, v.key == key { return v.image }
        guard let made = recolor(icon, cube: cube(key, ramp)) else { return icon }
        objc_setAssociatedObject(icon, &variantKey, Variant(key: key, image: made), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return made
    }

    /// Side of the colour cube. Brightness is a straight line through it, so a small cube
    /// interpolates the ramp exactly enough.
    private static let side = 32

    /// A colour cube sending every colour to the ramp step for its brightness.
    private static func cube(_ key: String, _ ramp: () -> [RGBA]) -> Data {
        if let data = cubes[key] { return data }
        let steps = ramp()
        let n = side
        var values = [Float](repeating: 1, count: n * n * n * 4)
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    // Brightness as the eye weighs the three channels (Rec. 709 luma).
                    let y = (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / Double(n - 1)
                    let c = steps[min(steps.count - 1, Int((y * Double(steps.count - 1)).rounded()))]
                    let i = ((b * n + g) * n + r) * 4
                    values[i] = Float(c.r)
                    values[i + 1] = Float(c.g)
                    values[i + 2] = Float(c.b)
                }
            }
        }
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        if cubes.count > 8 { cubes.removeAll() }
        cubes[key] = data
        return data
    }

    private static func recolor(_ icon: UIImage, cube: Data) -> UIImage? {
        guard let cg = icon.cgImage else { return nil }
        let input = CIImage(cgImage: cg)
        // The cube works on colours before transparency is applied, so soft edges keep their shape.
        let output = input.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": side,
            "inputCubeData": cube,
            "inputColorSpace": sRGB,
        ])
        guard let out = context.createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: sRGB) else { return nil }
        return UIImage(cgImage: out, scale: icon.scale, orientation: icon.imageOrientation)
    }
}

extension Palette {
    /// An app icon or a website logo as this theme draws it: grey in Mono, in the theme's hue
    /// in the tinted themes, untouched everywhere else. Every view that shows an icon goes
    /// through here.
    @MainActor
    func appIcon(_ icon: UIImage) -> UIImage {
        if monochrome { return IconTint.image(icon, key: "gray") { ThemeTint.grayRamp } }
        guard let tint = tokens.tint else { return icon }
        return IconTint.image(icon, key: "\(tint.hue).\(tint.saturation).\(isDark)") { tint.iconRamp(dark: isDark) }
    }

    /// What a website logo with transparent parts sits on: white, or the lightest step of the
    /// tinted ramp, so it matches the icons around it.
    var iconBacking: Color {
        guard let tint = tokens.tint else { return .white }
        return Color(uiColor: UIColor(tint.iconColor(at: 1, dark: isDark)))
    }
}
