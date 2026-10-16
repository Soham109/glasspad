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
        if prominent {
            styled(content)
                .tint(accent ?? palette.inkColor)
                .foregroundStyle(accent == nil ? palette.backgroundColor : Color.white)
        } else if let accent {
            styled(content).tint(accent)
        } else {
            styled(content)
        }
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
/// stretch into ovals. `accent` fills the key and turns the label white (an armed modifier,
/// the Next slide button).
struct KeyCapStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    var accent: Color? = nil
    var cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        configuration.label
            .foregroundStyle(accent == nil ? palette.inkColor : Color.white)
            .background {
                if let accent {
                    shape.fill(accent.opacity(configuration.isPressed ? 0.8 : 1))
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
