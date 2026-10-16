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
/// cut (a cut paste is worse than none), with the reason in `lastRefusal`. A push from the phone
/// is checked the same way and answered with `clipboardPushResult`, so the phone never says
/// "Sent" for something the Mac did not take.
@MainActor
public final class ClipboardMode {
    private let pasteboard: NSPasteboard
    /// Why the last clipboard transfer (either way) did not happen, in words for the user; nil
    /// once a transfer works again. Shown in Settings > Advanced > Diagnostics.
    public private(set) var lastRefusal: String? {
        didSet { if lastRefusal != oldValue { onRefusalChange?(lastRefusal) } }
    }
    /// Called on the main actor whenever `lastRefusal` changes.
    public var onRefusalChange: ((String?) -> Void)?

    public init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    /// Whether macOS refuses Glasspad's reads; tests stand in for System Settings.
    var accessDenied: (NSPasteboard) -> Bool = ClipboardMode.readsDenied

    /// What a pull found.
    public enum PullResult: Equatable, Sendable {
        case content(ClipboardContent)
        /// No text or image on the pasteboard.
        case empty
        /// Text larger than `ClipboardLimits.maxTextBytes` (UTF-8 bytes).
        case tooLarge(bytes: Int)
        /// An image that could not be read or shrunk to `ClipboardLimits.maxImageBytes`.
        case imageNotSendable
        /// The person set Glasspad's pasteboard access to Deny in System Settings, so every
        /// read comes back empty.
        case notAllowed
    }

    /// Puts the content on the pasteboard and returns nil, or returns why it did not (and leaves
    /// the pasteboard as it was). For an image the PNG is there at once; a TIFF copy (many apps
    /// only read TIFF) is added once converted, unless the pasteboard changed meanwhile.
    @discardableResult
    public func push(_ content: ClipboardContent) -> String? {
        if let refusal = Self.check(push: content) {
            lastRefusal = refusal
            GPLog.log("clipboard: refused a \(content.byteCount) byte push from the phone")
            return refusal
        }
        pasteboard.clearContents()
        let written: Bool
        switch content {
        case .text(let s):
            written = pasteboard.setString(s, forType: .string)
        case .imagePNG(let data):
            written = pasteboard.setData(data, forType: .png)
            let change = pasteboard.changeCount
            if written {
                Task { [weak self] in
                    guard let tiff = await Self.offMain({ Self.tiff(fromPNG: data) }),
                          let self, self.pasteboard.changeCount == change else { return }
                    self.pasteboard.setData(tiff, forType: .tiff)
                }
            }
        }
        guard written else {
            let refusal = ClipboardLimits.notWritten
            lastRefusal = refusal
            return refusal
        }
        lastRefusal = nil
        return nil
    }

    /// Why a push from the phone cannot go on the pasteboard, nil when it can.
    nonisolated static func check(push content: ClipboardContent) -> String? {
        switch content {
        case .text(let s):
            let bytes = s.utf8.count
            return bytes > ClipboardContent.maxTextBytes ? ClipboardContent.tooLargeMessage(bytes: bytes, holder: "This text") : nil
        case .imagePNG(let data):
            if data.count > ClipboardContent.maxImageBytes { return ClipboardLimits.imageTooLarge(bytes: data.count) }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int
            else {
                return ClipboardLimits.unreadableImage
            }
            // A small file can hold a huge picture (one colour packs gigabytes of pixels into a few
            // kilobytes); turning it into the TIFF copy would take all of the Mac's memory.
            return width * height > ClipboardLimits.maxImagePixels ? ClipboardLimits.tooManyPixels : nil
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
        if accessDenied(pasteboard) {
            result = .notAllowed
        } else if let png = pasteboard.data(forType: .png) {
            result = await Self.offMain { Self.fitting(png) }.map { .content(.imagePNG($0)) } ?? .imageNotSendable
        } else if let tiff = pasteboard.data(forType: .tiff) {
            result = await Self.offMain { Self.png(fromImage: tiff).flatMap { Self.fitting($0) } }.map { .content(.imagePNG($0)) } ?? .imageNotSendable
        } else if let s = pasteboard.string(forType: .string) {
            result = Self.checkText(s)
        } else {
            result = .empty
        }
        switch result {
        case .tooLarge(let bytes):
            lastRefusal = ClipboardLimits.tooLargeMessage(bytes: bytes)
            GPLog.log("clipboard: not sending \(bytes) bytes of text, over the \(ClipboardLimits.maxTextBytes) byte limit")
        case .imageNotSendable:
            lastRefusal = ClipboardLimits.imageNotSendable
            GPLog.log("clipboard: the image on the pasteboard could not be read or shrunk to send")
        case .notAllowed:
            lastRefusal = ClipboardLimits.notAllowed
            GPLog.log("clipboard: pasteboard access is set to deny for Glasspad")
        case .content, .empty:
            lastRefusal = nil
        }
        return result
    }

    /// True when macOS answers every programmatic read with nothing (pasteboard privacy,
    /// macOS 15.4 and later). Reading the setting itself never shows the Mac's paste alert.
    nonisolated static func readsDenied(_ pasteboard: NSPasteboard) -> Bool {
        guard #available(macOS 15.4, *) else { return false }
        return pasteboard.accessBehavior == .alwaysDeny
    }

    nonisolated static func checkText(_ s: String) -> PullResult {
        let bytes = s.utf8.count
        return bytes > ClipboardLimits.maxTextBytes ? .tooLarge(bytes: bytes) : .content(.text(s))
    }

    /// Tests only: told whether each piece of image work ran on the main thread.
    nonisolated(unsafe) static var offMainProbe: (@Sendable (_ onMainThread: Bool) -> Void)?

    nonisolated static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                offMainProbe?(Thread.isMainThread)
                continuation.resume(returning: work())
            }
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

/// How much the Mac puts in one clipboard message, and what it says when it will not.
public enum ClipboardLimits {
    /// Text, in UTF-8 bytes (the same limit the phone uses). At a slow 1 MB/s the message still
    /// arrives in a couple of seconds, and the link counts partial messages as alive anyway.
    public static let maxTextBytes = ClipboardContent.maxTextBytes
    /// Images, in PNG bytes (the message carries them as base64, 4/3 the size). A full-screen
    /// screenshot scaled to this is still sharp on a phone.
    public static let maxImageBytes = 3 << 20
    /// Pixels in an image from the phone: more than a 48 MP iPhone photo, far less than a picture
    /// made to fill the Mac's memory once decoded.
    public static let maxImagePixels = 100_000_000

    public static func tooLargeMessage(bytes: Int) -> String {
        ClipboardContent.tooLargeMessage(bytes: bytes, holder: "The Mac clipboard")
    }

    static func imageTooLarge(bytes: Int) -> String {
        String(format: "This image is %.1f MB, more than the %d MB Glasspad takes at once.",
               locale: Locale(identifier: "en_US_POSIX"), Double(bytes) / Double(1 << 20), ClipboardContent.maxImageBytes >> 20)
    }

    static let imageNotSendable = "The image on the Mac clipboard could not be made small enough to send. Copy a smaller part of it."
    static let tooManyPixels = "This image is too large for the Mac clipboard. Try a smaller one."
    static let unreadableImage = "Your Mac could not read this image. Try copying it again."
    static let notWritten = "The Mac clipboard did not take it. Try again."
    static let notAllowed = "Your Mac does not let Glasspad read its clipboard. Allow it in System Settings > Privacy & Security."
}
