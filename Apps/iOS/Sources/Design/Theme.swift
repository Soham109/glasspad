import SwiftUI
import UIKit

/// The looks Glasspad ships with. Paper is a soft warm white, Graphite a near black, System
/// follows the iPhone's light or dark appearance between those two. Mono is pure black and
/// white with no colour anywhere (it follows the iPhone too). Sand is a warm light beige and
/// Midnight a deep blue night.
enum ThemeChoice: String, CaseIterable, Identifiable, Sendable {
    case paper, graphite, system, mono, sand, midnight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: "Paper"
        case .graphite: "Graphite"
        case .system: "System"
        case .mono: "Mono"
        case .sand: "Sand"
        case .midnight: "Midnight"
        }
    }

    /// The window's appearance for this choice. System and Mono leave it unspecified, so the
    /// window follows the phone and SwiftUI's colour scheme reports the phone's real setting.
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .paper, .sand: .light
        case .graphite, .midnight: .dark
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
        return Palette(light: t, dark: t, isDark: dark, monochrome: self == .mono)
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
    /// The surface itself.
    let background: UIColor
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
    }

    private static func dynamic(_ light: UIColor, _ dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    init(isDark: Bool, monochrome: Bool, background: UIColor, raised: UIColor, raisedPressed: UIColor,
         line: UIColor, ink: UIColor, inkSoft: UIColor, dotBase: UIColor) {
        self.isDark = isDark
        self.monochrome = monochrome
        self.background = background
        self.raised = raised
        self.raisedPressed = raisedPressed
        self.line = line
        self.ink = ink
        self.inkSoft = inkSoft
        self.dotBase = dotBase
    }

    /// Colours that follow the appearance they are drawn in, between `light` and `dark`.
    fileprivate init(light: Tokens, dark: Tokens, isDark: Bool, monochrome: Bool) {
        let d = Palette.dynamic
        self.init(isDark: isDark, monochrome: monochrome,
                  background: d(light.background, dark.background), raised: d(light.raised, dark.raised),
                  raisedPressed: d(light.raisedPressed, dark.raisedPressed), line: d(light.line, dark.line),
                  ink: d(light.ink, dark.ink), inkSoft: d(light.inkSoft, dark.inkSoft), dotBase: d(light.dot, dark.dot))
    }

    private static let cache: [String: Palette] = {
        var all: [String: Palette] = [:]
        for theme in ThemeChoice.allCases {
            for dark in [false, true] {
                let t = theme.tokens
                all["\(theme.rawValue).\(dark)"] = Palette(light: t.light, dark: t.dark, isDark: dark,
                                                           monochrome: theme == .mono)
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

    var backgroundColor: Color { Color(uiColor: background) }
    var raisedColor: Color { Color(uiColor: raised) }
    var raisedPressedColor: Color { Color(uiColor: raisedPressed) }
    var lineColor: Color { Color(uiColor: line) }
    var inkColor: Color { Color(uiColor: ink) }
    var inkSoftColor: Color { Color(uiColor: inkSoft) }
    var colorScheme: ColorScheme { isDark ? .dark : .light }
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
struct WindowAppearance: UIViewRepresentable {
    let style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        view.isHidden = true
        return view
    }

    func updateUIView(_ view: Probe, context: Context) {
        view.style = style
        view.apply()
    }

    final class Probe: UIView {
        var style: UIUserInterfaceStyle = .unspecified

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        func apply() {
            guard let scene = window?.windowScene else { return }
            for window in scene.windows where window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
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
