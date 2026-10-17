// Prints the website's theme list (web/src/themes.ts) from the app's theme catalog. Run by
// scripts/web-themes.sh, which compiles this with the catalog's sources.
import Foundation

func hex(_ c: RGBA) -> String { String(format: "#%06X", c.hex) }
func num(_ v: Double) -> String {
    var s = String(format: "%.3f", v)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s
}
func rgba(_ c: RGBA) -> String {
    "rgba(\(Int((c.r * 255).rounded())),\(Int((c.g * 255).rounded())),\(Int((c.b * 255).rounded())),\(num(c.a)))"
}
/// Translucent white cards: glass themes at their usual strength write it short (".52").
func tile(_ t: ThemeTokens) -> String {
    guard t.raised.a < 1 else { return hex(t.raised) }
    let short = t.backdrop != nil && (t.raised.a == (t.isDark ? 0.085 : 0.52))
    let a = num(t.raised.a)
    return "rgba(255,255,255,\(short ? String(a.dropFirst()) : a))"
}
func pct(_ v: Double) -> String { "\(num(v * 100))%" }
func backdrop(_ b: ThemeBackdrop) -> String {
    let alpha = String(format: "%02x", Int((ThemeBackdrop.peak * 255).rounded()))
    return (b.pools.map { "radial-gradient(\(pct($0.radius)) \(pct($0.radius)) at \(pct($0.x)) \(pct($0.y)), \(hex($0.color))\(alpha), transparent)" }
        + [hex(b.base)]).joined(separator: ", ")
}
func bg(_ t: ThemeTokens) -> String { t.backdrop.map(backdrop) ?? hex(t.background) }

/// Photo has no fixed colours; the site shows a sample photo.
let photo = ##"  { key: "photo", name: "Photo", group: "Photo", bg: "radial-gradient(60% 60% at 30% 30%, #F2C38Bd9, transparent), radial-gradient(55% 55% at 75% 70%, #5C86B8d9, transparent), radial-gradient(40% 40% at 80% 20%, #E78C6Ed9, transparent), #7A8C9E", tile: "rgba(255,255,255,.52)", ink: "#11141C", ink2: "rgba(17,20,28,0.68)", accent: "#11141C", swatch: "radial-gradient(60% 60% at 30% 30%, #F2C38Bd9, transparent), radial-gradient(55% 55% at 75% 70%, #5C86B8d9, transparent), radial-gradient(40% 40% at 80% 20%, #E78C6Ed9, transparent), #7A8C9E" },"##

ThemeTint.custom = .defaultCustom
for group in ThemeChoice.Group.allCases {
    for theme in group.themes {
        if theme == .photo { print(photo); continue }
        let dark = theme.appearance == .dark
        let t = theme.tokens(dark: dark)
        let swatch = theme.appearance == .followsPhone
            ? (t.backdrop == nil || theme == .clear
                ? "linear-gradient(90deg, \(hex(t.background)) 50%, \(hex(theme.tokens(dark: true).background)) 50%)"
                : bg(t))
            : bg(t)
        var line = "  { key: \"\(theme.rawValue)\", name: \"\(theme.title)\", group: \"\(group.title)\", bg: \"\(bg(t))\", tile: \"\(tile(t))\", ink: \"\(hex(t.ink))\", ink2: \"\(rgba(t.inkSoft))\", accent: \"\(hex(t.accent))\", swatch: \"\(swatch)\""
        if dark { line += ", dark: true" }
        if theme.isMonochrome { line += ", mono: true" }
        if theme.tint != nil { line += ", tinted: true" }
        if let g = t.grain { line += ", grain: \(num(g.amount))" }
        print(line + " },")
    }
}
