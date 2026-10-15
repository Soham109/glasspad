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

    func resolved(_ scheme: ColorScheme) -> Palette {
        switch self {
        case .paper: .paper
        case .graphite: .graphite
        case .system: scheme == .dark ? .graphite : .paper
        }
    }
}

/// Every colour the app draws with. Views never hard code colours; they read a palette.
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
    /// Finger dots on the trackpad (opacity already includes the user's setting).
    var dot: UIColor
    /// Finger dot diameter in points and look, from Settings.
    var dotDiameter: CGFloat = 44
    var dotStyle: DotStyle = .soft

    static let paper = Palette(
        isDark: false,
        background: UIColor(hex: 0xF2F1EE),
        raised: UIColor(hex: 0xFBFAF8),
        raisedPressed: UIColor(hex: 0xE6E4DF),
        line: UIColor(hex: 0x1A1A1A, alpha: 0.08),
        ink: UIColor(hex: 0x1A1A1A),
        inkSoft: UIColor(hex: 0x1A1A1A, alpha: 0.52),
        dot: UIColor(hex: 0x1A1A1A, alpha: 0.14)
    )

    static let graphite = Palette(
        isDark: true,
        background: UIColor(hex: 0x141414),
        raised: UIColor(hex: 0x1F1F1F),
        raisedPressed: UIColor(hex: 0x2C2C2C),
        line: UIColor(white: 1, alpha: 0.08),
        ink: UIColor(hex: 0xF2F1EE),
        inkSoft: UIColor(white: 1, alpha: 0.5),
        dot: UIColor(white: 1, alpha: 0.18)
    )

    /// The palette with the user's finger dot size, opacity and style applied.
    @MainActor
    func customized(_ settings: PhoneSettings) -> Palette {
        var p = self
        var alpha: CGFloat = 0
        p.dot.getWhite(nil, alpha: &alpha)
        p.dot = p.dot.withAlphaComponent(min(0.9, alpha * settings.dotOpacity))
        p.dotDiameter = settings.dotSize
        p.dotStyle = settings.dotStyle
        return p
    }

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

// MARK: - Environment

private struct PaletteKey: EnvironmentKey {
    static let defaultValue: Palette = .paper
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
