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

    /// Image first (PNG, or TIFF converted to PNG), then text, else nil.
    public func pull() -> ClipboardContent? {
        if let png = pasteboard.data(forType: .png) { return .imagePNG(png) }
        if let tiff = pasteboard.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return .imagePNG(png)
        }
        if let s = pasteboard.string(forType: .string) { return .text(s) }
        return nil
    }
}
