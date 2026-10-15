// Draws the Glasspad app icons with CoreGraphics (same shapes as docs/brand/icon.svg).
// Usage: swift scripts/make-icons.swift   (run from the repo root)
import AppKit

struct Theme { let outer: NSColor; let surface: NSColor; let edge: NSColor; let dot: NSColor }
let paper = Theme(outer: NSColor(srgbRed: 0.929, green: 0.925, blue: 0.910, alpha: 1),
                  surface: NSColor(srgbRed: 0.985, green: 0.983, blue: 0.976, alpha: 1),
                  edge: NSColor(white: 0.1, alpha: 0.10), dot: NSColor(white: 0.1, alpha: 0.24))
/// For the iOS tinted icon: iOS tints a grayscale image, so this is light shapes on black.
let tinted = Theme(outer: NSColor(white: 0, alpha: 1), surface: NSColor(white: 0.16, alpha: 1),
                   edge: NSColor(white: 1, alpha: 0.14), dot: NSColor(white: 1, alpha: 0.9))
let graphite = Theme(outer: NSColor(white: 0.055, alpha: 1), surface: NSColor(white: 0.106, alpha: 1),
                     edge: NSColor(white: 1, alpha: 0.08), dot: NSColor(white: 1, alpha: 0.26))

func render(px: Int, theme: Theme, mac: Bool) -> Data {
    // iOS icons must be opaque (no alpha channel) and drawn at their real pixel size.
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
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

    // One finger: a solid dot with two faint ripple rings (a tap with haptic feedback)
    let design = ProcessInfo.processInfo.environment["DESIGN"] ?? "trail"
    func pt(_ x: CGFloat, _ yTop: CGFloat) -> CGPoint { CGPoint(x: body.minX + x * k, y: body.minY + (1024 - yTop) * k) }
    func disc(_ c: CGPoint, _ r: CGFloat, _ alpha: CGFloat) {
        theme.dot.withAlphaComponent(alpha * 0.62).setFill()
        NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).fill()
    }
    func ring(_ c: CGPoint, _ r: CGFloat, _ w: CGFloat, _ alpha: CGFloat) {
        let p = NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        p.lineWidth = w; theme.dot.withAlphaComponent(alpha).setStroke(); p.stroke()
    }
    if design == "trail" {
        // One continuous tapered stroke: the outline around a small circle at the start and the
        // finger's circle at the end, joined by their outer tangents, filled flat. Then the solid finger dot on top.
        let from = pt(300, 610), to = pt(660, 440)
        let r0 = 22 * k, r1 = 74 * k
        let dx = to.x - from.x, dy = to.y - from.y
        let d = (dx * dx + dy * dy).squareRoot()
        let theta = atan2(dy, dx)
        let phi = acos((r0 - r1) / d)
        let trail = CGMutablePath()
        trail.addArc(center: from, radius: r0, startAngle: theta + phi, endAngle: theta - phi + 2 * .pi, clockwise: false)
        trail.addArc(center: to, radius: r1, startAngle: theta - phi, endAngle: theta + phi, clockwise: false)
        trail.closeSubpath()
        // Flat: one even tint, no gradient.
        cg.addPath(trail)
        cg.setFillColor(theme.dot.withAlphaComponent(0.22).cgColor)
        cg.fillPath()
        theme.surface.setFill()
        NSBezierPath(ovalIn: CGRect(x: to.x - r1, y: to.y - r1, width: 2 * r1, height: 2 * r1)).fill()
        disc(to, r1, 1)
    } else {
        let c = pt(512, 512)
        ring(c, 230 * k, 5 * k, 0.25)
        ring(c, 160 * k, 5 * k, 0.45)
        disc(c, 76 * k, 1)
    }
    if mac { cg.restoreGState() }
    NSGraphicsContext.current = nil
    if mac { return rep.representation(using: .png, properties: [:])! }
    // iOS: flatten into an opaque sRGB bitmap so the PNG has no alpha channel at all.
    let flat = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                         bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    flat.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: px, height: px))
    return NSBitmapImageRep(cgImage: flat.makeImage()!).representation(using: .png, properties: [:])!
}

func menuBar(px: Int) -> Data {
    // Template image: black on transparent, 18 pt square. macOS tints it for light and dark bars.
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let u = CGFloat(px) / 18
    NSColor.black.setStroke(); NSColor.black.setFill()
    let r = CGRect(x: 1.5 * u, y: 3.5 * u, width: 15 * u, height: 11 * u)
    let p = NSBezierPath(roundedRect: r, xRadius: 3.2 * u, yRadius: 3.2 * u)
    p.lineWidth = 1.3 * u; p.stroke()
    for i in 0..<3 {
        let t = CGFloat(i) / 3
        let c = CGPoint(x: (4.6 + 3.2 * t) * u, y: (7.2 + 1.9 * t) * u)
        let rr = (0.45 + 0.35 * t) * u
        NSColor.black.withAlphaComponent(0.3 + 0.5 * t).setFill()
        NSBezierPath(ovalIn: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr)).fill()
    }
    NSColor.black.setFill()
    NSBezierPath(ovalIn: CGRect(x: 11.2 * u - 1.7 * u, y: 10.6 * u - 1.7 * u, width: 3.4 * u, height: 3.4 * u)).fill()
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
write(render(px: 1024, theme: tinted, mac: false), "\(ios)/AppIcon-1024-tinted.png")
write(Data("""
{
  "images" : [
    { "filename" : "AppIcon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "AppIcon-1024-dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ], "filename" : "AppIcon-1024-tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
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
if let d = ProcessInfo.processInfo.environment["PREVIEW_DIR"] { write(render(px: 512, theme: paper, mac: true), d + "/paper.png") }
print("done")
