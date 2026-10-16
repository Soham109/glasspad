import SwiftUI
import GlasspadKit

/// Arrange, seen before it happens: the arrangements macOS offers in Window > Move & Resize
/// (and Split View in full screen) as a row of glyphs, then the display in miniature with each
/// window in its place. Tap a place for another window, swap or turn them, pick the display
/// when there are several, then the one button that says what will happen.
struct ArrangeSheet: View {
    /// The window to start with in the first place (Displays' Split With); the front one when nil.
    let startFirst: UInt32?
    /// One-tap Split Screen instead, for a Mac that cannot show its windows (none from Displays).
    let fallback: (() -> Void)?

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    var store = DisplaysStore.shared
    var session = MacSession.shared

    @State private var selection: ArrangeSelection?
    @State private var fellBack = false

    private var accent: Color { AppMode.displays.accent(palette) }
    private let change = Animation.snappy(duration: 0.28)

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                content(size: geo.size)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
            .background(SurfaceBackground())
            .navigationTitle("Arrange")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if #available(iOS 26.0, *) {
                        Button("Cancel", systemImage: "xmark", role: .close) { dismiss() }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .tint(palette.inkColor)
        .presentationDetents([.height(detentHeight)])
        .presentationDragIndicator(.hidden)
        .onAppear {
            store.watch(true)
            sync()
        }
        .onDisappear { store.watch(false) }
        .onChange(of: store.state) { sync() }
        .onChange(of: store.macTooOld) { _, old in if old { useFallback() } }
    }

    // MARK: Content

    @ViewBuilder private func content(size: CGSize) -> some View {
        if let state = store.state, let selection, let display = state.display(selection.display) {
            if size.width > size.height * 1.3 {
                HStack(alignment: .center, spacing: 20) {
                    preview(state, selection, display)
                    VStack(spacing: 16) {
                        if state.sheetArrangements.count > 1 { arrangements(state, selection) }
                        Spacer(minLength: 0)
                        if state.shownDisplays.count > 1 { displayPicker(state, selection) }
                        if !state.canArrangeWindows { MacPermissionBanner(compact: true) }
                        primaryButton(state, selection)
                    }
                    .frame(width: min(320, size.width * 0.4))
                }
            } else {
                VStack(spacing: 16) {
                    if state.sheetArrangements.count > 1 { arrangements(state, selection) }
                    if state.shownDisplays.count > 1 { displayPicker(state, selection) }
                    preview(state, selection, display)
                    if !state.canArrangeWindows { MacPermissionBanner(compact: true) }
                    primaryButton(state, selection)
                }
            }
        } else if let state = store.state, state.windows.count < 2, fallback == nil {
            QuietMessage(symbol: "rectangle.split.2x1", title: "Open a second window",
                         detail: "Arrange puts windows side by side.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The row of arrangements, drawn the way the Move & Resize menu draws them.
    private func arrangements(_ state: DisplaysState, _ s: ArrangeSelection) -> some View {
        HStack(spacing: 6) {
            ForEach(state.sheetArrangements, id: \.self) { a in
                let next = a == s.arrangement ? s : state.switching(s, to: a)
                ArrangementOption(arrangement: a, selected: a == s.arrangement, accent: accent) {
                    guard let next, a != s.arrangement else { return }
                    Haptics.shared.tap()
                    withAnimation(change) { selection = next }
                }
                .disabled(next == nil)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func displayPicker(_ state: DisplaysState, _ s: ArrangeSelection) -> some View {
        Picker("Display", selection: Binding(get: { s.display }, set: { id in
            Haptics.shared.tap()
            var next = s
            next.display = id
            next.displayPicked = true
            withAnimation(change) { selection = next }
        })) {
            ForEach(state.shownDisplays) { d in
                Text(d.isBuiltIn ? "Built-in" : d.name).tag(d.id)
            }
        }
        .pickerStyle(.segmented)
    }

    private func primaryButton(_ state: DisplaysState, _ s: ArrangeSelection) -> some View {
        Button {
            Haptics.shared.play(.click)
            store.arrange(s)
            dismiss()
        } label: {
            Text(s.arrangement.actionTitle).frame(maxWidth: .infinity)
        }
        .glassButton(prominent: true, accent: accent)
        .controlSize(.large)
        .disabled(!state.canArrangeWindows || state.commands(for: s) == nil)
    }

    // MARK: Picture

    private func preview(_ state: DisplaysState, _ s: ArrangeSelection, _ display: MacDisplay) -> some View {
        GeometryReader { geo in
            let map = DisplayMiniature(frames: [display.frame], fitting: geo.size, padding: 1)
            let screen = map.toView(display.frame)
            let places = state.arrangeFrames(for: s)?.map { map.toView($0) } ?? []
            ZStack(alignment: .topLeading) {
                DisplayTile(display: display, rect: screen, scale: map.scale, highlighted: false, windowCount: 0)
                    .accessibilityHidden(true)
                ForEach(Array(places.enumerated()), id: \.offset) { i, rect in
                    place(state, s, i, rect: rect, scale: map.scale)
                }
                if places.count > 1, s.windows.count > 1 {
                    // Between the places; for two stacked ones at the side, clear of their names.
                    let all = places.reduce(CGRect.null) { $0.union($1) }
                    let stacked = s.arrangement == .topAndBottom || s.arrangement == .bottomAndTop
                    turnButton(s).position(x: stacked ? all.maxX - 29 : all.midX, y: all.midY)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .aspectRatio(display.frame.width / max(1, display.frame.height), contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(change, value: display)
        .animation(change, value: s)
    }

    /// One place: the window that goes there. Tap for the list of windows.
    @ViewBuilder
    private func place(_ state: DisplaysState, _ s: ArrangeSelection, _ i: Int, rect: CGRect, scale: CGFloat) -> some View {
        let id = s.windows.indices.contains(i) ? s.windows[i] : nil
        let window = id.flatMap(state.window)
        let choices = state.arrangeChoices(for: i, in: s)
        let card = WindowPlaceCard(window: window, icon: window?.bundleID.flatMap { session.icons.image(for: $0) },
                                   size: rect.size, scale: scale, fullScreen: s.arrangement == .fullScreen)
        Group {
            if choices.isEmpty {
                card
            } else {
                Menu {
                    Picker(s.arrangement.placeName(i), selection: Binding(get: { id ?? 0 }, set: { new in
                        Haptics.shared.tap()
                        withAnimation(change) { selection = state.choosing(new, place: i, in: s) }
                    })) {
                        ForEach(choices) { w in
                            Label {
                                Text(w.appName)
                                if let title = w.title, !title.isEmpty, title != w.appName { Text(title) }
                            } icon: {
                                if let icon = w.bundleID.flatMap({ session.icons.image(for: $0) }) {
                                    Image(uiImage: icon)
                                } else {
                                    Image(systemName: "macwindow")
                                }
                            }
                            .tag(w.id)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    card
                }
                .buttonStyle(TileStyle())
            }
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .accessibilityLabel(s.arrangement.placeName(i))
        .accessibilityValue(window.map { w in w.title.map { $0.isEmpty || $0 == w.appName ? w.appName : "\(w.appName), \($0)" } ?? w.appName }
                            ?? "Empty")
        .accessibilityHint(choices.isEmpty ? "" : "Double tap to choose another window.")
    }

    /// Swaps two windows, or turns quarters one place clockwise.
    private func turnButton(_ s: ArrangeSelection) -> some View {
        let symbol = switch s.arrangement {
        case .topAndBottom, .bottomAndTop: "arrow.up.arrow.down"
        case .leftAndRight, .rightAndLeft, .fullScreen: "arrow.left.arrow.right"
        default: "arrow.clockwise"
        }
        return Button {
            Haptics.shared.tap()
            withAnimation(change) { selection = s.rotated }
        } label: {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.inkColor)
                .frame(width: 34, height: 34)
                .background(Circle().fill(palette.solidColor))
                .background(Circle().fill(palette.raisedColor))
                .overlay(Circle().strokeBorder(palette.lineColor, lineWidth: 1))
                .shadow(color: (palette.isDark ? palette.solidColor : palette.inkColor).opacity(0.18), radius: 4, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(TileStyle())
        .accessibilityLabel(s.windows.count == 2 ? "Swap" : "Turn")
    }

    // MARK: State

    /// Upright: the title bar, the arrangements, the picker, the display at full width, the button.
    private var detentHeight: CGFloat {
        let width = UIScreen.main.bounds.width - 32
        guard let state = store.state, let s = selection, let d = state.display(s.display), d.frame.height > 0 else { return 420 }
        let picture = width * d.frame.height / d.frame.width
        let row: CGFloat = state.sheetArrangements.count > 1 ? ArrangementOption.height + 16 : 0
        let picker: CGFloat = state.shownDisplays.count > 1 ? 32 + 16 : 0
        let banner: CGFloat = state.canArrangeWindows ? 0 : 76
        return 56 + 8 + row + picker + picture + 16 + banner + 50 + 16 + 4
    }

    /// Starts from the front window, then keeps the choice as windows come and go.
    private func sync() {
        guard let state = store.state else { return }
        var start: WindowArrangement = .leftAndRight
        #if DEBUG
        if let a = DisplaysDebug.arrangement, state.sheetArrangements.contains(a) { start = a }
        #endif
        let next = selection.flatMap { state.refreshed($0) } ?? state.defaultArrangement(start, first: startFirst)
            ?? state.defaultArrangement(.leftAndRight, first: startFirst)
        if next == nil, fallback != nil { return useFallback() }
        if next != selection { selection = next }
    }

    /// This Mac cannot show its windows: Split Screen as one tap, with the Mac's answer.
    private func useFallback() {
        guard !fellBack, let fallback else { return }
        fellBack = true
        dismiss()
        fallback()
    }
}

// MARK: - Arrangement row

/// One arrangement to choose: its glyph and its name, as macOS words it.
private struct ArrangementOption: View {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    let arrangement: WindowArrangement
    let selected: Bool
    let accent: Color
    let action: () -> Void

    static let height: CGFloat = 62

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button(action: action) {
            VStack(spacing: 5) {
                ArrangementGlyph(arrangement: arrangement, fill: selected ? accent : palette.inkSoftColor.opacity(0.55),
                                 outline: selected ? palette.inkColor : palette.inkSoftColor)
                    .frame(width: 40, height: 28)
                Text(arrangement.title)
                    .font(.caption2.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? palette.inkColor : palette.inkSoftColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .background {
                if selected {
                    shape.fill(palette.raisedColor).overlay(shape.strokeBorder(palette.lineColor, lineWidth: 1))
                }
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(TileStyle())
        .accessibilityLabel(arrangement.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// An arrangement drawn like the Move & Resize menu's icons: a display with its places filled.
/// Tiled windows sit on the desktop below the menu bar with a little space around them; Split
/// View fills the whole screen edge to edge.
struct ArrangementGlyph: View {
    let arrangement: WindowArrangement
    let fill: Color
    let outline: Color

    var body: some View {
        Canvas { context, size in
            let line: CGFloat = 1.3
            let screen = CGRect(origin: .zero, size: size).insetBy(dx: line / 2, dy: line / 2)
            let frame = Path(roundedRect: screen, cornerRadius: size.height * 0.16, style: .continuous)
            let full = arrangement == .fullScreen
            let bar = full ? 0 : size.height * 0.16
            let inset: CGFloat = full ? line : line + 1.6
            let area = CGRect(x: inset, y: inset + bar, width: size.width - inset * 2, height: size.height - inset * 2 - bar)
            // The slot math rounds to whole points, so it runs at ten times the glyph's size.
            let gap: CGFloat = full ? 1.2 : 1.6
            for (i, slot) in arrangement.slots.enumerated() {
                let r = DisplayGeometry.frame(of: slot, in: area.scaled(10), gap: (full ? 0 : gap) * 10).scaled(0.1)
                let pane = full ? r.insetBy(dx: gap / 2, dy: 0) : r
                context.fill(Path(roundedRect: pane, cornerRadius: full ? 0.8 : 1.4, style: .continuous),
                             with: .color(i == 0 ? fill : fill.opacity(0.7)))
            }
            if !full {
                var menuBar = context
                menuBar.clip(to: frame)
                menuBar.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: bar + line / 2)), with: .color(outline.opacity(0.3)))
            }
            context.stroke(frame, with: .color(outline), lineWidth: line)
        }
        .accessibilityHidden(true)
    }
}

private extension CGRect {
    func scaled(_ k: CGFloat) -> CGRect { CGRect(x: minX * k, y: minY * k, width: width * k, height: height * k) }
}

// MARK: - Window card

/// A window in its place: the frame and title bar macOS draws (none in full screen), the app's
/// icon, name and title. An empty place is a dashed outline.
private struct WindowPlaceCard: View {
    @Environment(\.palette) private var palette
    let window: MacWindow?
    let icon: UIImage?
    let size: CGSize
    let scale: CGFloat
    let fullScreen: Bool

    var body: some View {
        let corner = fullScreen ? 0 : min(max(4, 16 * scale), min(size.width, size.height) / 4)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        if window == nil {
            shape.strokeBorder(palette.inkColor.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: size.width, height: size.height)
        } else {
            let bar = fullScreen ? 0 : min(size.height * 0.16, max(10, 28 * scale))
            let shade = palette.isDark ? palette.solidColor : palette.inkColor
            ZStack(alignment: .top) {
                shape.fill(palette.solidColor)
                shape.fill(palette.raisedColor)
                if !fullScreen {
                    Rectangle()
                        .fill(palette.inkColor.opacity(0.05))
                        .frame(height: bar)
                    lights(bar)
                }
                label
                    .padding(.horizontal, 6)
                    .padding(.top, bar)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(palette.inkColor.opacity(fullScreen ? 0.3 : 0.18), lineWidth: 0.75))
            .frame(width: size.width, height: size.height)
            .shadow(color: shade.opacity(fullScreen ? 0 : 0.18), radius: 3, y: 1)
            .contentShape(shape)
        }
    }

    /// The close, minimize and zoom buttons.
    private func lights(_ bar: CGFloat) -> some View {
        let d = min(bar * 0.42, 7)
        return HStack(spacing: d * 0.6) {
            ForEach(0..<3, id: \.self) { _ in
                Circle().fill(palette.inkColor.opacity(0.2)).frame(width: d, height: d)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: bar, alignment: .leading)
        .padding(.leading, bar * 0.6)
    }

    private var label: some View {
        let side = min(min(size.width, size.height) * 0.3, 52)
        let roomy = size.height > 96
        return VStack(spacing: roomy ? 6 : 3) {
            Group {
                if let icon {
                    Image(uiImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "macwindow").resizable().scaledToFit().foregroundStyle(palette.inkSoftColor).padding(side * 0.12)
                }
            }
            .frame(width: side, height: side)
            if let window {
                VStack(spacing: 1) {
                    HStack(spacing: 3) {
                        Text(window.appName)
                            .font((roomy ? Font.subheadline : .caption).weight(.semibold))
                            .foregroundStyle(palette.inkColor)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.inkSoftColor)
                    }
                    // Always a line for the title, so the places line up.
                    let title = window.title.flatMap { $0.isEmpty || $0 == window.appName ? nil : $0 }
                    Text(title ?? " ")
                        .font(roomy ? .caption : .caption2)
                        .foregroundStyle(palette.inkSoftColor)
                        .accessibilityHidden(title == nil)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
    }
}
