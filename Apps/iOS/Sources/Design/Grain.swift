import GlasspadKit
import SwiftUI
import UIKit

/// The grain themes' surface: the theme's colour with a fine still grain, drawn once into a
/// 256 pixel tile at the screen's own pixel density and used as a repeating pattern colour.
/// The window, the trackpad and every panel that fills with the surface colour get it for
/// free; nothing about it moves or redraws, so it costs no power once drawn.
enum Grain {
    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var noise: [Int: [Double]] = [:]
        var tiles: [String: UIImage] = [:]
    }

    private static let cache = Cache()

    /// The screen's pixels per point. Read from the trait collection when there is one.
    static var scale: CGFloat {
        let s = UITraitCollection.current.displayScale
        return s >= 1 ? s : 3
    }

    /// The tile: `color` under `grain`, one grain value per screen pixel.
    static func tile(_ color: RGBA, _ grain: ThemeGrain) -> UIImage {
        let scale = scale
        let key = "\(color.hex).\(grain.amount).\(scale)"
        cache.lock.lock()
        defer { cache.lock.unlock() }
        if let tile = cache.tiles[key] { return tile }
        let side = ThemeGrain.side
        let noiseKey = Int(scale * 100)
        let noise = cache.noise[noiseKey] ?? ThemeGrain.noise(pixelsPerGrain: scale / 2)
        cache.noise[noiseKey] = noise
        // Linear light, as `ThemeGrain.apply` defines it, straight into bytes.
        let base = (color.r * 255, color.g * 255, color.b * 255)
        let reach = 2 * grain.amount * 255
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        for i in 0..<(side * side) {
            let d = (noise[i] - 0.5) * reach
            pixels[i * 4] = UInt8(min(255, max(0, base.0 + d)).rounded())
            pixels[i * 4 + 1] = UInt8(min(255, max(0, base.1 + d)).rounded())
            pixels[i * 4 + 2] = UInt8(min(255, max(0, base.2 + d)).rounded())
        }
        let image: UIImage = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
                  let cg = ctx.makeImage() else { return UIImage() }
            return UIImage(cgImage: cg, scale: scale, orientation: .up)
        }
        cache.tiles[key] = image
        return image
    }

    /// The surface with its grain as a pattern colour.
    static func color(_ color: RGBA, _ grain: ThemeGrain) -> UIColor {
        UIColor(patternImage: tile(color, grain))
    }
}

/// Fills its frame with a pattern colour (the grain), pixel for pixel. SwiftUI cannot draw a
/// pattern colour itself.
struct PatternFill: UIViewRepresentable {
    let color: UIColor

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = color
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        view.backgroundColor = color
    }
}
