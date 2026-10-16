import CoreImage
import GlasspadKit
import UIKit

/// The Photo theme's backdrop: a photo the person picked, blurred into soft colour and veiled
/// just enough for text to read on it (`PhotoTone`). The blurred photo is kept in the app's own
/// files on this iPhone and never leaves it.
///
/// Like the glass backdrops it is a square tile laid from the window's top left. The photo
/// fills the portrait screen, and its mirror across the diagonal fills what landscape adds, so
/// both orientations show the photo and the seam melts into the blur.
final class PhotoBackdrop: @unchecked Sendable {
    static let shared = PhotoBackdrop()

    struct Current {
        /// The blurred, veiled tile.
        let tile: UIImage
        /// The part of the tile a screen shows, small, for the theme's preview.
        let preview: UIImage
        let tone: PhotoTone
        /// Changes with every new photo, so palettes made from an older one are not reused.
        let version: Int
    }

    private let lock = NSLock()
    private var stored: Current?
    private var loaded = false

    /// The photo in use, read from disk the first time it is asked for. Nil until one is picked.
    var current: Current? {
        lock.lock()
        defer { lock.unlock() }
        if !loaded {
            loaded = true
            if let data = try? Data(contentsOf: Self.fileURL), let blurred = UIImage(data: data) {
                stored = Self.finish(blurred, version: 1)
            }
        }
        return stored
    }

    private static var fileURL: URL {
        let folder = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return folder.appendingPathComponent("PhotoBackdrop.jpg")
    }

    /// Blurs `data` (any image the photo picker hands over) into the backdrop for a screen of
    /// `screen` points, saves it and makes it current. Runs off the main thread.
    func use(_ data: Data, screen: CGSize) async -> Bool {
        guard let blurred = await Task.detached(priority: .userInitiated, operation: { Self.blur(data, screen: screen) }).value,
              let jpeg = blurred.jpegData(compressionQuality: 0.9) else { return false }
        do {
            try jpeg.write(to: Self.fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            return false
        }
        let version = (current?.version ?? 0) + 1
        let finished = Self.finish(blurred, version: version)
        lock.withLock { stored = finished }
        await MainActor.run { PhoneSettings.shared.photoVersion = version }
        return true
    }

    /// The phone's screen in points, for laying the photo out.
    @MainActor static var screenSize: CGSize {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.screen.bounds.size ?? CGSize(width: 402, height: 874)
    }

    // MARK: Drawing

    private static let blurRadius: CGFloat = 30

    /// The photo laid out on the tile and blurred, before the veil.
    private static func blur(_ data: Data, screen: CGSize) -> UIImage? {
        guard let photo = downsampled(data, maxPixels: Backdrop.side) else { return nil }
        let w = min(screen.width, screen.height), h = max(screen.width, screen.height)
        let side = Backdrop.side
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let laid = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            let cg = ctx.cgContext
            // Under everything, the photo across the whole tile, so no edge is ever empty.
            photo.draw(in: fill(photo.size, into: CGRect(x: 0, y: 0, width: side, height: side)))
            // Its mirror across the diagonal: what landscape shows beyond the portrait width.
            let portrait = fill(photo.size, into: CGRect(x: 0, y: 0, width: w, height: h))
            cg.saveGState()
            cg.clip(to: CGRect(x: 0, y: 0, width: side, height: w))
            cg.concatenate(CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0))
            cg.clip(to: CGRect(x: 0, y: 0, width: w, height: h))
            photo.draw(in: portrait)
            cg.restoreGState()
            // The photo itself, filling the portrait screen.
            cg.saveGState()
            cg.clip(to: CGRect(x: 0, y: 0, width: w, height: h))
            photo.draw(in: portrait)
            cg.restoreGState()
        }
        guard let input = CIImage(image: laid) else { return nil }
        let extent = input.extent
        let soft = input.clampedToExtent()
            .applyingGaussianBlur(sigma: blurRadius)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.15])
            .cropped(to: extent)
        guard let out = CIContext().createCGImage(soft, from: extent) else { return nil }
        return UIImage(cgImage: out, scale: 1, orientation: .up)
    }

    /// The rectangle that fills `rect` with an image of `size`, centred, cropping the excess.
    private static func fill(_ size: CGSize, into rect: CGRect) -> CGRect {
        let scale = max(rect.width / max(1, size.width), rect.height / max(1, size.height))
        let s = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height)
    }

    /// The photo at no more than `maxPixels` on its long side, upright, without decoding it at full size.
    private static func downsampled(_ data: Data, maxPixels: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Works out the tone from colours across the blurred photo and draws the veil over it.
    private static func finish(_ blurred: UIImage, version: Int) -> Current {
        let tone = PhotoTone.fit(samples: samples(blurred))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let tile = UIGraphicsImageRenderer(size: blurred.size, format: format).image { ctx in
            blurred.draw(at: .zero)
            UIColor(tone.veilColor.alpha(tone.veil)).setFill()
            ctx.fill(CGRect(origin: .zero, size: blurred.size), blendMode: .normal)
        }
        let shown = blurred.size.width * Backdrop.shown
        let preview = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 160), format: format).image { _ in
            tile.draw(in: CGRect(x: 0, y: 0, width: blurred.size.width * 160 / shown, height: blurred.size.height * 160 / shown))
        }
        return Current(tile: tile, preview: preview, tone: tone, version: version)
    }

    /// Colours on an 8 by 8 grid over the part of the tile a screen can show.
    private static func samples(_ image: UIImage) -> [RGBA] {
        guard let cg = image.cgImage else { return [] }
        let n = 8
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            // The tile's top left 80 percent is the most any iPhone shows; draw it into the grid.
            let shown = CGFloat(cg.width) * Backdrop.shown
            let scale = CGFloat(n) / shown
            ctx.draw(cg, in: CGRect(x: 0, y: CGFloat(n) - CGFloat(cg.height) * scale,
                                    width: CGFloat(cg.width) * scale, height: CGFloat(cg.height) * scale))
            return true
        }
        guard drawn else { return [] }
        return stride(from: 0, to: pixels.count, by: 4).map {
            RGBA(r: Double(pixels[$0]) / 255, g: Double(pixels[$0 + 1]) / 255, b: Double(pixels[$0 + 2]) / 255)
        }
    }
}
