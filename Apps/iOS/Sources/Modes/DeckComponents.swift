import SwiftUI
import GlasspadKit

// Tiles and the grid shared by Actions, Pinned folders, the Library and the editor.

// MARK: - Grid

/// How many columns and rows a tile covers.
private struct SpanKey: LayoutValueKey {
    static let defaultValue = DeckButtonSize.regular
}

extension View {
    func tileSpan(_ size: DeckButtonSize?) -> some View { layoutValue(key: SpanKey.self, value: size ?? .regular) }
}

/// A grid of square tiles sized from the space it is given (a full screen, half of it, or a
/// split-screen pane), never the screen. Regular tiles go in balanced, centred rows
/// (`TileGridMetrics`): 7 tiles are 4 + 3, 6 are 3 + 3. Wide and large tiles are packed in
/// reading order (`DeckGridPacking`) and the block is centred.
struct TileGrid: Layout {
    /// Tile side the grid aims for, before it fits the width.
    let preferred: CGFloat
    /// How much short rows may grow their tiles. Kept small so neighbouring grids on one
    /// screen look like one size.
    var maxGrowth: Double = 1.15

    static func preferred(scale: Double) -> CGFloat { 80 * CGFloat(scale) }

    private var spacing: CGFloat { preferred >= 70 ? 10 : 8 }

    struct Plan {
        let metrics: TileGridMetrics
        let frames: [CGRect]
        let size: CGSize
    }

    func plan(width: CGFloat, spans: [DeckButtonSize]) -> Plan {
        let w = Double(max(0, width))
        if spans.allSatisfy({ $0 == .regular }) {
            let m = TileGridMetrics.fit(count: spans.count, width: w, preferred: Double(preferred), spacing: Double(spacing),
                                           maxGrowth: maxGrowth)
            let frames = spans.indices.map { i -> CGRect in
                let o = m.origin(of: i)
                return CGRect(x: o.x, y: o.y, width: m.tile, height: m.tile)
            }
            return Plan(metrics: m, frames: frames, size: CGSize(width: width, height: m.height))
        }
        let m = TileGridMetrics.packed(width: w, preferred: Double(preferred), spacing: Double(spacing), maxGrowth: maxGrowth)
        let (cells, rows) = DeckGridPacking.place(spans.map { (columns: $0.span.columns, rows: $0.span.rows) }, columns: m.columns)
        let step = m.tile + m.spacing
        let left = ((w - m.rowWidth(m.columns)) / 2).rounded(.down)
        let frames = cells.map { c in
            CGRect(x: left + Double(c.column) * step, y: Double(c.row) * step,
                   width: Double(c.columns) * m.tile + Double(c.columns - 1) * m.spacing,
                   height: Double(c.rows) * m.tile + Double(c.rows - 1) * m.spacing)
        }
        let height = rows == 0 ? 0 : Double(rows) * m.tile + Double(rows - 1) * m.spacing
        return Plan(metrics: m, frames: frames, size: CGSize(width: width, height: height))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        plan(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 370, spans: subviews.map { $0[SpanKey.self] }).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let p = plan(width: bounds.width, spans: subviews.map { $0[SpanKey.self] })
        for (view, frame) in zip(subviews, p.frames) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }
}

// MARK: - Colours

extension Color {
    /// `#RRGGBB`, or nil.
    init?(hexString: String?) {
        guard var s = hexString?.trimmingCharacters(in: .whitespaces) else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }
}

// MARK: - Tiles

/// What a tile shows in its middle: an SF Symbol on a soft disc of the button's colour, an
/// app's own icon, or a website's logo.
struct TileFace: Equatable {
    var symbol: String
    var tint: Color
    var appIcon: UIImage? = nil
    var website: String? = nil
}

/// One tile: the raised surface with a hairline edge, its face in the middle and a short
/// label under it. Folders show their first four buttons, like folders on the Home Screen.
struct ActionTile: View {
    @Environment(\.palette) private var palette
    let title: String
    let face: TileFace
    var folder: [TileFace]? = nil
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

    var body: some View {
        Button(action: action) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                Group {
                    if size == .wide {
                        HStack(spacing: side * 0.14) {
                            glyph(side * 0.5)
                            if showsTitle { label(lines: 2, alignment: .leading) }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, side * 0.17)
                    } else {
                        VStack(spacing: side * 0.08) {
                            glyph(side * (size == .large ? 0.36 : (showsTitle ? 0.44 : 0.54)))
                            if showsTitle { label(lines: size == .large ? 1 : 2, alignment: .center) }
                        }
                        .padding(.horizontal, 6)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .background { background }
            .overlay(alignment: .topTrailing) { cornerMark }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(TileStyle())
        // Tile labels stop growing where they would no longer fit, like Home Screen labels.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .modifier(Jiggle(active: editing, seed: title))
    }

    private func label(lines: Int, alignment: TextAlignment) -> some View {
        Text(title)
            .font(size == .regular ? .caption.weight(.medium) : .subheadline.weight(.medium))
            .lineLimit(lines)
            .multilineTextAlignment(alignment)
            .minimumScaleFactor(0.8)
            .foregroundStyle(style == .outlined ? palette.inkSoftColor : palette.inkColor)
    }

    @ViewBuilder private func glyph(_ d: CGFloat) -> some View {
        ZStack {
            if let progress {
                Gauge(value: progress) { EmptyView() }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(palette.tint(face.tint))
                    .scaleEffect(d / 56)
            } else if pending {
                Circle().fill(disc(face.tint))
                ProgressView().tint(palette.inkColor)
            } else if style == .outlined {
                Image(systemName: face.symbol)
                    .font(.system(size: d * 0.5, weight: .regular))
                    .foregroundStyle(palette.inkSoftColor)
            } else if let folder {
                FolderFace(faces: folder, side: d * 1.12)
            } else {
                FaceView(face: face, diameter: d)
            }
        }
        .frame(width: d, height: d)
    }

    private func disc(_ tint: Color) -> Color { palette.tint(tint).opacity(palette.isDark ? 0.26 : 0.14) }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        switch style {
        case .filled:
            shape.fill(palette.raisedColor)
                .overlay(shape.strokeBorder(palette.lineColor, lineWidth: 1))
                .shadow(color: .black.opacity(palette.isDark ? 0 : 0.05), radius: 4, y: 2)
        case .outlined:
            shape.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(palette.inkSoftColor.opacity(0.45))
        }
    }

    @ViewBuilder private var cornerMark: some View {
        if editing {
            EmptyView() // Edit mode marks tiles with a remove button and a gentle wiggle, like the Home Screen.
        } else if succeeded {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(palette.tint(Color(uiColor: .systemGreen)))
                .padding(7)
                .transition(.scale.combined(with: .opacity))
        } else if let badge, folder == nil {
            Image(systemName: badge)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.inkSoftColor)
                .padding(8)
                .accessibilityHidden(true)
        }
    }
}

/// A face on its own: an app icon, a website logo, or a symbol on a soft disc.
struct FaceView: View {
    @Environment(\.palette) private var palette
    let face: TileFace
    let diameter: CGFloat

    var body: some View {
        if let icon = face.appIcon {
            // macOS icons leave a margin around the rounded square; draw them a little larger
            // so the visible icon matches the discs around it.
            Image(uiImage: icon)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: diameter * 1.2, height: diameter * 1.2)
                .saturation(palette.monochrome ? 0 : 1)
        } else if let link = face.website {
            WebsiteLogo(link: link, tint: face.tint, size: diameter * 0.9)
        } else {
            Circle()
                .fill(palette.tint(face.tint).opacity(palette.isDark ? 0.26 : 0.14))
                .overlay {
                    Image(systemName: UIImage(systemName: face.symbol) == nil ? "square.dashed" : face.symbol)
                        .font(.system(size: diameter * 0.44, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(palette.tint(face.tint))
                }
                .frame(width: diameter, height: diameter)
        }
    }
}

/// Up to four faces in a rounded square, the way a Home Screen folder shows its apps.
private struct FolderFace: View {
    @Environment(\.palette) private var palette
    let faces: [TileFace]
    let side: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.26, style: .continuous)
        let cell = side * 0.36, gap = side * 0.08
        shape.fill(palette.inkColor.opacity(palette.isDark ? 0.1 : 0.06))
            .overlay {
                if faces.isEmpty {
                    Image(systemName: "folder.fill")
                        .font(.system(size: side * 0.36, weight: .semibold))
                        .foregroundStyle(palette.inkSoftColor)
                } else {
                    VStack(spacing: gap) {
                        ForEach(0..<2, id: \.self) { row in
                            HStack(spacing: gap) {
                                ForEach(0..<2, id: \.self) { col in
                                    let i = row * 2 + col
                                    if i < faces.count {
                                        FaceView(face: faces[i], diameter: cell)
                                            .frame(width: cell, height: cell)
                                    } else {
                                        Color.clear.frame(width: cell, height: cell)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: side, height: side)
    }
}

/// The Home Screen wiggle in edit mode. Driven by the clock rather than a repeating
/// animation, so it always stops dead when editing ends and never gets stuck half way.
struct Jiggle: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let active: Bool
    let seed: String

    func body(content: Content) -> some View {
        let on = active && !reduceMotion
        // A stable offset per tile, so neighbours do not move in step.
        let phase = Double(seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }) / 0xFFFF * 2 * .pi
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !on)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            content.rotationEffect(.degrees(on ? sin(t * 2 * .pi * 3.2 + phase) * 1.5 : 0))
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
    var tint: Color { Color(hexString: color) ?? Color(uiColor: .systemOrange) }

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

    /// The tile face: the app's icon for Open App, the site's logo for a website, otherwise
    /// the symbol in the button's colour.
    @MainActor
    func face(icons: IconCache) -> TileFace {
        var face = TileFace(symbol: symbol, tint: tint)
        if case .openApp(let id) = action { face.appIcon = icons.image(for: id) }
        face.website = action.websiteLink
        return face
    }
}

extension MacroSummary {
    var tint: Color { rgb.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? Color(uiColor: .systemTeal) }
}
