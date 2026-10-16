import SwiftUI
import GlasspadKit

/// The Mac's displays, drawn the way System Settings draws them (true sizes and places, the
/// menu bar and camera housing on the main one), with each window on them in front to back
/// order. Tap a window to bring it forward, drag it to move it, touch and hold for Move &
/// Resize. Tap a display for its settings.
struct DisplaysMode: View {
    /// Set when opened from the mode menu's tools: a close button leads the header.
    var onClose: (() -> Void)?

    @Environment(\.palette) private var palette
    @Environment(\.modeTopClearance) private var topClearance
    @Bindable var settings = PhoneSettings.shared
    var session = MacSession.shared
    var store = DisplaysStore.shared

    @State private var settingsFor: DisplayPick?
    @State private var closing: MacWindow?
    @State private var splitting: WindowPick?
    /// The window just picked, outlined in the drawing (and on the Mac) for a moment.
    @State private var lit: UInt32?
    @State private var litTask: Task<Void, Never>?

    static let hintID = "displays.hint"

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let wide = size.width > size.height * 1.15
            // Room for the mode pill: none as a tool, the pane's own in a layout.
            let pill = onClose == nil && topClearance == nil
            let top = topClearance ?? (pill && settings.pillPosition == .top ? (wide ? 44 : 60) : 12)
            let bottom: CGFloat = pill && settings.pillPosition == .bottom ? 72 : (wide ? 8 : 16)
            VStack(alignment: .leading, spacing: wide ? 8 : 16) {
                if size.height > 320 || onClose != nil { header(compact: wide) }
                content(wide: wide, height: size.height)
            }
            .padding(.horizontal, 16)
            .padding(.top, top)
            .padding(.bottom, bottom)
            .frame(width: size.width, height: size.height, alignment: .top)
        }
        .background(SurfaceBackground())
        .overlay(alignment: .bottom) {
            DisplaysNotices()
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .animation(.snappy(duration: 0.25), value: store.notice)
        .animation(.snappy(duration: 0.25), value: store.splitNotice)
        .animation(.snappy(duration: 0.25), value: store.state?.pending)
        .onAppear {
            store.watch(true)
            #if DEBUG
            DisplaysDebug.applyOnAppear { settingsFor = $0 } split: { splitting = $0 }
            #endif
        }
        .onDisappear { store.watch(false) }
        .confirmationDialog(closing.map { "Close \($0.label)?" } ?? "", isPresented: Binding(
            get: { closing != nil }, set: { if !$0 { closing = nil } }), titleVisibility: .visible, presenting: closing) { w in
            Button("Close Window", role: .destructive) { run(.close, w) }
        } message: { _ in
            Text("If it has unsaved changes, the app asks what to do.")
        }
        .sheet(item: $settingsFor) { pick in
            DisplaySettingsSheet(displayID: pick.id)
                .environment(\.palette, palette)
        }
        .sheet(item: $splitting) { pick in
            ArrangeSheet(startFirst: pick.id, fallback: nil)
                .environment(\.palette, palette)
        }
    }

    // MARK: Header

    private func header(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if let onClose {
                Button(action: onClose) { DisplaysGlyph(symbol: "xmark") }
                    .buttonStyle(TileStyle())
                    .accessibilityLabel("Close")
            }
            Text("Displays")
                .font(compact ? .title.bold() : .largeTitle.bold())
                .foregroundStyle(palette.inkColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let main = store.state?.shownDisplays.first(where: \.isMain) ?? store.state?.shownDisplays.first {
                Button {
                    Haptics.shared.tap()
                    settingsFor = DisplayPick(id: main.id)
                } label: {
                    DisplaysGlyph(symbol: "gearshape")
                }
                .buttonStyle(TileStyle())
                .accessibilityLabel("Display Settings")
                .accessibilityHint("Brightness, resolution, Night Shift and arrangement.")
            }
        }
    }

    // MARK: Content

    @ViewBuilder private func content(wide: Bool, height: CGFloat) -> some View {
        if !session.isConnected {
            ModeOfflineMessage(mode: .displays)
        } else if store.macTooOld {
            QuietMessage(symbol: "display.2", title: "Update Glasspad on your Mac",
                         detail: "Displays needs the latest Glasspad on \(session.macName ?? "your Mac").")
        } else if let state = store.state {
            if !state.canArrangeWindows { MacPermissionBanner(compact: true) }
            if wide {
                HStack(alignment: .top, spacing: 16) {
                    arrangement(state)
                    if height > 240 {
                        WindowList(state: state, run: run, close: { closing = $0 }, split: split, hint: showsHint)
                            .frame(width: 320)
                    }
                }
            } else if height < 460 {
                // A short pane: the arrangement alone.
                arrangement(state)
            } else {
                arrangement(state)
                    .frame(height: arrangementHeight(state, height: height))
                WindowList(state: state, run: run, close: { closing = $0 }, split: split, hint: showsHint)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The arrangement in its box, like System Settings > Displays.
    private func arrangement(_ state: DisplaysState) -> some View {
        DisplaysCanvas(state: state, lit: lit, run: run, close: { closing = $0 }, split: split) { display in
            Haptics.shared.tap()
            settingsFor = DisplayPick(id: display.id)
        }
        .padding(16)
        .displaysSurface(RoundedRectangle(cornerRadius: DisplaysMetrics.corner, style: .continuous))
    }

    /// Upright: as tall as the arrangement needs at full width, up to half the screen.
    private func arrangementHeight(_ state: DisplaysState, height: CGFloat) -> CGFloat {
        let union = state.shownDisplays.reduce(CGRect.null) { $0.union($1.frame) }
        let width = UIScreen.main.bounds.width - 32 - 32
        guard !union.isNull, union.width > 0 else { return 200 }
        let rooms = DisplaysCanvas.labelRooms(state.shownDisplays)
        let labels = rooms.top + rooms.bottom
        return min(height * 0.5, max(160, width * union.height / union.width + labels + 32 + 2))
    }

    /// Split With: the Arrange sheet, with this window first.
    private func split(_ w: MacWindow) {
        Haptics.shared.tap()
        splitting = WindowPick(id: w.id)
        if !settings.seenTips.contains(Self.hintID) { settings.seenTips.insert(Self.hintID) }
    }

    private func run(_ command: WindowCommand, _ w: MacWindow) {
        if command == .raise {
            Haptics.shared.tap()
            light(w)
        }
        store.run(command, on: w)
        if !settings.seenTips.contains(Self.hintID) { settings.seenTips.insert(Self.hintID) }
    }

    /// Outlines the window here and on the Mac for a moment, so it is clear which one it was.
    private func light(_ w: MacWindow) {
        store.highlight(w)
        withAnimation(.snappy(duration: 0.2)) { lit = w.id }
        litTask?.cancel()
        litTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { lit = nil }
        }
    }

    private var showsHint: Bool {
        guard store.state != nil, session.isConnected, !settings.seenTips.contains(Self.hintID) else { return false }
        #if DEBUG
        if FilmDirector.shared.active { return false }
        #endif
        return true
    }
}

/// Displays as a tool: full screen over the current mode.
struct DisplaysCover: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DisplaysMode { dismiss() }
            .persistentSystemOverlays(.hidden)
            .statusBarHidden(true)
    }
}

struct DisplayPick: Identifiable, Equatable {
    let id: UInt32
}

struct WindowPick: Identifiable, Equatable {
    let id: UInt32
}

/// One corner family for Displays and Arrange: cards, then the controls inside them.
enum DisplaysMetrics {
    static let corner: CGFloat = 24
    static let innerCorner: CGFloat = 12
}

/// A raised fill alone, as Apple draws grouped content; where that fill barely differs from
/// the surface (Mono, Pure Black, High Contrast) or with Increase Contrast, a hairline edge too.
struct DisplaysSurface<S: InsettableShape>: ViewModifier {
    @Environment(\.palette) private var palette
    @Environment(\.colorSchemeContrast) private var contrast
    let shape: S

    static func needsEdge(_ theme: ThemeChoice, contrast: ColorSchemeContrast) -> Bool {
        contrast == .increased || [.mono, .pureBlack, .highContrast].contains(theme)
    }

    func body(content: Content) -> some View {
        content
            .background(shape.fill(palette.raisedColor))
            .overlay { if Self.needsEdge(palette.theme, contrast: contrast) { shape.strokeBorder(palette.lineColor, lineWidth: 1) } }
    }
}

extension View {
    func displaysSurface<S: InsettableShape>(_ shape: S) -> some View { modifier(DisplaysSurface(shape: shape)) }
}

/// A round, icon-only button face, 44 points across.
struct DisplaysGlyph: View {
    @Environment(\.palette) private var palette
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(palette.inkColor)
            .frame(width: 44, height: 44)
            .displaysSurface(Circle())
            .contentShape(Circle())
    }
}

// MARK: - Canvas

/// The arrangement: displays at their true size and place, windows on top. Windows are drawn
/// once for the whole arrangement and cut to the displays, so one spanning two shows on both.
private struct DisplaysCanvas: View {
    @Environment(\.palette) private var palette
    let state: DisplaysState
    /// The window just picked: outlined in the accent colour.
    let lit: UInt32?
    let run: (WindowCommand, MacWindow) -> Void
    let close: (MacWindow) -> Void
    let split: (MacWindow) -> Void
    let onOpenDisplay: (MacDisplay) -> Void
    var session = MacSession.shared

    @State private var drag: WindowDrag?

    private struct WindowDrag: Equatable {
        var id: UInt32
        var translation: CGSize
        var location: CGPoint
    }

    /// Room above and below the arrangement for display names.
    static let labelRoom: CGFloat = 20

    /// A display's name goes under it, or above it when another display sits right below.
    static func nameAbove(_ d: MacDisplay, among displays: [MacDisplay]) -> Bool {
        displays.contains { o in
            o.id != d.id && abs(o.frame.minY - d.frame.maxY) < 1 && o.frame.minX < d.frame.maxX && o.frame.maxX > d.frame.minX
        }
    }

    /// Room for names above and below the arrangement (none for a single display).
    static func labelRooms(_ displays: [MacDisplay]) -> (top: CGFloat, bottom: CGFloat) {
        guard displays.count > 1 else { return (0, 0) }
        return (displays.contains { nameAbove($0, among: displays) } ? labelRoom : 0, labelRoom)
    }

    var body: some View {
        GeometryReader { geo in
            let displays = state.shownDisplays
            let labels = displays.count > 1
            let rooms = Self.labelRooms(displays)
            let room = rooms.top
            let map = DisplayMiniature(frames: displays.map(\.frame),
                                       fitting: CGSize(width: geo.size.width, height: geo.size.height - rooms.top - rooms.bottom), padding: 1)
            let place = { (r: CGRect) in map.toView(r).offsetBy(dx: 0, dy: room) }
            let target = drag.flatMap { dropTarget($0, map: map, room: room) }
            ZStack(alignment: .topLeading) {
                ForEach(displays) { d in
                    DisplayTile(display: d, rect: place(d.frame), scale: map.scale,
                                highlighted: target == d.id && drag.map { state.window($0.id).flatMap(state.display(of:))?.id != d.id } == true,
                                windowCount: windows(on: d).count)
                        .onTapGesture { onOpenDisplay(d) }
                }
                ZStack(alignment: .topLeading) {
                    ForEach(state.windows.reversed()) { w in
                        if w.id != drag?.id { chip(w, rect: place(w.frame), map: map, room: room) }
                    }
                }
                .mask {
                    ZStack(alignment: .topLeading) {
                        ForEach(displays) { d in
                            let r = place(d.frame)
                            Rectangle().frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
                        }
                    }
                }
                if labels { names(displays, place: place) }
                if let drag, let w = state.window(drag.id) {
                    chip(w, rect: place(w.frame).offsetBy(dx: drag.translation.width, dy: drag.translation.height),
                         map: map, room: room, lifted: true)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .coordinateSpace(name: Self.space)
        }
        .animation(.snappy(duration: 0.28), value: state.windows)
        .animation(.snappy(duration: 0.28), value: state.displays)
    }

    private static let space = "displays.canvas"

    private func windows(on d: MacDisplay) -> [MacWindow] {
        state.windows.filter { state.display(of: $0)?.id == d.id }
    }

    /// The display under the finger.
    private func dropTarget(_ drag: WindowDrag, map: DisplayMiniature, room: CGFloat) -> UInt32? {
        let displays = state.shownDisplays
        let point = map.toGlobal(CGPoint(x: drag.location.x, y: drag.location.y - room))
        return DisplayGeometry.displayIndex(at: point, in: displays.map(\.frame)).map { displays[$0].id }
    }

    // MARK: Windows

    private func chip(_ w: MacWindow, rect: CGRect, map: DisplayMiniature, room: CGFloat, lifted: Bool = false) -> some View {
        WindowChip(window: w, size: rect.size, scale: map.scale, icon: w.bundleID.flatMap { session.icons.image(for: $0) },
                   front: state.windows.first?.id == w.id, lifted: lifted, lit: lit == w.id)
            .position(x: rect.midX, y: rect.midY)
            .onTapGesture { run(.raise, w) }
            .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
                .onChanged { v in drag = WindowDrag(id: w.id, translation: v.translation, location: v.location) }
                .onEnded { v in drop(w, at: v.location, translation: v.translation, map: map, room: room) })
            .contextMenu { WindowMenu(window: w, state: state, run: { run($0, w) }, close: { close(w) }, split: { split(w) }) } preview: { WindowPreview(window: w, icon: w.bundleID.flatMap { session.icons.image(for: $0) }) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.spokenName(of: w))
            .accessibilityHint("Double tap to bring it forward.")
            .accessibilityAddTraits(.isButton)
            .accessibilityActions {
                ForEach(WindowTile.allCases, id: \.self) { tile in
                    Button(tile.title) { run(.tile(tile), w) }
                }
            }
    }

    private func drop(_ w: MacWindow, at location: CGPoint, translation: CGSize, map: DisplayMiniature, room: CGFloat) {
        defer { drag = nil }
        guard let target = dropTarget(WindowDrag(id: w.id, translation: translation, location: location), map: map, room: room),
              hypot(translation.width, translation.height) > 4 else { return }
        if target == state.display(of: w)?.id {
            let start = map.toView(w.frame.origin)
            let origin = map.toGlobal(CGPoint(x: start.x + translation.width, y: start.y + translation.height))
            run(.move(display: target, origin: origin), w)
        } else {
            run(.move(display: target, origin: nil), w)
        }
    }

    // MARK: Names

    /// Each display's name under it, or above it when another display is right below.
    private func names(_ displays: [MacDisplay], place: (CGRect) -> CGRect) -> some View {
        let rects = displays.map { place($0.frame) }
        return ForEach(Array(displays.enumerated()), id: \.element.id) { i, d in
            let r = rects[i]
            let blocked = Self.nameAbove(d, among: displays)
            Text(d.shortName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(palette.inkSoftColor)
                .lineLimit(1)
                .frame(width: max(r.width, 40))
                // The room for names is fixed; VoiceOver reads them from the displays themselves.
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
                .position(x: r.midX, y: blocked ? r.minY - Self.labelRoom / 2 : r.maxY + Self.labelRoom / 2)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Window menu and list

/// Move & Resize for one window, as in the Mac's Window menu.
private struct WindowMenu: View {
    let window: MacWindow
    let state: DisplaysState
    let run: (WindowCommand) -> Void
    let close: () -> Void
    /// Split With: the Arrange sheet with this window first.
    let split: () -> Void

    var body: some View {
        Section {
            ForEach([WindowTile.leftHalf, .rightHalf, .topHalf, .bottomHalf], id: \.self) { tile in
                Button(tile.title, systemImage: tile.symbol) { run(.tile(tile)) }
            }
        }
        Section {
            Button(WindowTile.fill.title, systemImage: WindowTile.fill.symbol) { run(.tile(.fill)) }
            Button(WindowTile.center.title, systemImage: WindowTile.center.symbol) { run(.tile(.center)) }
            if state.windows.contains(where: { $0.id != window.id }) {
                Button("Split With…", systemImage: "rectangle.split.2x1", action: split)
            }
            let elsewhere = state.shownDisplays.filter { $0.id != state.display(of: window)?.id }
            if elsewhere.count == 1, let d = elsewhere.first {
                Button("Move to \(d.name)", systemImage: "display") { run(.move(display: d.id, origin: nil)) }
            } else if !elsewhere.isEmpty {
                Menu {
                    ForEach(elsewhere) { d in
                        Button(d.name) { run(.move(display: d.id, origin: nil)) }
                    }
                } label: {
                    Label("Move To", systemImage: "display")
                }
            }
        }
        Section {
            Button("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") { run(.fullScreen) }
            Button("Minimize", systemImage: "minus.rectangle") { run(.minimize) }
        }
        Section {
            Button("Close Window", systemImage: "xmark", role: .destructive, action: close)
        }
    }
}

/// Every window, front to back, for when a miniature is too small to aim at: tap to bring
/// one forward, touch and hold for Move & Resize.
private struct WindowList: View {
    @Environment(\.palette) private var palette
    let state: DisplaysState
    let run: (WindowCommand, MacWindow) -> Void
    let close: (MacWindow) -> Void
    let split: (MacWindow) -> Void
    let hint: Bool
    var session = MacSession.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(state.windows.enumerated()), id: \.element.id) { i, w in
                    if i > 0 { Rectangle().fill(palette.lineColor).frame(height: 0.5).padding(.leading, 60) }
                    row(w)
                }
            }
            .displaysSurface(RoundedRectangle(cornerRadius: DisplaysMetrics.corner, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: DisplaysMetrics.corner, style: .continuous))
            if hint {
                Text("Tap to bring forward. Drag to move. Hold for more.")
                    .font(.footnote)
                    .foregroundStyle(palette.inkSoftColor)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .animation(.snappy(duration: 0.28), value: state.windows.map(\.id))
    }

    private func row(_ w: MacWindow) -> some View {
        let icon = w.bundleID.flatMap { session.icons.image(for: $0) }
        return Button { run(.raise, w) } label: {
            HStack(spacing: 12) {
                Group {
                    if let icon {
                        Image(uiImage: icon).resizable().interpolation(.high)
                    } else {
                        Image(systemName: "macwindow").font(.title3).foregroundStyle(palette.inkSoftColor)
                    }
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(w.appName)
                        .font(.body)
                        .foregroundStyle(palette.inkColor)
                    // Only when the app has other windows: which one this is.
                    if let detail = state.distinction(of: w) {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(palette.inkSoftColor)
                            .truncationMode(.middle)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { WindowMenu(window: w, state: state, run: { run($0, w) }, close: { close(w) }, split: { split(w) }) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.spokenName(of: w))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double tap to bring it forward.")
    }
}

// MARK: - Display tile

/// One display: its desktop, the menu bar and camera housing on the main one, a fine edge.
struct DisplayTile: View {
    @Environment(\.palette) private var palette
    let display: MacDisplay
    let rect: CGRect
    let scale: CGFloat
    /// A window is being dragged over it.
    let highlighted: Bool
    let windowCount: Int

    var body: some View {
        let corner = max(3, 10 * scale)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let accent = AppMode.displays.accent(palette)
        ZStack(alignment: .top) {
            shape.fill(palette.solidColor)
            shape.fill(palette.raisedPressedColor)
            shape.fill(LinearGradient(colors: [accent.opacity(palette.isDark ? 0.30 : 0.22), accent.opacity(0.06)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            if display.isMain { menuBar }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(highlighted ? accent : palette.inkColor.opacity(0.22), lineWidth: highlighted ? 2 : 1))
        .frame(width: rect.width, height: rect.height)
        .contentShape(shape)
        .position(x: rect.midX, y: rect.midY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(display.name)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Double tap for its settings.")
        .accessibilityAddTraits(.isButton)
    }

    /// As tall as the Mac's (taller around a camera housing), never thinner than a hairline.
    private var menuBar: some View {
        let height = max(2.5, max(display.menuBarHeight, 24) * scale)
        return ZStack(alignment: .top) {
            Rectangle().fill(palette.raisedColor.opacity(0.92))
                .overlay(alignment: .bottom) { Rectangle().fill(palette.inkColor.opacity(0.12)).frame(height: 0.5) }
            if let notch = display.notchWidth, notch > 0 {
                UnevenRoundedRectangle(bottomLeadingRadius: height * 0.45, bottomTrailingRadius: height * 0.45, style: .continuous)
                    .fill(palette.isDark ? palette.solidColor : palette.inkColor)
                    .frame(width: max(4, notch * scale), height: height)
            }
        }
        .frame(height: height)
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if display.isMain { parts.append("Main display") }
        if let r = display.resolution { parts.append("Looks like \(r.width) by \(r.height)") }
        parts.append(windowCount == 1 ? "1 window" : "\(windowCount) windows")
        return parts.joined(separator: ", ")
    }
}

// MARK: - Window chip

/// A window in miniature: its frame and corners, a title bar, and the app's icon.
private struct WindowChip: View {
    @Environment(\.palette) private var palette
    let window: MacWindow
    let size: CGSize
    let scale: CGFloat
    let icon: UIImage?
    /// The Mac's front window, with the deeper shadow macOS gives it.
    let front: Bool
    let lifted: Bool
    /// Just picked: an accent outline, so it is clear which window it was.
    var lit = false

    var body: some View {
        let corner = min(max(2, 16 * scale), min(size.width, size.height) / 3)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let bar = min(size.height * 0.3, max(2, 28 * scale))
        let shade = palette.isDark ? palette.solidColor : palette.inkColor
        ZStack(alignment: .top) {
            // Opaque even where raised is frosted (the glass themes): windows hide what is behind.
            shape.fill(palette.solidColor)
            shape.fill(palette.raisedColor)
            Rectangle()
                .fill(palette.inkColor.opacity(0.05))
                .frame(height: bar)
            if bar >= 5, size.width >= 40 { lights(bar) }
            iconView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, bar)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(palette.inkColor.opacity(front || lifted ? 0.2 : 0.13), lineWidth: 0.75))
        .overlay { if lit { shape.strokeBorder(AppMode.displays.accent(palette), lineWidth: 2) } }
        .frame(width: max(size.width, 4), height: max(size.height, 4))
        .shadow(color: shade.opacity(lifted ? 0.35 : front ? 0.24 : 0.12), radius: lifted ? 10 : front ? 4 : 2, y: lifted ? 6 : 1)
        .scaleEffect(lifted ? 1.04 : 1)
        .contentShape(shape)
    }

    /// The close, minimize and zoom buttons, as small dots in the title bar.
    private func lights(_ bar: CGFloat) -> some View {
        let d = min(bar * 0.42, 6)
        return HStack(spacing: d * 0.6) {
            ForEach(0..<3, id: \.self) { _ in
                Circle().fill(palette.inkColor.opacity(0.2)).frame(width: d, height: d)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: bar, alignment: .leading)
        .padding(.leading, bar * 0.5)
    }

    @ViewBuilder private var iconView: some View {
        let side = min(min(size.width, size.height) * 0.5, 44)
        if side >= 9 {
            if let icon {
                Image(uiImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: side, height: side)
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: side * 0.6))
                    .foregroundStyle(palette.inkSoftColor)
            }
        }
    }
}

/// What a held window shows above its menu: the app, the window's name and size.
private struct WindowPreview: View {
    @Environment(\.palette) private var palette
    let window: MacWindow
    let icon: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(uiImage: icon).resizable().interpolation(.high).frame(width: 44, height: 44)
            } else {
                Image(systemName: "macwindow").font(.title).foregroundStyle(palette.inkSoftColor).frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(window.appName)
                    .font(.headline)
                    .foregroundStyle(palette.inkColor)
                if let title = window.title, !title.isEmpty, title != window.appName {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(palette.inkSoftColor)
                        .lineLimit(2)
                }
                Text("\(Int(window.frame.width)) × \(Int(window.frame.height))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.inkSoftColor)
            }
        }
        .padding(16)
        .frame(minWidth: 220, alignment: .leading)
        .background(palette.raisedColor)
    }
}

// MARK: - Notices

/// "Keep these display settings?" while a change waits, and why a command did not work.
struct DisplaysNotices: View {
    @Environment(\.palette) private var palette
    var store = DisplaysStore.shared

    var body: some View {
        VStack(spacing: 10) {
            if let split = store.splitNotice {
                Label(split.text, systemImage: split.ok ? "rectangle.split.2x1" : "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(palette.inkColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassCapsule()
                    .id(split.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let notice = store.notice {
                Text(notice)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(palette.inkColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassCapsule()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let pending = store.state?.pending, let deadline = store.pendingDeadline {
                keepCard(pending, deadline: deadline)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: 440)
    }

    private func keepCard(_ pending: PendingDisplayChange, deadline: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Keep these display settings?")
                    .font(.headline)
                    .foregroundStyle(palette.inkColor)
                Text(pending.summary)
                    .font(.subheadline)
                    .foregroundStyle(palette.inkSoftColor)
                    .fixedSize(horizontal: false, vertical: true)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, Int(deadline.timeIntervalSince(context.date).rounded(.up)))
                    Text(left == 1 ? "Reverting in 1 second." : "Reverting in \(left) seconds.")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(palette.inkSoftColor)
                        .contentTransition(.numericText(countsDown: true))
                }
            }
            HStack(spacing: 10) {
                Button {
                    store.run(.revertChanges)
                } label: {
                    Text("Revert").frame(maxWidth: .infinity)
                }
                .glassButton()
                Button {
                    store.run(.keepChanges)
                } label: {
                    Text("Keep").frame(maxWidth: .infinity)
                }
                .glassButton(prominent: true, accent: AppMode.displays.accent(palette))
            }
            .controlSize(.large)
        }
        .padding(16)
        .glassPanel(cornerRadius: 24)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
/// Debug launch arguments for screenshots:
///   -GPDisplaysDemo <one|two|three|many>  another sample arrangement (with -GPDemo)
///   -GPDisplaysPending                    a change waiting for Keep
///   -GPDisplaysSheet <main|2|...>         open a display's settings; -GPDisplaysArrange opens Arrange
///   -GPDisplaysSplit [arrangement]        open Arrange on the front window (leftAndRight, quarters...)
enum DisplaysDebug {
    @MainActor static var applied = false
    @MainActor static var openArrange = false
    /// The arrangement Arrange starts on.
    @MainActor static var arrangement: WindowArrangement?

    @MainActor static func applyOnAppear(open: (DisplayPick) -> Void, split: (WindowPick) -> Void) {
        guard !applied, MacSession.shared.isDemo else { return }
        applied = true
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if args.contains("-GPDisplaysDemo") || args.contains("-GPDisplaysPending") {
            DisplaysStore.shared.applyDemo(value("-GPDisplaysDemo"), pending: args.contains("-GPDisplaysPending"))
        }
        openArrange = args.contains("-GPDisplaysArrange")
        arrangement = value("-GPDisplaysSplit").flatMap(WindowArrangement.init(rawValue:))
        if args.contains("-GPDisplaysSplit"), let front = DisplaysStore.shared.state?.windows.first { split(WindowPick(id: front.id)) }
        if let which = value("-GPDisplaysSheet") ?? (openArrange ? "main" : nil) {
            let displays = DisplaysStore.shared.state?.shownDisplays ?? []
            let id = UInt32(which) ?? displays.first(where: \.isMain)?.id
            if let id { open(DisplayPick(id: id)) }
        }
    }
}
#endif
