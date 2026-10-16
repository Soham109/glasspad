import GlasspadKit
import SwiftUI
import UIKit

// The themes themselves (names, groups and colours) live in GlasspadKit's ThemeCatalog, where
// a test checks every one for contrast. This file turns them into colours the app draws with.

extension ThemeChoice {
    /// The window's appearance for this choice. Themes that follow the phone leave it
    /// unspecified, so SwiftUI's colour scheme reports the phone's real setting.
    var interfaceStyle: UIUserInterfaceStyle {
        // Photo takes the light or dark its photo needs, once there is one.
        if self == .photo, let photo = PhotoBackdrop.shared.current { return photo.tone.isDark ? .dark : .light }
        return switch appearance {
        case .light: .light
        case .dark: .dark
        case .followsPhone: .unspecified
        }
    }

    /// The palette for this choice. `scheme` is the phone's own setting, used by the themes
    /// that follow it. Every colour in it is a semantic token that resolves against the light
    /// or dark appearance it is drawn in; the window appearance above makes that match.
    func resolved(_ scheme: ColorScheme) -> Palette {
        let dark: Bool = switch interfaceStyle {
        case .light: false
        case .dark: true
        default: scheme == .dark
        }
        return Palette.themed(self, dark: dark)
    }

    /// Fixed colours of this theme in one appearance, for the previews in Settings. The glass
    /// backdrop is left to the preview to draw small.
    func preview(dark: Bool) -> Palette {
        if self == .photo, let photo = PhotoBackdrop.shared.current {
            return Palette.cached("photo.\(photo.version).preview") {
                Palette(light: photo.tone.tokens, dark: photo.tone.tokens, theme: self, isDark: photo.tone.isDark, patternBackdrop: false)
            }
        }
        return Palette.cached("\(cacheName).\(dark).preview") {
            let t = tokens(dark: dark)
            return Palette(light: t, dark: t, theme: self, isDark: dark, patternBackdrop: false)
        }
    }

    /// Remote is always dark: the theme's own dark colours when it has plain ones that suit a
    /// dim room (Mono, Pure Black, High Contrast, the tinted themes), Graphite otherwise.
    var remotePalette: Palette {
        if tint != nil { return preview(dark: true) }
        return switch self {
        case .mono, .pureBlack, .highContrast: preview(dark: true)
        default: .graphite
        }
    }

    /// Names this theme's palettes in the cache. Custom Tint's colours change with the
    /// person's colour, so its name carries the colour.
    fileprivate var cacheName: String {
        guard self == .customTint, let tint else { return rawValue }
        return "\(rawValue).\(tint.hue).\(tint.saturation)"
    }
}

/// Every colour the app draws with. Views never hard code colours; they read a palette.
///
/// The app palette (`themed`) is made of semantic tokens: each colour carries its light value
/// and its dark value and picks one from the trait collection it is drawn in. So text,
/// symbols and UIKit-backed controls (menus, pickers, toggles) can never be left holding the
/// other appearance's colour after a change. `preview` palettes are fixed versions, used only
/// to show a theme next to another one.
struct Palette: Equatable, Sendable {
    let theme: ThemeChoice
    let isDark: Bool
    /// The colours as numbers in the current appearance, for making a colour readable here.
    let tokens: ThemeTokens
    /// Mono: no colour anywhere. Tiles, symbols and accents all draw in the ink.
    var monochrome: Bool { theme.isMonochrome }
    /// The tinted themes: one hue for everything. Colours chosen by modes and by the person
    /// move onto it (see `tint`), and app icons take it too (see `appIcon`).
    var tinted: Bool { tokens.tint != nil }
    /// Glass themes: the surface is a soft coloured backdrop and raised things are frosted
    /// and translucent. Floating controls use the system's Liquid Glass.
    var glass: Bool { theme.isGlass }
    /// The surface is a pattern (a glass backdrop, a photo or grain) that SwiftUI cannot draw
    /// as a colour, so the window draws it behind everything.
    var patterned: Bool { glass || tokens.grain != nil }
    /// The surface itself. In the glass themes this is a soft gradient (a pattern colour), so
    /// use it only to fill an area, never for text or symbols; those take `solid`.
    private(set) var background: UIColor
    /// A plain colour that matches the surface, for text and symbols on an ink filled button.
    let solid: UIColor
    /// Cards and buttons that sit on the surface.
    let raised: UIColor
    /// A pressed or selected raised element.
    let raisedPressed: UIColor
    /// Hairlines.
    let line: UIColor
    /// Primary text and symbols.
    let ink: UIColor
    /// Secondary text.
    let inkSoft: UIColor
    /// The theme's own colour, for controls, switches and links.
    let accent: UIColor
    /// The finger dot colour before the user's opacity setting.
    let dotBase: UIColor
    /// The user's dot opacity multiplier.
    var dotScale: CGFloat = 1
    /// Finger dot diameter in points and look, from Settings.
    var dotDiameter: CGFloat = 44
    var dotStyle: DotStyle = .soft

    /// Finger dots on the trackpad (opacity already includes the user's setting).
    var dot: UIColor {
        let base = dotBase, scale = dotScale
        return UIColor { traits in
            let c = base.resolvedColor(with: traits)
            return c.withAlphaComponent(min(0.9, c.cgColor.alpha * scale))
        }
    }

    private static func dynamic(_ light: RGBA, _ dark: RGBA) -> UIColor {
        if light == dark { return UIColor(light) }
        let l = UIColor(light), d = UIColor(dark)
        return UIColor { $0.userInterfaceStyle == .dark ? d : l }
    }

    /// Colours that follow the appearance they are drawn in, between `light` and `dark`.
    /// `patternBackdrop` fills the glass themes' surface with the full size backdrop.
    fileprivate init(light: ThemeTokens, dark: ThemeTokens, theme: ThemeChoice, isDark: Bool, patternBackdrop: Bool) {
        let d = Palette.dynamic
        self.theme = theme
        self.isDark = isDark
        tokens = isDark ? dark : light
        if patternBackdrop, let lb = light.backdrop, let db = dark.backdrop {
            let l = Backdrop.color(lb), dk = Backdrop.color(db)
            background = lb == db ? l : UIColor { $0.userInterfaceStyle == .dark ? dk : l }
        } else if patternBackdrop, let lg = light.grain, let dg = dark.grain {
            let l = Grain.color(light.background, lg), dk = Grain.color(dark.background, dg)
            background = light == dark ? l : UIColor { $0.userInterfaceStyle == .dark ? dk : l }
        } else {
            background = d(light.background, dark.background)
        }
        solid = d(light.solid, dark.solid)
        raised = d(light.raised, dark.raised)
        raisedPressed = d(light.raisedPressed, dark.raisedPressed)
        line = d(light.line, dark.line)
        ink = d(light.ink, dark.ink)
        inkSoft = d(light.inkSoft, dark.inkSoft)
        accent = d(light.accent, dark.accent)
        dotBase = d(light.dot, dark.dot)
    }

    /// Palettes are made once per theme and appearance, when first asked for, so the glass
    /// backdrops are only drawn for the themes actually shown.
    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var palettes: [String: Palette] = [:]
    }

    private static let cache = Cache()

    fileprivate static func cached(_ key: String, _ make: () -> Palette) -> Palette {
        cache.lock.lock()
        defer { cache.lock.unlock() }
        if let p = cache.palettes[key] { return p }
        // Each Custom Tint colour tried makes palettes of its own; start over now and then.
        if cache.palettes.count > 160 { cache.palettes.removeAll() }
        let p = make()
        cache.palettes[key] = p
        return p
    }

    /// The app palette for a theme. `dark` only says which way the window currently looks;
    /// the colours themselves follow whatever appearance they are drawn in.
    static func themed(_ theme: ThemeChoice = .paper, dark: Bool) -> Palette {
        if theme == .photo, let photo = PhotoBackdrop.shared.current {
            return cached("photo.\(photo.version)") {
                var p = Palette(light: photo.tone.tokens, dark: photo.tone.tokens, theme: theme, isDark: photo.tone.isDark,
                                patternBackdrop: false)
                p.background = UIColor(patternImage: photo.tile)
                return p
            }
        }
        return cached("\(theme.cacheName).\(dark)") {
            Palette(light: theme.tokens(dark: false), dark: theme.tokens(dark: true), theme: theme, isDark: dark, patternBackdrop: true)
        }
    }

    /// Fixed Graphite colours (Remote, and previews).
    static let graphite = ThemeChoice.graphite.preview(dark: true)

    /// A colour the user or a mode chose, or the ink in Mono. Colours too close to the
    /// surface to read (dark grey on Graphite, yellow on Paper, green on Forest) are moved
    /// toward the ink just far enough to read. In a tinted theme the colour first moves onto
    /// the theme's hue, keeping its brightness, so modes and tiles still differ a little.
    func tint(_ color: Color) -> Color {
        if monochrome { return inkColor }
        let c = UIColor(color).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard c.getRed(&r, green: &g, blue: &b, alpha: &a) else { return color }
        let rgba = RGBA(r: r, g: g, b: b, a: a)
        let readable = tokens.readable(tokens.tint?.mapped(rgba) ?? rgba)
        return readable == rgba ? color : Color(uiColor: UIColor(readable))
    }

    /// Symbols on a tile filled with a `tint` colour: white, or the surface colour where the
    /// fills are the ink (Mono) or light (the tinted themes in dark).
    var onFill: Color { monochrome || (tinted && isDark) ? solidColor : .white }

    /// The palette with the user's finger dot size, opacity and style applied.
    @MainActor
    func customized(_ settings: PhoneSettings) -> Palette {
        var p = self
        p.dotScale = settings.dotOpacity
        p.dotDiameter = settings.dotSize
        p.dotStyle = settings.dotStyle
        return p
    }

    /// The traits this palette is meant for, for drawing outside SwiftUI (layers, images).
    var traits: UITraitCollection { UITraitCollection(userInterfaceStyle: isDark ? .dark : .light) }

    /// The glass backdrop at full size (the picked photo in the Photo theme), lined up with the
    /// window's. Nil in the plain themes.
    var backdropImage: UIImage? {
        if theme == .photo, tokens.photoSamples != nil { return PhotoBackdrop.shared.current?.tile }
        return tokens.backdrop.map(Backdrop.image)
    }

    /// The part of the backdrop a screen shows, small, for previews.
    var backdropPreview: UIImage? {
        if theme == .photo, tokens.photoSamples != nil { return PhotoBackdrop.shared.current?.preview }
        return tokens.backdrop.map(Backdrop.preview)
    }

    /// The surface as a SwiftUI colour. Clear in the glass themes: SwiftUI cannot draw a
    /// pattern, so the window draws the backdrop behind everything (see `WindowAppearance`) and
    /// views that must hide what is under them use `SurfaceBackground`.
    var backgroundColor: Color { patterned ? .clear : Color(uiColor: background) }
    /// A sunken area inside a raised card (a text preview): the surface, or in the glass
    /// themes a deeper frost.
    var wellColor: Color { patterned ? raisedPressedColor : backgroundColor }

    /// The grain themes' surface with its grain, as a pattern colour, in this appearance.
    var grainSurface: UIColor? { tokens.grain.map { Grain.color(tokens.background, $0) } }
    /// The surface as a plain colour: text and symbols on an ink filled button.
    var solidColor: Color { Color(uiColor: solid) }
    var raisedColor: Color { Color(uiColor: raised) }
    var raisedPressedColor: Color { Color(uiColor: raisedPressed) }
    var lineColor: Color { Color(uiColor: line) }
    var inkColor: Color { Color(uiColor: ink) }
    var inkSoftColor: Color { Color(uiColor: inkSoft) }
    var accentColor: Color { Color(uiColor: accent) }
    var colorScheme: ColorScheme { isDark ? .dark : .light }

    // Status colours: Apple's green, orange and red, deepened where a theme needs it to read.
    // Mono keeps them out of colour: good is the ink, waiting is the soft ink, and a problem
    // is the ink too (the symbol beside it says which). The tinted themes do the same in
    // their accent.

    /// Connected, passed, done.
    var good: Color { monochrome ? inkColor : tinted ? accentColor : Color(uiColor: UIColor(tokens.good)) }
    /// Waiting or needs a look.
    var caution: Color { monochrome || tinted ? inkSoftColor : Color(uiColor: UIColor(tokens.caution)) }
    /// Failed or recording.
    var bad: Color { monochrome ? inkColor : tinted ? accentColor : Color(uiColor: UIColor(tokens.bad)) }
    /// Idle, or another iPhone has the Mac.
    private var quiet: Color {
        monochrome || tinted ? inkSoftColor : Color(uiColor: UIColor(tokens.readable(SystemHue.gray.value(dark: isDark))))
    }

    /// The connection dot: good when connected, caution while looking, bad on failure, and a
    /// quiet grey when idle or another iPhone has the Mac. In Mono the dot keeps its meaning
    /// through brightness and its pulse while looking.
    func linkColor(_ state: LinkState) -> Color {
        switch state {
        case .connected: good
        case .searching, .connecting: caution
        case .failed where state.isReplaced: quiet
        case .failed: bad
        case .idle: quiet
        }
    }
}

extension UIColor {
    convenience init(_ c: RGBA) {
        self.init(red: c.r, green: c.g, blue: c.b, alpha: c.a)
    }
}

// MARK: - Glass backdrop

/// The soft coloured backdrop behind a glass theme: a few large, blurred pools of colour on a
/// pale (or deep) base, as the catalog describes. It is drawn once into a square tile and used
/// as a pattern colour, so every screen, sheet and the trackpad that fills with the surface
/// colour gets it with no extra views. The pools sit symmetrically about the diagonal, so
/// portrait and landscape crops of the tile look alike.
enum Backdrop {
    /// Side of the square tile, in points. Larger than any iPhone screen, so it never repeats.
    static let side: CGFloat = 1100
    /// The part of the tile a screen shows (its top left), for previews.
    static let shown: CGFloat = 0.8

    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var images: [String: UIImage] = [:]
    }

    private static let cache = Cache()

    /// The full size tile.
    static func image(_ backdrop: ThemeBackdrop) -> UIImage {
        cached(backdrop, side: side, scale: 1)
    }

    static func color(_ backdrop: ThemeBackdrop) -> UIColor { UIColor(patternImage: image(backdrop)) }

    /// A small render of the part of the tile a screen shows, for theme previews.
    static func preview(_ backdrop: ThemeBackdrop) -> UIImage {
        cached(backdrop, side: 160, scale: shown)
    }

    private static func cached(_ backdrop: ThemeBackdrop, side: CGFloat, scale: CGFloat) -> UIImage {
        let key = "\(backdrop.hashValue).\(side)"
        cache.lock.lock()
        defer { cache.lock.unlock() }
        if let image = cache.images[key] { return image }
        let image = render(backdrop, side: side, region: scale)
        cache.images[key] = image
        return image
    }

    /// Draws the `region` (a fraction of the tile, from its top left) into a square of `side`.
    private static func render(_ backdrop: ThemeBackdrop, side: CGFloat, region: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: side, height: side)
        let tile = side / region
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(backdrop.base).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let space = CGColorSpaceCreateDeviceRGB()
            for pool in backdrop.pools {
                let c = CGPoint(x: pool.x * tile, y: pool.y * tile)
                let color = UIColor(pool.color)
                let colors = [color.withAlphaComponent(ThemeBackdrop.peak).cgColor, color.withAlphaComponent(0.4).cgColor,
                              color.withAlphaComponent(0).cgColor] as CFArray
                guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.45, 1]) else { continue }
                ctx.cgContext.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c,
                                                 endRadius: pool.radius * tile, options: [])
            }
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension UIColor {
    /// This colour moved `amount` (0...1) of the way to `other`.
    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        guard getRed(&r1, green: &g1, blue: &b1, alpha: &a1), other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return self }
        let t = min(1, max(0, amount))
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: a1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

// MARK: - Window appearance

/// Sets the appearance of every window in the scene that hosts it. The window is the one
/// place a light or dark choice reaches everything: SwiftUI's own text and symbols, Form rows,
/// presented sheets (including ones already open), confirmation dialogs, context menus,
/// alerts and the keyboard.
///
/// It also paints the window with the theme's surface, so the glass themes' backdrop (which
/// SwiftUI cannot draw as a colour) sits behind every screen, lined up with the trackpad's.
struct WindowAppearance: UIViewRepresentable {
    let style: UIUserInterfaceStyle
    /// Read where this view is made (the root view's body), so a theme change updates it.
    var theme: ThemeChoice = PhoneSettings.shared.theme
    /// The Photo theme's photo, so picking a new one repaints the window.
    var photo = 0
    /// The Custom Tint colour, so picking a new one repaints the window.
    var tint: UInt32 = 0

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        view.isHidden = true
        return view
    }

    func updateUIView(_ view: Probe, context: Context) {
        view.style = style
        view.surface = Palette.themed(theme, dark: style == .dark).background
        view.apply()
    }

    final class Probe: UIView {
        var style: UIUserInterfaceStyle = .unspecified
        var surface: UIColor?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        func apply() {
            guard let scene = window?.windowScene else { return }
            for window in scene.windows where window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
            // The app's window (not the keyboard's) shows the surface; its root view is clear so
            // the surface shows wherever SwiftUI draws nothing.
            guard let window = self.window, let surface else { return }
            window.backgroundColor = surface
            window.rootViewController?.view.backgroundColor = .clear
        }
    }
}

// MARK: - Environment

private struct PaletteKey: EnvironmentKey {
    static let defaultValue: Palette = .themed(dark: false)
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - Shared pieces

/// The theme's surface as a view, for screens and sheets that must hide what is under them.
/// In the glass themes it draws the backdrop lined up with the window's, so a panel filled
/// with it is seamless with the screen around it.
struct SurfaceBackground: View {
    @Environment(\.palette) private var palette

    var body: some View {
        if let grain = palette.grainSurface {
            PatternFill(color: grain)
                .ignoresSafeArea()
                .accessibilityHidden(true)
        } else if let backdrop = palette.backdropImage {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                Image(uiImage: backdrop)
                    .resizable()
                    .frame(width: Backdrop.side, height: Backdrop.side)
                    .offset(x: -frame.minX, y: -frame.minY)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .clipped()
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        } else {
            palette.backgroundColor.ignoresSafeArea()
        }
    }
}

/// Calm full-width message shown when a mode has nothing to show yet.
struct QuietMessage: View {
    @Environment(\.palette) private var palette
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(palette.inkSoftColor)
            Text(title)
                .font(.headline)
                .foregroundStyle(palette.inkColor)
            Text(detail)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.inkSoftColor)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
