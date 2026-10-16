import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// How website logos are stored on the phone: redrawn as 8-bit sRGB with alpha and written as
/// a plain PNG, then read back with ImageIO. UIKit's own decoder refused some logos as they
/// came ("Error -17102 decompressing image"): grey PNGs, and PNGs made from `.ico` frames.
public enum LogoImage {
    /// The image redrawn as 8-bit sRGB with alpha, the one format every decoder takes.
    public static func plainBitmap(_ image: CGImage) -> CGImage? {
        guard image.width > 0, image.height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// True for an image already in that format.
    public static func isPlain(_ image: CGImage) -> Bool {
        image.colorSpace?.name == CGColorSpace.sRGB && image.bitsPerComponent == 8
            && image.bitsPerPixel == 32
    }

    /// A plain PNG (no orientation or other metadata).
    public static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// Frames with more pixels than this are never decoded: a logo file of a few kilobytes can
    /// say it is 50000 pixels square, which would take gigabytes before any scaling down.
    public static let maxSourcePixels = 4096 * 4096

    /// The largest frame of a downloaded logo (an `.ico` holds several sizes), scaled down to
    /// `maxPixelSize` on a side while it decodes, so a huge logo never becomes a huge bitmap.
    /// Only the chosen frame is decoded, and only when it is within `maxSourcePixels`.
    public static func thumbnail(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var best: (index: Int, side: Int)?
        for i in 0..<min(CGImageSourceGetCount(source), 32) {
            guard let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any],
                  let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
                  w > 0, h > 0, w * h <= maxSourcePixels else { continue }
            if best == nil || min(w, h) > best!.side { best = (i, min(w, h)) }
        }
        guard let best else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, best.index, options as CFDictionary)
    }

    /// Decodes image data now; nil when it cannot be read (an SVG, a web page, damage).
    public static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary),
              image.width > 0, image.height > 0 else { return nil }
        return image
    }
}
