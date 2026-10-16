import AppKit
import GlasspadKit
import ImageIO
import UniformTypeIdentifiers

/// Clipboard mode: text and PNG images on NSPasteboard.
///
/// The pasteboard is read and written on the main thread; image conversion and shrinking run on
/// a background queue, because a large screenshot takes hundreds of milliseconds and the main
/// thread also posts the pointer events.
///
/// Size: a clipboard answer goes out as one control message, and the phone counts the link as
/// dead after a few seconds with no whole message (pings queue behind a big one). An 11 MB image
/// (about 15 MB as base64) takes longer than that on a slow Wi-Fi, which dropped the session and
/// any drag with it, and text had no cap at all. So what the Mac sends is kept to
/// `ClipboardLimits`: images are scaled down to fit, and text over the cap is refused rather than
/// cut (a cut paste is worse than none), with the reason in `lastRefusal`.
@MainActor
public final class ClipboardMode {
    private let pasteboard: NSPasteboard
    /// Why the last pull sent nothing although the pasteboard had something, nil when it sent it.
    public private(set) var lastRefusal: String?

    public init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    /// What a pull found.
    public enum PullResult: Equatable, Sendable {
        case content(ClipboardContent)
        /// No text or image on the pasteboard.
        case empty
        /// Text larger than `ClipboardLimits.maxTextBytes` (UTF-8 bytes).
        case tooLarge(bytes: Int)
    }

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

    /// Image first (PNG, or TIFF converted to PNG), then text, else nil. Images larger than
    /// `ClipboardLimits.maxImageBytes` are scaled down until they fit; text over the limit gives
    /// nil (see `pullResult()` for why).
    public func pull() async -> ClipboardContent? {
        if case .content(let c) = await pullResult() { return c }
        return nil
    }

    public func pullResult() async -> PullResult {
        let result: PullResult
        if let png = pasteboard.data(forType: .png) {
            result = await Self.offMain { Self.fitting(png) }.map { .content(.imagePNG($0)) } ?? .empty
        } else if let tiff = pasteboard.data(forType: .tiff) {
            result = await Self.offMain { Self.png(fromImage: tiff).flatMap { Self.fitting($0) } }.map { .content(.imagePNG($0)) } ?? .empty
        } else if let s = pasteboard.string(forType: .string) {
            result = Self.checkText(s)
        } else {
            result = .empty
        }
        if case .tooLarge(let bytes) = result {
            lastRefusal = ClipboardLimits.tooLargeMessage(bytes: bytes)
            GPLog.log("clipboard: not sending \(bytes) bytes of text, over the \(ClipboardLimits.maxTextBytes) byte limit")
        } else {
            lastRefusal = nil
        }
        return result
    }

    nonisolated static func checkText(_ s: String) -> PullResult {
        let bytes = s.utf8.count
        return bytes > ClipboardLimits.maxTextBytes ? .tooLarge(bytes: bytes) : .content(.text(s))
    }

    nonisolated static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: work()) }
        }
    }

    /// The PNG as is when it fits `limit`, else redrawn smaller until it does. ImageIO only, so
    /// it is safe off the main thread.
    nonisolated static func fitting(_ png: Data, limit: Int = ClipboardLimits.maxImageBytes) -> Data? {
        guard png.count > limit else { return png }
        guard let source = CGImageSourceCreateWithData(png as CFData, nil), CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        var scale = (Double(limit) / Double(png.count)).squareRoot()
        for _ in 0..<6 {
            let side = max(1, Int(Double(max(width, height)) * scale))
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                            kCGImageSourceThumbnailMaxPixelSize: side,
                                            kCGImageSourceCreateThumbnailWithTransform: true]
            guard let small = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            if let out = encode(small, as: .png), out.count <= limit { return out }
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

/// How much the Mac puts in one clipboard message.
public enum ClipboardLimits {
    /// Text, in UTF-8 bytes. About 2 million characters of English text; at a slow 1 MB/s the
    /// message still arrives well inside the phone's silence timeout.
    public static let maxTextBytes = 2 << 20
    /// Images, in PNG bytes (the message carries them as base64, 4/3 the size). A full-screen
    /// screenshot scaled to this is still sharp on a phone.
    public static let maxImageBytes = 3 << 20

    public static func tooLargeMessage(bytes: Int) -> String {
        let mb = Double(bytes) / Double(1 << 20)
        return String(format: "The Mac clipboard holds %.1f MB of text, more than the %d MB Glasspad sends at once. Copy a smaller part.",
                      locale: Locale(identifier: "en_US_POSIX"), mb, maxTextBytes >> 20)
    }
}
