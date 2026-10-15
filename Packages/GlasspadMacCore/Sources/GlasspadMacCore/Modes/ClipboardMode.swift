import AppKit
import GlasspadKit
import ImageIO
import UniformTypeIdentifiers

/// Clipboard mode: text and PNG images on NSPasteboard.
///
/// The pasteboard is read and written on the main thread; image conversion and shrinking run on
/// a background queue, because a large screenshot takes hundreds of milliseconds and the main
/// thread also posts the pointer events.
@MainActor
public final class ClipboardMode {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    /// Puts the content on the pasteboard. For an image the PNG is there at once; a TIFF copy
    /// (many apps only read TIFF) is added once converted, unless the pasteboard changed meanwhile.
    public func push(_ content: ClipboardContent) {
        pasteboard.clearContents()
        switch content {
        case .text(let s):
            pasteboard.setString(s, forType: .string)
        case .imagePNG(let data):
            pasteboard.setData(data, forType: .png)
            let change = pasteboard.changeCount
            Task { [weak self] in
                guard let tiff = await Self.offMain({ Self.tiff(fromPNG: data) }),
                      let self, self.pasteboard.changeCount == change else { return }
                self.pasteboard.setData(tiff, forType: .tiff)
            }
        }
    }

    /// Image first (PNG, or TIFF converted to PNG), then text, else nil. Images too large for
    /// one message are scaled down until they fit.
    public func pull() async -> ClipboardContent? {
        if let png = pasteboard.data(forType: .png) {
            return await Self.offMain { Self.fitting(png) }.map { .imagePNG($0) }
        }
        if let tiff = pasteboard.data(forType: .tiff) {
            return await Self.offMain { Self.png(fromImage: tiff).flatMap(Self.fitting) }.map { .imagePNG($0) }
        }
        if let s = pasteboard.string(forType: .string) { return .text(s) }
        return nil
    }

    nonisolated static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: work()) }
        }
    }

    /// The PNG as is when it fits `ClipboardContent.maxImageBytes`, else redrawn smaller until it
    /// does. ImageIO only, so it is safe off the main thread.
    nonisolated static func fitting(_ png: Data) -> Data? {
        guard png.count > ClipboardContent.maxImageBytes else { return png }
        guard let source = CGImageSourceCreateWithData(png as CFData, nil), CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        var scale = (Double(ClipboardContent.maxImageBytes) / Double(png.count)).squareRoot()
        for _ in 0..<6 {
            let side = max(1, Int(Double(max(width, height)) * scale))
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                            kCGImageSourceThumbnailMaxPixelSize: side,
                                            kCGImageSourceCreateThumbnailWithTransform: true]
            guard let small = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            if let out = encode(small, as: .png), out.count <= ClipboardContent.maxImageBytes { return out }
            scale *= 0.7
        }
        return nil
    }

    nonisolated static func png(fromImage data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return encode(image, as: .png)
    }

    nonisolated static func tiff(fromPNG data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return encode(image, as: .tiff)
    }

    private nonisolated static func encode(_ image: CGImage, as type: UTType) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
