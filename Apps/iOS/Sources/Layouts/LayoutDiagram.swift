import GlasspadKit
import SwiftUI

/// A small drawing of a layout: a phone-shaped outline with each pane tinted in its mode's
/// colour and marked with its symbol, the way the real screen will split.
struct LayoutDiagram: View {
    @Environment(\.palette) private var palette
    let layout: ScreenLayout
    var landscape: Bool
    /// Hide the symbols (for very small drawings).
    var showsSymbols = true
    /// Pane titles under the symbols, for large drawings.
    var showsTitles = false

    /// The real screen's proportions (iPhone 18 Pro).
    static let aspect: CGFloat = 874.0 / 402.0

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let gap = max(1.5, min(size.width, size.height) * 0.035)
            let inset = gap
            let inner = CGSize(width: max(0, size.width - inset * 2), height: max(0, size.height - inset * 2))
            let corner = min(size.width, size.height) * 0.16
            let arrangement = layout.arrangement(in: inner, gap: gap)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(palette.inkColor.opacity(palette.isDark ? 0.10 : 0.07))
                ForEach(arrangement.panes, id: \.index) { pane in
                    let mode = layout.mode(at: pane.index)
                    PaneTile(mode: mode, size: pane.rect.size, cornerRadius: max(2, corner - inset),
                             showsSymbol: showsSymbols, showsTitle: showsTitles)
                        .offset(x: pane.rect.minX + inset, y: pane.rect.minY + inset)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .aspectRatio(landscape ? Self.aspect : 1 / Self.aspect, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(layout.paneSummary)
    }
}

/// One pane in a diagram.
struct PaneTile: View {
    @Environment(\.palette) private var palette
    let mode: AppMode
    let size: CGSize
    var cornerRadius: CGFloat
    var showsSymbol = true
    var showsTitle = false

    var body: some View {
        let accent = mode.accent(palette)
        let side = min(size.width, size.height)
        let shape = RoundedRectangle(cornerRadius: min(cornerRadius, side / 2), style: .continuous)
        ZStack {
            shape.fill(palette.raisedColor)
            shape.fill(accent.opacity(palette.isDark ? 0.22 : 0.13))
            shape.strokeBorder(accent.opacity(0.18), lineWidth: 0.5)
            if showsSymbol && side >= 14 {
                VStack(spacing: side * 0.06) {
                    Image(systemName: mode.symbol)
                        .font(.system(size: max(7, min(side * 0.34, 34)), weight: .semibold))
                        .foregroundStyle(accent)
                    if showsTitle && side >= 70 {
                        Text(mode.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(palette.inkColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(4)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
