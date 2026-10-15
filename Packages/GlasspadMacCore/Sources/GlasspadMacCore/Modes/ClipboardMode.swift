import AppKit
import GlasspadKit

/// Clipboard mode: text and PNG images on NSPasteboard.
@MainActor
public final class ClipboardMode {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    public func push(_ content: ClipboardContent) {
        pasteboard.clearContents()
        switch content {
        case .text(let s):
            pasteboard.setString(s, forType: .string)
        case .imagePNG(let data):
            pasteboard.setData(data, forType: .png)
            // Many apps only read TIFF; add it when the PNG decodes.
            if let tiff = NSImage(data: data)?.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        }
    }

    /// Image first (PNG, or TIFF converted to PNG), then text, else nil. Images too large for
    /// one message are scaled down until they fit.
    public func pull() -> ClipboardContent? {
        if let png = pasteboard.data(forType: .png) { return Self.fitting(png).map { .imagePNG($0) } }
        if let tiff = pasteboard.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return Self.fitting(png).map { .imagePNG($0) }
        }
        if let s = pasteboard.string(forType: .string) { return .text(s) }
        return nil
    }

    /// The PNG as is when it fits `ClipboardContent.maxImageBytes`, else redrawn smaller until it does.
    static func fitting(_ png: Data) -> Data? {
        guard png.count > ClipboardContent.maxImageBytes else { return png }
        guard let source = NSBitmapImageRep(data: png) else { return nil }
        var scale = (Double(ClipboardContent.maxImageBytes) / Double(png.count)).squareRoot()
        for _ in 0..<6 {
            let w = max(1, Int(Double(source.pixelsWide) * scale)), h = max(1, Int(Double(source.pixelsHigh) * scale))
            guard let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                               bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
            source.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
            NSGraphicsContext.restoreGraphicsState()
            if let out = small.representation(using: .png, properties: [:]), out.count <= ClipboardContent.maxImageBytes {
                return out
            }
            scale *= 0.7
        }
        return nil
    }
}
