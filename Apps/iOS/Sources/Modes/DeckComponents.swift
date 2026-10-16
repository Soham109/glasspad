import SwiftUI
import GlasspadKit

// Tiles and the packed grid shared by Actions and Deck.

/// Compact tile size for a width: whole columns, equal 8 pt gaps, no leftover space.
struct ActionGridMetrics: Equatable {
    let columns: Int
    let cell: CGFloat
    var cellHeight: CGFloat
    let spacing: CGFloat

    static let baseCell = 72.0

    static func fit(width: CGFloat, scale: Double) -> ActionGridMetrics {
        let spacing: CGFloat = 8
        let target = baseCell * CGFloat(scale)
        let columns = max(3, Int((width + spacing) / (target + spacing)))
        let cell = ((width - CGFloat(columns - 1) * spacing) / CGFloat(columns)).rounded(.down)
        return ActionGridMetrics(columns: columns, cell: cell, cellHeight: cell, spacing: spacing)
    }

    /// Tiles sized so these buttons fill `height` (see `DeckGridFit`); scrolls when they cannot.
    static func filling(_ sizes: [DeckButtonSize], width: CGFloat, height: CGFloat, scale: Double) -> ActionGridMetrics {
        let f = DeckGridFit.best(spans: sizes.map { (columns: $0.span.columns, rows: $0.span.rows) },
                                 width: Double(width), height: Double(height), maxCell: 112 * scale,
                                 fallbackCell: baseCell * scale)
        return ActionGridMetrics(columns: f.columns, cell: CGFloat(f.cellWidth).rounded(.down),
                                 cellHeight: CGFloat(f.cellHeight).rounded(.down), spacing: 8)
    }
}

/// How many columns and rows a tile covers.
private struct SpanKey: LayoutValueKey {
    static let defaultValue = DeckButtonSize.regular
}

extension View {
    func tileSpan(_ size: DeckButtonSize?) -> some View { layoutValue(key: SpanKey.self, value: size ?? .regular) }
}

/// Places square cells of mixed spans in reading order (`DeckGridPacking`).
struct PackedGrid: Layout {
    let metrics: ActionGridMetrics

    private func cells(_ subviews: Subviews) -> ([DeckGridPacking.Cell], Int) {
        let spans = subviews.map { $0[SpanKey.self].span }
        return DeckGridPacking.place(spans.map { (columns: $0.columns, rows: $0.rows) }, columns: metrics.columns)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (_, rows) = cells(subviews)
        let width = CGFloat(metrics.columns) * metrics.cell + CGFloat(metrics.columns - 1) * metrics.spacing
        let height = rows == 0 ? 0 : CGFloat(rows) * metrics.cellHeight + CGFloat(rows - 1) * metrics.spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (placed, _) = cells(subviews)
        let stepX = metrics.cell + metrics.spacing, stepY = metrics.cellHeight + metrics.spacing
        for (view, cell) in zip(subviews, placed) {
            let w = CGFloat(cell.columns) * metrics.cell + CGFloat(cell.columns - 1) * metrics.spacing
            let h = CGFloat(cell.rows) * metrics.cellHeight + CGFloat(cell.rows - 1) * metrics.spacing
            view.place(at: CGPoint(x: bounds.minX + CGFloat(cell.column) * stepX, y: bounds.minY + CGFloat(cell.row) * stepY),
                       proposal: ProposedViewSize(width: w, height: h))
        }
    }
}

extension Color {
    /// `#RRGGBB`, or nil.
    init?(hexString: String?) {
        guard var s = hexString?.trimmingCharacters(in: .whitespaces) else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }
}

/// One flat tile, like Control Center: the plain surface colour with a hairline edge, the
/// symbol (or the app's own icon) in the button's colour, a short label under it. No
/// gradients, no glow.
struct ActionTile: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let symbol: String
    let tint: Color
    var appIcon: UIImage? = nil
    var size: DeckButtonSize = .regular
    var showsTitle = true
    var badge: String? = nil
    var pending = false
    var succeeded = false
    var progress: Double? = nil
    var editing = false
    var style: Style = .filled
    let action: () -> Void

    enum Style { case filled, outlined }
    @State private var wiggle = false

    var body: some View {
        Button(action: action) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                VStack(spacing: side * 0.07) {
                    Spacer(minLength: 0)
                    glyph(side: side)
                    if showsTitle {
                        Text(title)
                            .font(size == .regular ? .caption2.weight(.semibold) : .footnote.weight(.semibold))
                            .lineLimit(size == .regular ? 2 : 1)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(palette.inkColor)
                            .padding(.horizontal, 4)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .background { background }
            .overlay(alignment: .topTrailing) { cornerMark }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(TileStyle())
        // Tile labels stop growing where they would no longer fit, like Home Screen labels.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .rotationEffect(.degrees(editing && wiggle && !reduceMotion ? 1.4 : 0))
        .onChange(of: editing, initial: true) { _, on in
            guard on, !reduceMotion else { wiggle = false; return }
            withAnimation(.easeInOut(duration: 0.13).repeatForever(autoreverses: true)) { wiggle = true }
        }
    }

    @ViewBuilder private func glyph(side: CGFloat) -> some View {
        ZStack {
            if let progress {
                Gauge(value: progress) { EmptyView() }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(tint)
                    .scaleEffect(0.5)
            } else if pending {
                ProgressView().tint(palette.inkColor)
            } else if let appIcon {
                Image(uiImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: side * (size == .large ? 0.36 : 0.5))
            } else {
                // Filled, like Control Center: one weight and one style for
                // every tile, whatever symbol the user picked.
                Image(systemName: UIImage(systemName: symbol) == nil ? "square.dashed" : symbol)
                    .font(.system(size: side * (size == .large ? 0.2 : 0.26), weight: .medium))
                    .symbolVariant(style == .outlined ? .none : .fill)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: succeeded)
            }
        }
        .frame(height: side * (size == .large ? 0.3 : 0.42))
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        switch style {
        case .filled:
            shape.fill(palette.raisedColor)
                .overlay(shape.strokeBorder(palette.lineColor, lineWidth: 1))
        case .outlined:
            shape.fill(palette.raisedColor)
                .overlay(shape.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(palette.lineColor.opacity(3)))
        }
    }

    @ViewBuilder private var cornerMark: some View {
        if editing {
            EmptyView() // Edit mode marks tiles with a remove button and a gentle wiggle, like the Home Screen.
        } else if succeeded {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(tint)
                .padding(6)
                .transition(.scale.combined(with: .opacity))
        } else if let badge {
            Image(systemName: badge)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.inkSoftColor)
                .padding(7)
                .accessibilityHidden(true)
        }
    }
}

/// A small section heading inside a page.
struct ActionSectionHeader: View {
    @Environment(\.palette) private var palette
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(palette.inkColor)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(palette.inkSoftColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

extension DeckButton {
    /// The tile colour, or the Actions accent.
    var tint: Color { Color(hexString: color) ?? AppMode.actions.accent(.paper) }

    /// Small corner badge saying what kind of button it is.
    var badge: String? {
        switch action {
        case .folder: "folder.fill"
        case .runMacro: "wand.and.stars"
        case .runShortcut: "square.stack.3d.up.fill"
        case .shellScript: "terminal.fill"
        default: nil
        }
    }
}

extension MacroSummary {
    var tint: Color { rgb.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? AppMode.macros.accent(.paper) }
}
