import GlasspadKit
import SwiftUI
import UIKit

/// The looks Glasspad ships with. Paper is a soft warm white, Graphite a near black, System
/// follows the iPhone's light or dark appearance between those two. Mono is pure black and
/// white with no colour anywhere (it follows the iPhone too). Sand is a warm light beige and
/// Midnight a deep blue night. Glass and Glass Dark lay translucent, frosted surfaces over a
/// soft coloured backdrop, with the system's Liquid Glass on floating controls.
enum ThemeChoice: String, CaseIterable, Identifiable, Sendable {
    case paper, graphite, system, mono, sand, midnight, glass, glassDark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: "Paper"
        case .graphite: "Graphite"
        case .system: "System"
        case .mono: "Mono"
        case .sand: "Sand"
        case .midnight: "Midnight"
        case .glass: "Glass"
        case .glassDark: "Glass Dark"
        }
    }

    /// Translucent surfaces over a coloured backdrop.
    var isGlass: Bool { self == .glass || self == .glassDark }

    /// The window's appearance for this choice. System and Mono leave it unspecified, so the
    /// window follows the phone and SwiftUI's colour scheme reports the phone's real setting.
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .paper, .sand, .glass: .light
        case .graphite, .midnight, .glassDark: .dark
        case .system, .mono: .unspecified
        }
    }

    /// The colours for each appearance. A theme that forces one appearance uses its colours
    /// for both, so nothing can resolve to another theme's colour.
    fileprivate var tokens: (light: Palette.Tokens, dark: Palette.Tokens) {
        switch self {
        case .paper, .graphite, .system: (.paper, .graphite)
        case .mono: (.monoLight, .monoDark)
        case .sand: (.sand, .sand)
        case .midnight: (.midnight, .midnight)
        case .glass: (.glassLight, .glassLight)
        case .glassDark: (.glassDark, .glassDark)
        }
    }

    /// The palette for this choice. `scheme` is the phone's own setting, used by System and
    /// Mono. Every colour in it is a semantic token that resolves against the light or dark
    /// appearance it is drawn in; the window appearance above makes that match the choice.
    func resolved(_ scheme: ColorScheme) -> Palette {
        let dark: Bool = switch interfaceStyle {
        case .light: false
        case .dark: true
        default: scheme == .dark
        }
        return Palette.themed(self, dark: dark)
    }

    /// Fixed colours of this theme in one appearance, for the previews in Settings.
    func preview(dark: Bool) -> Palette {
        let t = dark ? tokens.dark : tokens.light
        return Palette(light: t, dark: t, isDark: dark, monochrome: self == .mono, glass: isGlass)
    }
}

/// Every colour the app draws with. Views never hard code colours; they read a palette.
///
/// The app palette (`themed`) is made of semantic tokens: each colour carries its light value
/// and its dark value and picks one from the trait collection it is drawn in. So text,
/// symbols and UIKit-backed controls (menus, pickers, toggles) can never be left holding the
/// other appearance's colour after a change. `paper` and `graphite` are fixed versions, used
/// only to preview a theme next to another one.
struct Palette: Equatable, Sendable {
    let isDark: Bool
    /// Mono: no colour anywhere. Tiles, symbols and accents all draw in the ink.
    let monochrome: Bool
    /// Glass themes: the surface is a soft coloured backdrop and raised things are frosted
    /// and translucent. Floating controls use the system's Liquid Glass.
    var glass: Bool = false
    /// The surface itself. In the glass themes this is a soft gradient (a pattern colour), so
    /// use it only to fill an area, never for text or symbols; those take `solid`.
    let background: UIColor
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

    /// One theme's colours in one appearance.
    struct Tokens: Sendable {
        let background, raised, raisedPressed, line, ink, inkSoft, dot: UIColor
        /// A plain colour standing in for the surface where a pattern cannot go (text on an
        /// ink filled button). The surface itself for every theme but the glass ones.
        var solid: UIColor? = nil

        static let paper = Tokens(background: UIColor(hex: 0xF2F1EE), raised: UIColor(hex: 0xFBFAF8),
                                  raisedPressed: UIColor(hex: 0xE6E4DF), line: UIColor(hex: 0x1A1A1A, alpha: 0.08),
                                  ink: UIColor(hex: 0x1A1A1A), inkSoft: UIColor(hex: 0x1A1A1A, alpha: 0.56),
                                  dot: UIColor(hex: 0x1A1A1A, alpha: 0.14))
        static let graphite = Tokens(background: UIColor(hex: 0x141414), raised: UIColor(hex: 0x1F1F1F),
                                     raisedPressed: UIColor(hex: 0x2C2C2C), line: UIColor(white: 1, alpha: 0.1),
                                     ink: UIColor(hex: 0xF2F1EE), inkSoft: UIColor(hex: 0xF2F1EE, alpha: 0.58),
                                     dot: UIColor(white: 1, alpha: 0.18))
        static let monoLight = Tokens(background: UIColor(hex: 0xFFFFFF), raised: UIColor(hex: 0xF4F4F4),
                                      raisedPressed: UIColor(hex: 0xE4E4E4), line: UIColor(white: 0, alpha: 0.1),
                                      ink: UIColor(hex: 0x000000), inkSoft: UIColor(white: 0, alpha: 0.55),
                                      dot: UIColor(white: 0, alpha: 0.14))
        static let monoDark = Tokens(background: UIColor(hex: 0x000000), raised: UIColor(hex: 0x141414),
                                     raisedPressed: UIColor(hex: 0x262626), line: UIColor(white: 1, alpha: 0.14),
                                     ink: UIColor(hex: 0xFFFFFF), inkSoft: UIColor(white: 1, alpha: 0.58),
                                     dot: UIColor(white: 1, alpha: 0.2))
        static let sand = Tokens(background: UIColor(hex: 0xECE4D6), raised: UIColor(hex: 0xF7F2E9),
                                 raisedPressed: UIColor(hex: 0xDFD4C2), line: UIColor(hex: 0x3B2F22, alpha: 0.1),
                                 ink: UIColor(hex: 0x2E261D), inkSoft: UIColor(hex: 0x2E261D, alpha: 0.58),
                                 dot: UIColor(hex: 0x3B2F22, alpha: 0.16))
        static let midnight = Tokens(background: UIColor(hex: 0x0B111D), raised: UIColor(hex: 0x151D2D),
                                     raisedPressed: UIColor(hex: 0x1F2A3F), line: UIColor(hex: 0xA9BCE6, alpha: 0.13),
                                     ink: UIColor(hex: 0xE8EDF7), inkSoft: UIColor(hex: 0xE8EDF7, alpha: 0.6),
                                     dot: UIColor(hex: 0xC4D3F5, alpha: 0.2))
        static let glassLight = Tokens(background: Backdrop.light.color, raised: UIColor(white: 1, alpha: 0.52),
                                       raisedPressed: UIColor(white: 1, alpha: 0.3), line: UIColor(white: 1, alpha: 0.7),
                                       ink: UIColor(hex: 0x11141C), inkSoft: UIColor(hex: 0x11141C, alpha: 0.56),
                                       dot: UIColor(hex: 0x11141C, alpha: 0.14), solid: UIColor(hex: 0xEEF0F7))
        static let glassDark = Tokens(background: Backdrop.dark.color, raised: UIColor(white: 1, alpha: 0.085),
                                      raisedPressed: UIColor(white: 1, alpha: 0.16), line: UIColor(white: 1, alpha: 0.12),
                                      ink: UIColor(hex: 0xF3F4F9), inkSoft: UIColor(hex: 0xF3F4F9, alpha: 0.6),
                                      dot: UIColor(white: 1, alpha: 0.2), solid: UIColor(hex: 0x10121C))
    }

    private static func dynamic(_ light: UIColor, _ dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    init(isDark: Bool, monochrome: Bool, glass: Bool = false, background: UIColor, solid: UIColor? = nil,
         raised: UIColor, raisedPressed: UIColor, line: UIColor, ink: UIColor, inkSoft: UIColor, dotBase: UIColor) {
        self.isDark = isDark
        self.monochrome = monochrome
        self.glass = glass
        self.background = background
        self.solid = solid ?? background
        self.raised = raised
        self.raisedPressed = raisedPressed
        self.line = line
        self.ink = ink
        self.inkSoft = inkSoft
        self.dotBase = dotBase
    }

    /// Colours that follow the appearance they are drawn in, between `light` and `dark`.
    fileprivate init(light: Tokens, dark: Tokens, isDark: Bool, monochrome: Bool, glass: Bool = false) {
        let d = Palette.dynamic
        self.init(isDark: isDark, monochrome: monochrome, glass: glass,
                  background: d(light.background, dark.background),
                  solid: d(light.solid ?? light.background, dark.solid ?? dark.background), raised: d(light.raised, dark.raised),
                  raisedPressed: d(light.raisedPressed, dark.raisedPressed), line: d(light.line, dark.line),
                  ink: d(light.ink, dark.ink), inkSoft: d(light.inkSoft, dark.inkSoft), dotBase: d(light.dot, dark.dot))
    }

    private static let cache: [String: Palette] = {
        var all: [String: Palette] = [:]
        for theme in ThemeChoice.allCases {
            for dark in [false, true] {
                let t = theme.tokens
                all["\(theme.rawValue).\(dark)"] = Palette(light: t.light, dark: t.dark, isDark: dark,
                                                           monochrome: theme == .mono, glass: theme.isGlass)
            }
        }
        return all
    }()

    /// The app palette for a theme. `dark` only says which way the window currently looks;
    /// the colours themselves follow whatever appearance they are drawn in.
    static func themed(_ theme: ThemeChoice = .paper, dark: Bool) -> Palette {
        cache["\(theme.rawValue).\(dark)"]!
    }

    /// Fixed Paper colours, for previews.
    static let paper = ThemeChoice.paper.preview(dark: false)
    /// Fixed Graphite colours, for previews.
    static let graphite = ThemeChoice.graphite.preview(dark: true)

    /// A colour the user or a mode chose, or the ink in Mono. Colours too close to the
    /// surface to read (dark grey on Graphite, yellow on Paper) are moved toward the ink.
    func tint(_ color: Color) -> Color {
        if monochrome { return inkColor }
        let c = UIColor(color).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard c.getRed(&r, green: &g, blue: &b, alpha: &a) else { return color }
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if isDark && luminance < 0.42 { return Color(uiColor: c.mixed(with: .white, amount: 0.45)) }
        if !isDark && luminance > 0.72 { return Color(uiColor: c.mixed(with: .black, amount: 0.22)) }
        return color
    }

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

    /// The surface as a SwiftUI colour. Clear in the glass themes: SwiftUI cannot draw a
    /// pattern, so the window draws the backdrop behind everything (see `WindowAppearance`) and
    /// views that must hide what is under them use `SurfaceBackground`.
    var backgroundColor: Color { glass ? .clear : Color(uiColor: background) }
    /// A sunken area inside a raised card (a text preview): the surface, or in the glass
    /// themes a deeper frost.
    var wellColor: Color { glass ? raisedPressedColor : backgroundColor }
    /// The surface as a plain colour: text and symbols on an ink filled button.
    var solidColor: Color { Color(uiColor: solid) }
    var raisedColor: Color { Color(uiColor: raised) }
    var raisedPressedColor: Color { Color(uiColor: raisedPressed) }
    var lineColor: Color { Color(uiColor: line) }
    var inkColor: Color { Color(uiColor: ink) }
    var inkSoftColor: Color { Color(uiColor: inkSoft) }
    var colorScheme: ColorScheme { isDark ? .dark : .light }

    // Status colours. Mono keeps them out of colour: good is the ink, waiting is the soft
    // ink, and a problem is the ink too (the symbol beside it says which).

    /// Connected, passed, done.
    var good: Color { monochrome ? inkColor : Color(uiColor: .systemGreen) }
    /// Waiting or needs a look.
    var caution: Color { monochrome ? inkSoftColor : Color(uiColor: .systemOrange) }
    /// Failed or recording.
    var bad: Color { monochrome ? inkColor : Color(uiColor: .systemRed) }

    /// The connection dot: good when connected, caution while looking, bad on failure, and a
    /// quiet grey when idle or another iPhone has the Mac. In Mono the dot keeps its meaning
    /// through brightness and its pulse while looking.
    func linkColor(_ state: LinkState) -> Color {
        switch state {
        case .connected: good
        case .searching, .connecting: caution
        case .failed where state.isReplaced: monochrome ? inkSoftColor : Color(uiColor: .systemGray)
        case .failed: bad
        case .idle: monochrome ? inkSoftColor : Color(uiColor: .systemGray)
        }
    }
}

// MARK: - Glass backdrop

/// The soft coloured backdrop behind the glass themes: a few large, blurred pools of colour
/// on a pale (or deep) base. It is drawn once into a square tile and used as a pattern colour,
/// so every screen, sheet and the trackpad that fills with the surface colour gets it with no
/// extra views. The pools sit symmetrically about the diagonal, so portrait and landscape crops
/// of the tile look alike.
enum Backdrop {
    case light, dark

    /// Side of the square tile, in points. Larger than any iPhone screen, so it never repeats.
    static let side: CGFloat = 1100

    var color: UIColor { UIColor(patternImage: image) }

    var image: UIImage {
        switch self {
        case .light: Self.lightImage
        case .dark: Self.darkImage
        }
    }

    private static let lightImage = render(base: UIColor(hex: 0xEDEFF6), pools: [
        (CGPoint(x: 0.05, y: 0.05), 0.55, UIColor(hex: 0xB9CFFF)),
        (CGPoint(x: 0.36, y: 0.36), 0.42, UIColor(hex: 0xE3D3FF)),
        (CGPoint(x: 0.12, y: 0.62), 0.42, UIColor(hex: 0xFFDCCB)),
        (CGPoint(x: 0.62, y: 0.12), 0.42, UIColor(hex: 0xFFDCCB)),
        (CGPoint(x: 0.0, y: 0.92), 0.4, UIColor(hex: 0xC6EBE4)),
        (CGPoint(x: 0.92, y: 0.0), 0.4, UIColor(hex: 0xC6EBE4)),
    ])

    private static let darkImage = render(base: UIColor(hex: 0x0B0D16), pools: [
        (CGPoint(x: 0.05, y: 0.05), 0.55, UIColor(hex: 0x2B3A8C)),
        (CGPoint(x: 0.36, y: 0.36), 0.4, UIColor(hex: 0x4A2A78)),
        (CGPoint(x: 0.12, y: 0.66), 0.42, UIColor(hex: 0x0E5560)),
        (CGPoint(x: 0.66, y: 0.12), 0.42, UIColor(hex: 0x0E5560)),
        (CGPoint(x: 0.0, y: 0.95), 0.36, UIColor(hex: 0x5A2050)),
        (CGPoint(x: 0.95, y: 0.0), 0.36, UIColor(hex: 0x5A2050)),
    ])

    /// Each pool is a centre (as a fraction of the tile), a radius (fraction) and a colour.
    private static func render(base: UIColor, pools: [(CGPoint, CGFloat, UIColor)]) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            base.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let space = CGColorSpaceCreateDeviceRGB()
            for (center, radius, color) in pools {
                let c = CGPoint(x: center.x * side, y: center.y * side)
                let colors = [color.withAlphaComponent(0.85).cgColor, color.withAlphaComponent(0.4).cgColor,
                              color.withAlphaComponent(0).cgColor] as CFArray
                guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.45, 1]) else { continue }
                ctx.cgContext.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c,
                                                 endRadius: radius * side, options: [])
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
        if palette.glass {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                Image(uiImage: (palette.isDark ? Backdrop.dark : Backdrop.light).image)
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
