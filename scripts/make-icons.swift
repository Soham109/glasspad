// Draws the Glasspad app icons with CoreGraphics (same shapes as docs/brand/icon.svg).
// Usage: swift scripts/make-icons.swift   (run from the repo root)
import AppKit

struct Theme { let outer: NSColor; let surface: NSColor; let edge: NSColor; let dot: NSColor }
let paper = Theme(outer: NSColor(srgbRed: 0.929, green: 0.925, blue: 0.910, alpha: 1),
                  surface: NSColor(srgbRed: 0.985, green: 0.983, blue: 0.976, alpha: 1),
                  edge: NSColor(white: 0.1, alpha: 0.10), dot: NSColor(white: 0.1, alpha: 0.24))
let graphite = Theme(outer: NSColor(white: 0.055, alpha: 1), surface: NSColor(white: 0.106, alpha: 1),
                     edge: NSColor(white: 1, alpha: 0.08), dot: NSColor(white: 1, alpha: 0.26))

func render(px: Int, theme: Theme, mac: Bool) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let s = CGFloat(px) / 1024
    cg.scaleBy(x: s, y: s)
    cg.setAllowsAntialiasing(true)
    let full = CGRect(x: 0, y: 0, width: 1024, height: 1024)

    // iOS: full-bleed square (the system rounds it). Mac: rounded body inside a margin, with a soft shadow.
    let body = mac ? full.insetBy(dx: 100, dy: 100) : full
    let bodyRadius: CGFloat = mac ? 185 : 0
    if mac {
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor(white: 0, alpha: 0.28).cgColor)
        theme.outer.setFill()
        NSBezierPath(roundedRect: body, xRadius: bodyRadius, yRadius: bodyRadius).fill()
        cg.restoreGState()
        cg.saveGState()
        NSBezierPath(roundedRect: body, xRadius: bodyRadius, yRadius: bodyRadius).addClip()
    }
    theme.outer.setFill(); body.fill()

    // Glass surface
    let k = body.width / 1024
    let surf = CGRect(x: body.minX + 102 * k, y: body.minY + 222 * k, width: 820 * k, height: 580 * k)
    let sp = NSBezierPath(roundedRect: surf, xRadius: 140 * k, yRadius: 140 * k)
    theme.surface.setFill(); sp.fill()
    theme.edge.setStroke(); sp.lineWidth = 4 * k; sp.stroke()

    // Two finger dots (y is flipped from the SVG)
    func dot(_ x: CGFloat, _ yTop: CGFloat) {
        let r = 72 * k
        let c = CGPoint(x: body.minX + x * k, y: body.minY + (1024 - yTop) * k)
        theme.dot.setFill()
        NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).fill()
    }
    dot(415, 465); dot(625, 565)
    if mac { cg.restoreGState() }
    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

func menuBar(px: Int) -> Data {
    // Template image: black on transparent, 18 pt square. macOS tints it for light and dark bars.
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let u = CGFloat(px) / 18
    NSColor.black.setStroke(); NSColor.black.setFill()
    let r = CGRect(x: 1.75 * u, y: 3 * u, width: 14.5 * u, height: 12 * u).insetBy(dx: 0.0, dy: 0)
    let p = NSBezierPath(roundedRect: r, xRadius: 3.6 * u, yRadius: 3.6 * u)
    p.lineWidth = 1.3 * u; p.stroke()
    for c in [CGPoint(x: 7 * u, y: 9.6 * u), CGPoint(x: 11 * u, y: 8 * u)] {
        NSBezierPath(ovalIn: CGRect(x: c.x - 1.35 * u, y: c.y - 1.35 * u, width: 2.7 * u, height: 2.7 * u)).fill()
    }
    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

func write(_ d: Data, _ path: String) {
    try! FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try! d.write(to: URL(fileURLWithPath: path))
}

// iOS: one 1024 asset (Xcode makes the rest), plus a dark variant and tinted left to the system.
let ios = "Apps/iOS/Resources/Assets.xcassets/AppIcon.appiconset"
write(render(px: 1024, theme: paper, mac: false), "\(ios)/AppIcon-1024.png")
write(render(px: 1024, theme: graphite, mac: false), "\(ios)/AppIcon-1024-dark.png")
write(Data("""
{
  "images" : [
    { "filename" : "AppIcon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "AppIcon-1024-dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
""".utf8), "\(ios)/Contents.json")
write(Data("{ \"info\" : { \"author\" : \"xcode\", \"version\" : 1 } }".utf8), "Apps/iOS/Resources/Assets.xcassets/Contents.json")

// macOS
let mac = "Apps/Mac/Resources/Assets.xcassets/AppIcon.appiconset"
var entries: [String] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pt)x\(pt)@\(scale)x.png"
        write(render(px: pt * scale, theme: paper, mac: true), "\(mac)/\(name)")
        entries.append("    { \"filename\" : \"\(name)\", \"idiom\" : \"mac\", \"scale\" : \"\(scale)x\", \"size\" : \"\(pt)x\(pt)\" }")
    }
}
write(Data("{\n  \"images\" : [\n\(entries.joined(separator: ",\n"))\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n".utf8), "\(mac)/Contents.json")
write(Data("{ \"info\" : { \"author\" : \"xcode\", \"version\" : 1 } }".utf8), "Apps/Mac/Resources/Assets.xcassets/Contents.json")

// Menu bar template image set
let mb = "Apps/Mac/Resources/Assets.xcassets/MenuBarIcon.imageset"
write(menuBar(px: 18), "\(mb)/MenuBarIcon.png")
write(menuBar(px: 36), "\(mb)/MenuBarIcon@2x.png")
write(Data("""
{
  "images" : [
    { "filename" : "MenuBarIcon.png", "idiom" : "mac", "scale" : "1x" },
    { "filename" : "MenuBarIcon@2x.png", "idiom" : "mac", "scale" : "2x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "template-rendering-intent" : "template" }
}
""".utf8), "\(mb)/Contents.json")

// Previews for the docs
write(render(px: 512, theme: paper, mac: true), "docs/brand/preview-mac-paper.png")
write(render(px: 512, theme: graphite, mac: true), "docs/brand/preview-mac-graphite.png")
write(render(px: 512, theme: paper, mac: false), "docs/brand/preview-ios-paper.png")
write(render(px: 1024, theme: paper, mac: true), "docs/brand/icon.png")
print("done")
