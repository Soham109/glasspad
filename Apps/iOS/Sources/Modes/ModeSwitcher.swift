import SwiftUI
import GlasspadKit

/// The small pill at the top centre. It shows the current mode, fades after 2 s, and comes
/// back when the top edge is touched. Tap it for the mode menu, long press for Settings.
/// When faded, a tiny dot stays in its place and shows the connection.
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
                    if bottom && expanded {
                        menu
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
                    }
                    if bottom && showsHint { hint }
                    if visible || expanded {
                        pill
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.85, anchor: bottom ? .bottom : .top)))
                    } else {
                        ConnectionDot(state: session.state)
                            .padding(bottom ? .bottom : .top, 8)
                            .transition(.opacity)
                    }
                    if !bottom && showsHint { hint }
                    if !bottom && expanded {
                        menu
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
                    }
                }
                .padding(bottom ? .bottom : .top, 6)
                .glassGroup(spacing: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: bottom ? .bottom : .top)
        }
        // A floating control, like Control Center: it grows with text size up to a point,
        // then stays put instead of breaking words across lines.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: visible)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: expanded)
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
            ConnectionDot(state: session.state)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 40)
        .glassCapsule(interactive: true)
        .contentShape(Capsule())
        .onTapGesture {
            Haptics.shared.tap()
            settings.seenTips.insert(Self.hintID)
            if expanded { close() } else { expanded = true; hideTask?.cancel() }
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            Haptics.shared.play(.click)
            expanded = false
            router.showSettings = true
            ScreenAwake.update()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(layout == nil ? "\(mode.title) mode, \(session.state.statusText)" : "\(title) layout, \(session.state.statusText)")
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

    private var menu: some View {
        let modes = AppMode.visible
        let columns = modes.count <= 5 ? max(1, modes.count) : 4
        return VStack(spacing: 6) {
            if session.macNeedsAccessibility {
                MacPermissionBanner(compact: true)
                    .padding(.bottom, 4)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
                ForEach(modes) { mode in
                    let current = mode == router.mode && router.layoutID == nil
                    Button {
                        Haptics.shared.tap()
                        router.show(mode)
                        close()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: mode.symbol)
                                .font(.title3)
                                .imageScale(.medium)
                                .foregroundStyle(mode.accent(palette))
                                .frame(height: 26)
                            Text(mode.title)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(palette.inkColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background {
                            if current {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(mode.accent(palette).opacity(0.14))
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(TileStyle())
                    .accessibilityLabel(mode.title)
                    .accessibilityAddTraits(current ? .isSelected : [])
                }
            }
            LayoutMenuRow(close: close)
            Divider().padding(.horizontal, 8).padding(.vertical, 2)
            let tools = [AppMode.clipboard, .present, .remote, .displays].filter { !modes.contains($0) }
            if !tools.isEmpty {
                // Four tools do not fit in one row with their names: two rows of two.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: tools.count == 4 ? 2 : tools.count),
                          spacing: 6) {
                    ForEach(tools) { tool in
                        Button {
                            Haptics.shared.tap()
                            close()
                            router.openTool(tool)
                        } label: {
                            utilityLabel(tool.title, symbol: tool.toolSymbol)
                        }
                        .buttonStyle(TileStyle())
                        .accessibilityHint(tool.toolHint)
                    }
                }
            }
            if store.macs.count > 1 { macPicker }
            HStack(spacing: 6) {
                Button {
                    Haptics.shared.tap()
                    OrientationLock.toggle()
                } label: {
                    utilityLabel(locked ? "Rotation Locked" : "Lock Rotation",
                                 symbol: locked ? "lock.rotation" : "rotate.right", on: locked)
                }
                .buttonStyle(TileStyle())
                .accessibilityLabel("Lock rotation")
                .accessibilityValue(locked ? settings.orientation.title : "Off")
                .accessibilityHint(locked ? "Lets the screen turn with the phone again" : "Holds the screen the way it is now")

                Button {
                    close()
                    router.showSettings = true
                    ScreenAwake.update()
                } label: {
                    utilityLabel("Settings", symbol: "gearshape")
                }
                .buttonStyle(TileStyle())
            }
        }
        .padding(10)
        .frame(width: 340)
        .glassPanel(cornerRadius: 28)
    }

    /// The smaller buttons under the modes: a soft tile, so they read as buttons too.
    private func utilityLabel(_ title: String, symbol: String, on: Bool = false) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(palette.inkColor)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .contentTransition(.symbolEffect(.replace))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(palette.inkColor.opacity(on ? 0.16 : 0.06),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Only with two or more paired Macs. Picking one connects to it; the choice is remembered.
    private var macPicker: some View {
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
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "laptopcomputer")
                Text(store.selected?.name ?? "Choose a Mac")
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.inkSoftColor)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(palette.inkColor)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(palette.inkColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Mac")
        .accessibilityValue(store.selected?.name ?? "None")
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

/// Green when connected, amber while looking or connecting, red on failure, grey when idle.
struct ConnectionDot: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let state: LinkState

    var body: some View {
        Circle()
            .fill(color)
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

    private var color: Color {
        switch state {
        case .connected: Color(uiColor: .systemGreen)
        case .searching, .connecting: Color(uiColor: .systemOrange)
        case .failed where state.isReplaced: Color.gray
        case .failed: Color(uiColor: .systemRed)
        case .idle: Color.gray
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
