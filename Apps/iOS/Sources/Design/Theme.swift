import SwiftUI
import UIKit

/// The looks Glasspad ships with. Paper is a soft warm white, Graphite a near black, System
/// follows the iPhone's light or dark appearance.
enum ThemeChoice: String, CaseIterable, Identifiable, Sendable {
    case paper, graphite, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: "Paper"
        case .graphite: "Graphite"
        case .system: "System"
        }
    }

    /// The window's appearance for this choice. System leaves it unspecified, so the window
    /// follows the phone and SwiftUI's colour scheme reports the phone's real setting.
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .paper: .light
        case .graphite: .dark
        case .system: .unspecified
        }
    }

    /// The palette for this choice. `scheme` is the phone's own setting, used only by System.
    /// Every colour in it is a semantic token that resolves against the light or dark
    /// appearance it is drawn in; the window appearance above makes that match the choice.
    func resolved(_ scheme: ColorScheme) -> Palette {
        switch self {
        case .paper: .themed(dark: false)
        case .graphite: .themed(dark: true)
        case .system: .themed(dark: scheme == .dark)
        }
    }
}

/// Every colour the app draws with. Views never hard code colours; they read a palette.
///
/// The app palette (`themed`) is made of semantic tokens: each colour carries its Paper value
/// and its Graphite value and picks one from the trait collection it is drawn in. So text,
/// symbols and UIKit-backed controls (menus, pickers, toggles) can never be left holding the
/// other theme's colour after a change. `paper` and `graphite` are fixed versions, used only
/// to preview a theme next to the other one.
struct Palette: Equatable, Sendable {
    let isDark: Bool
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

    private enum Tokens {
        static let background = (light: UIColor(hex: 0xF2F1EE), dark: UIColor(hex: 0x141414))
        static let raised = (light: UIColor(hex: 0xFBFAF8), dark: UIColor(hex: 0x1F1F1F))
        static let raisedPressed = (light: UIColor(hex: 0xE6E4DF), dark: UIColor(hex: 0x2C2C2C))
        static let line = (light: UIColor(hex: 0x1A1A1A, alpha: 0.08), dark: UIColor(white: 1, alpha: 0.1))
        static let ink = (light: UIColor(hex: 0x1A1A1A), dark: UIColor(hex: 0xF2F1EE))
        static let inkSoft = (light: UIColor(hex: 0x1A1A1A, alpha: 0.56), dark: UIColor(hex: 0xF2F1EE, alpha: 0.58))
        static let dot = (light: UIColor(hex: 0x1A1A1A, alpha: 0.14), dark: UIColor(white: 1, alpha: 0.18))
    }

    private static func dynamic(_ pair: (light: UIColor, dark: UIColor)) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? pair.dark : pair.light }
    }

    private static let themedLight = themedTokens(dark: false)
    private static let themedDark = themedTokens(dark: true)

    private static func themedTokens(dark: Bool) -> Palette {
        Palette(isDark: dark,
                background: dynamic(Tokens.background), raised: dynamic(Tokens.raised),
                raisedPressed: dynamic(Tokens.raisedPressed), line: dynamic(Tokens.line),
                ink: dynamic(Tokens.ink), inkSoft: dynamic(Tokens.inkSoft), dotBase: dynamic(Tokens.dot))
    }

    /// The app palette. `dark` only says which way the window currently looks; the colours
    /// themselves follow whatever appearance they are drawn in.
    static func themed(dark: Bool) -> Palette { dark ? themedDark : themedLight }

    /// Fixed Paper colours, for previews.
    static let paper = fixed(dark: false)
    /// Fixed Graphite colours, for previews.
    static let graphite = fixed(dark: true)

    private static func fixed(dark: Bool) -> Palette {
        func pick(_ pair: (light: UIColor, dark: UIColor)) -> UIColor { dark ? pair.dark : pair.light }
        return Palette(isDark: dark,
                       background: pick(Tokens.background), raised: pick(Tokens.raised),
                       raisedPressed: pick(Tokens.raisedPressed), line: pick(Tokens.line),
                       ink: pick(Tokens.ink), inkSoft: pick(Tokens.inkSoft), dotBase: pick(Tokens.dot))
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
