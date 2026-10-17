import GlasspadKit
import SwiftUI

/// Liquid Glass on iOS 26 and later, the closest system material before that.
/// Glass is used only for controls that float above content (the mode pill, mode
/// buttons), never for the trackpad surface itself.
extension View {
    /// Glass in a capsule, for small floating controls.
    @ViewBuilder
    func glassCapsule(interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: .capsule)
        } else {
            background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        }
    }

    /// Glass in a rounded rectangle, for floating panels.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 28, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular,
                        in: .rect(cornerRadius: cornerRadius, style: .continuous))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        }
    }

    /// Groups nearby glass shapes so they blend and morph together on iOS 26.
    @ViewBuilder
    func glassGroup(spacing: CGFloat = 20) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    /// The standard glass button look on iOS 26, bordered before that.
    ///
    /// A prominent button is filled. With an `accent` it is that colour with white text, like
    /// any tinted system button. Without one it is filled with the theme's ink and its label
    /// takes the surface colour, so it reads in both themes (white ink on Graphite gets dark text).
    func glassButton(prominent: Bool = false, accent: Color? = nil) -> some View {
        modifier(GlassButtonStyle(prominent: prominent, accent: accent))
    }
}

private struct GlassButtonStyle: ViewModifier {
    @Environment(\.palette) private var palette
    let prominent: Bool
    let accent: Color?

    func body(content: Content) -> some View {
        // Mono has no colours: an accent becomes the ink, with the surface colour on it.
        let accent = palette.monochrome ? nil : self.accent
        if prominent {
            styled(content)
                .tint(accent ?? palette.inkColor)
                .foregroundStyle(accent.map(Self.label(on:)) ?? palette.solidColor)
        } else if let accent {
            styled(content).tint(accent)
        } else {
            styled(content)
        }
    }

    /// White on dark accents, near black on light ones (bright teal, yellow, mint), whichever
    /// reads better (`RGBA.labelOnFill`, checked in ThemeContrastTests).
    static func label(on accent: Color) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(accent).resolvedColor(with: UITraitCollection.current).getRed(&r, green: &g, blue: &b, alpha: &a)
        let label = RGBA(r: Double(r), g: Double(g), b: Double(b)).labelOnFill
        return Color(red: label.r, green: label.g, blue: label.b)
    }

    @ViewBuilder private func styled(_ content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { content.buttonStyle(.glassProminent) } else { content.buttonStyle(.glass) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
        }
    }
}

/// A flat key, like the system keyboard: a filled rounded rectangle with a hairline edge that
/// darkens while pressed. Used for keys and big remote buttons, where glass capsules would
/// stretch into ovals. `accent` fills the key and turns the label white (an armed modifier).
/// `prominent` fills it with the ink instead, the label taking the surface colour, like a
/// primary button (the Next slide button).
struct KeyCapStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    var accent: Color? = nil
    var prominent = false
    var cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if prominent {
            configuration.label
                .foregroundStyle(palette.solidColor)
                .background(shape.fill(palette.inkColor.opacity(configuration.isPressed ? 0.82 : 1)))
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.4)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        } else {
            keyCap(configuration, shape: shape)
        }
    }

    private func keyCap(_ configuration: Configuration, shape: RoundedRectangle) -> some View {
        // Mono fills an armed key with the ink and puts the surface colour on it.
        let fill = accent.map { palette.tint($0) }
        return configuration.label
            .foregroundStyle(accent == nil ? palette.inkColor : (palette.monochrome ? palette.solidColor : Color.white))
            .background {
                if let fill {
                    shape.fill(fill.opacity(configuration.isPressed ? 0.8 : 1))
                } else {
                    shape.fill(configuration.isPressed ? palette.raisedPressedColor : palette.raisedColor)
                }
            }
            .overlay { shape.strokeBorder(palette.lineColor, lineWidth: 1) }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
