import SwiftUI
import GlasspadKit

/// The small pill at the top centre. It shows the current mode, fades after 2 s, and comes
/// back when the top edge is touched. Tap it for the mode menu, long press for Settings.
/// The pill and the menu are one piece of glass: on iOS 26 the pill grows into the menu.
/// A small dot shows the connection only when something is wrong.
struct ModeSwitcher: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    var router = AppRouter.shared
    var session = MacSession.shared
    var settings = PhoneSettings.shared
    var store = PairingStore.shared

    @State private var visible = true
    @State private var expanded = false
    @State private var hideTask: Task<Void, Never>?
    @Namespace private var glass

    var body: some View {
        GeometryReader { geo in
            let bottom = settings.pillPosition == .bottom
            let edge = bottom ? geo.safeAreaInsets.bottom : geo.safeAreaInsets.top
            ZStack(alignment: bottom ? .bottom : .top) {
                if expanded {
                    // Tap anywhere else to close the menu.
                    Color.black.opacity(palette.isDark ? 0.35 : 0.12)
                        .ignoresSafeArea()
                        .onTapGesture { close() }
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }

                // Touching the pill's edge brings it back.
                if !visible && !expanded {
                    Color.clear
                        .frame(height: max(24, edge))
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in reveal() })
                        .ignoresSafeArea(edges: bottom ? .bottom : .top)
                        .accessibilityHidden(true)
                }

                VStack(spacing: 10) {
                    if bottom && showsHint { hint }
                    Group {
                        if expanded {
                            menu.transition(transition(bottom: bottom, scale: 0.92))
                        } else if visible {
                            pill.transition(transition(bottom: bottom, scale: 0.85))
                        } else if !session.isConnected {
                            ConnectionDot(state: session.state)
                                // The one lit spot left on a dimmed screen; dim it too (OLED).
                                .opacity(router.isDimmed ? 0.3 : 1)
                                .padding(bottom ? .bottom : .top, 8)
                                .transition(.opacity)
                        }
                    }
                    .glassGroup(spacing: 12)
                    if !bottom && showsHint { hint }
                }
                .padding(bottom ? .bottom : .top, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: bottom ? .bottom : .top)
        }
        // A floating control, like Control Center: it grows with text size up to a point,
        // then stays put instead of breaking words across lines.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: visible)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: expanded)
        .animation(.easeInOut(duration: 0.2), value: session.isConnected)
        .onAppear {
            #if DEBUG
            if DebugLaunch.showMenuAtLaunch { expanded = true }
            #endif
            scheduleHide()
        }
        .onChange(of: router.mode) { reveal() }
        .onChange(of: router.layoutID) { reveal() }
        .onChange(of: voiceOver) { reveal() }
    }

    /// On iOS 26 the glass itself morphs between pill and menu; before that they scale and fade.
    private func transition(bottom: Bool, scale: CGFloat) -> AnyTransition {
        if #available(iOS 26.0, *) { return .opacity }
        if reduceMotion { return .opacity }
        return .opacity.combined(with: .scale(scale: scale, anchor: bottom ? .bottom : .top))
    }

    // MARK: Pill

    private var pill: some View {
        let mode = router.mode
        let layout = router.layout
        let title = layout?.name ?? mode.title
        return HStack(spacing: 8) {
            Image(systemName: layout?.symbol(landscape: isLandscape) ?? mode.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(layout == nil ? mode.accent(palette) : palette.inkColor)
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.inkColor)
                .lineLimit(1)
            if !session.isConnected {
                ConnectionDot(state: session.state)
                    .transition(.opacity.combined(with: .scale(scale: 0.5)))
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 40)
        .morphingGlass(Capsule(), id: "switcher", in: glass, interactive: true)
        .contentShape(Capsule())
        .onTapGesture {
            Haptics.shared.tap()
            settings.seenTips.insert(Self.hintID)
            expanded = true
            hideTask?.cancel()
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            Haptics.shared.play(.click)
            expanded = false
            router.showSettings = true
            ScreenAwake.update()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(layout == nil ? "\(mode.title) mode" : "\(title) layout")
        .accessibilityValue(session.isConnected ? "" : session.state.statusText)
        .accessibilityHint("Double tap to switch modes")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Settings") {
            router.showSettings = true
            ScreenAwake.update()
        }
    }

    // MARK: First-run hint

    private static let hintID = "pill"

    /// Until the pill has been tapped once, a line under it says what it does, and it stays.
    private var showsHint: Bool {
        // Only over the trackpad: every other mode has content right under the pill.
        guard !expanded, router.mode == .trackpad, router.layoutID == nil, !settings.seenTips.contains(Self.hintID),
              settings.hasOnboarded else { return false }
        #if DEBUG
        if FilmDirector.shared.active || session.isDemo { return false }
        #endif
        return true
    }

    private var hint: some View {
        Text("Tap for modes. Hold for Settings.")
            .font(.footnote)
            .foregroundStyle(palette.inkSoftColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityHidden(true)
    }

    // MARK: Menu

    private var locked: Bool { settings.orientation != .automatic }

    /// Rows of at most five that fill evenly: five in one row, then two rows.
    static func columns(for count: Int) -> Int {
        count <= 5 ? max(1, count) : min(5, (count + 1) / 2)
    }

    private var menu: some View {
        let modes = AppMode.visible
        // Every mode that opens on top instead of replacing the screen, unless shown as a mode.
        let tools = AppMode.allCases.filter { $0.isTool && !modes.contains($0) }
        return VStack(spacing: 8) {
            header
            if session.macNeedsAccessibility {
                MacPermissionBanner(compact: true)
            }
            tileGrid(modes) { mode in
                let current = mode == router.mode && router.layoutID == nil
                Button {
                    Haptics.shared.tap()
                    router.show(mode)
                    close()
                } label: {
                    MenuTile(title: mode.title, selected: current) { symbol(mode) }
                }
                .buttonStyle(TileStyle())
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(current ? .isSelected : [])
            }
            LayoutMenuRow(close: close)
            if !tools.isEmpty {
                Divider().padding(.horizontal, 8)
                tileGrid(tools, alignedTo: modes.count) { tool in
                    Button {
                        Haptics.shared.tap()
                        close()
                        router.openTool(tool)
                    } label: {
                        MenuTile(title: tool.title) { symbol(tool) }
                    }
                    .buttonStyle(TileStyle())
                    .accessibilityLabel(tool.title)
                    .accessibilityHint(tool.toolHint)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(width: Self.contentWidth + 24)
        .morphingGlass(RoundedRectangle(cornerRadius: 32, style: .continuous), id: "switcher", in: glass)
        .accessibilityAction(.escape) { close() }
    }

    private func symbol(_ mode: AppMode) -> some View {
        Image(systemName: mode.symbol)
            .font(.title3)
            .imageScale(.medium)
            .foregroundStyle(mode.accent(palette))
    }

    /// The menu's width inside its margins, and the gap between tiles.
    static let contentWidth: CGFloat = 316
    static let tileSpacing: CGFloat = 4

    /// Tiles in even rows. A short row under a grid (`alignedTo` its count) keeps that grid's
    /// columns and sits centred in them, so every symbol lines up with one above it.
    @ViewBuilder
    private func tileGrid<Tile: View>(_ items: [AppMode], alignedTo above: Int? = nil,
                                      @ViewBuilder tile: @escaping (AppMode) -> Tile) -> some View {
        let aboveColumns = above.map(Self.columns(for:)) ?? 0
        if items.count < aboveColumns, (aboveColumns - items.count) % 2 == 0 {
            let width = (Self.contentWidth - Self.tileSpacing * CGFloat(aboveColumns - 1)) / CGFloat(aboveColumns)
            HStack(spacing: Self.tileSpacing) {
                ForEach(items) { tile($0).frame(width: width) }
            }
            .frame(maxWidth: .infinity)
        } else {
            let columns = Self.columns(for: items.count)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.tileSpacing), count: columns),
                      spacing: Self.tileSpacing) {
                ForEach(items) { tile($0) }
            }
        }
    }

    /// Lock Rotation and Settings in the corners, the Mac in between.
    private var header: some View {
        HStack(spacing: 8) {
            RoundIconButton(symbol: locked ? "lock.rotation" : "rotate.right", on: locked) {
                Haptics.shared.tap()
                OrientationLock.toggle()
            }
            .accessibilityLabel("Lock Rotation")
            .accessibilityValue(locked ? settings.orientation.title : "Off")
            .accessibilityHint(locked ? "Lets the screen turn with the phone again" : "Holds the screen the way it is now")
            Spacer(minLength: 0)
            macStatus
            Spacer(minLength: 0)
            RoundIconButton(symbol: "gearshape") {
                close()
                router.showSettings = true
                ScreenAwake.update()
            }
            .accessibilityLabel("Settings")
        }
    }

    /// The Mac's name, or what is wrong with the connection. With two or more paired Macs it is
    /// a menu to switch between them; the choice is remembered.
    @ViewBuilder private var macStatus: some View {
        let choosing = store.macs.count > 1
        let words = store.selected == nil ? "No Mac paired"
            : session.isConnected ? (session.macName ?? "Mac") : session.state.statusText
        let label = HStack(spacing: 6) {
            if !session.isConnected { ConnectionDot(state: session.state) }
            Text(words)
                .lineLimit(1)
                .truncationMode(.middle)
            if choosing {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
            }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(palette.inkSoftColor)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        if choosing {
            Menu {
                ForEach(store.macs) { mac in
                    Button {
                        Haptics.shared.tap()
                        session.select(mac)
                        close()
                    } label: {
                        if mac.macID == store.selected?.macID {
                            Label(mac.name, systemImage: "checkmark")
                        } else {
                            Text(mac.name)
                        }
                    }
                }
            } label: { label }
            .accessibilityLabel("Mac")
            .accessibilityValue(words)
        } else {
            label
                .accessibilityElement(children: .combine)
        }
    }

    /// The pill's layout symbol follows the way the screen splits now.
    @Environment(\.verticalSizeClass) private var verticalSize
    private var isLandscape: Bool { verticalSize == .compact }

    // MARK: Timing

    private func reveal() {
        visible = true
        scheduleHide()
    }

    private func close() {
        expanded = false
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard !voiceOver, !showsHint else { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, !expanded else { return }
            visible = false
        }
    }
}

/// One tile in the mode menu (modes, layouts and tools alike): a symbol over a short name,
/// like a Control Center button. Only the current one is filled, in a neutral shade, so the
/// colour stays with the symbols.
struct MenuTile<Icon: View>: View {
    @Environment(\.palette) private var palette
    let title: String
    var selected = false
    var soft = false
    let icon: Icon

    init(title: String, selected: Bool = false, soft: Bool = false, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.selected = selected
        self.soft = soft
        self.icon = icon()
    }

    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 16, style: .continuous) }

    var body: some View {
        VStack(spacing: 6) {
            icon.frame(height: 28)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(soft ? palette.inkSoftColor : palette.inkColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, minHeight: 66)
        .background {
            if selected { Self.shape.fill(palette.inkColor.opacity(palette.isDark ? 0.16 : 0.08)) }
        }
        .contentShape(Self.shape)
    }
}

/// A small round button for the menu's corners. `on` fills it with the ink, like a switched
/// on Control Center button.
private struct RoundIconButton: View {
    @Environment(\.palette) private var palette
    let symbol: String
    var on = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(on ? palette.solidColor : palette.inkColor)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 36)
                .background(Circle().fill(on ? palette.inkColor : palette.inkColor.opacity(palette.isDark ? 0.14 : 0.07)))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .animation(.easeInOut(duration: 0.2), value: on)
        }
        .buttonStyle(TileStyle())
    }
}

private extension View {
    /// Glass that morphs into the other glass with the same `id` in its container on iOS 26
    /// (the pill grows into the menu). Before that, the closest system material.
    @ViewBuilder
    func morphingGlass(_ shape: some Shape, id: String, in namespace: Namespace.ID, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
                .glassEffectID(id, in: namespace)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.primary.opacity(0.08), lineWidth: 0.5))
        }
    }
}

/// The connection in one dot, in the palette's status colours (`Palette.linkColor`). It pulses
/// while looking or connecting.
struct ConnectionDot: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorSchemeContrast) private var contrast
    let state: LinkState

    var body: some View {
        Circle()
            .fill(palette.linkColor(state))
            .frame(width: 7, height: 7)
            .overlay {
                if contrast == .increased { Circle().strokeBorder(.primary.opacity(0.6), lineWidth: 1) }
            }
            .phaseAnimator([1.0, 0.35], trigger: pulsing) { dot, opacity in
                dot.opacity(pulsing ? opacity : 1)
            } animation: { _ in .easeInOut(duration: 0.8) }
            .accessibilityHidden(true)
    }

    private var pulsing: Bool {
        switch state {
        case .searching, .connecting: true
        default: false
        }
    }
}

/// What a mode shows when there is no connection.
struct ModeOfflineMessage: View {
    var session = MacSession.shared
    var router = AppRouter.shared
    let mode: AppMode

    var body: some View {
        if PairingStore.shared.selected == nil {
            VStack(spacing: 16) {
                QuietMessage(symbol: "laptopcomputer", title: "No Mac paired",
                             detail: "Pair a Mac to use \(mode.title).")
                    .frame(maxHeight: 180)
                Button("Pair a Mac") { router.showPairing = true }
                    .glassButton(prominent: true)
                    .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if session.isReplaced {
            VStack(spacing: 16) {
                QuietMessage(symbol: "iphone", title: session.state.statusText,
                             detail: "\(session.macName ?? "Your Mac") follows one iPhone at a time.")
                    .frame(maxHeight: 180)
                LinkActions()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 16) {
                QuietMessage(symbol: mode.symbol, title: session.state.statusText,
                             detail: "Keep both on the same Wi-Fi with Glasspad open on \(session.macName ?? "your Mac").")
                    .frame(maxHeight: 180)
                LinkActions()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
