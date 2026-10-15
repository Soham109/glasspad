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
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}
