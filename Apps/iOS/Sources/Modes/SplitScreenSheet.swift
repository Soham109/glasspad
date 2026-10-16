import SwiftUI
import GlasspadKit

/// Split Screen, seen before it happens: the display in miniature with the two windows on their
/// halves (the front window left, the one behind it right). Tap a half for another window, swap
/// them, pick the display when there are several, then Split.
struct SplitScreenSheet: View {
    /// The window to start on the left (Displays' Split With); the front one when nil.
    let startLeft: UInt32?
    /// One-tap Split Screen instead, for a Mac that cannot show its windows (none from Displays).
    let fallback: (() -> Void)?

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    var store = DisplaysStore.shared
    var session = MacSession.shared

    @State private var selection: SplitSelection?
    @State private var fellBack = false

    private var accent: Color { AppMode.displays.accent(palette) }

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
            .navigationTitle("Split Screen")
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
            let wide = size.width > size.height * 1.3
            if wide {
                HStack(alignment: .center, spacing: 20) {
                    preview(state, selection, display)
                    VStack(spacing: 16) {
                        Spacer(minLength: 0)
                        controls(state, selection)
                    }
                    .frame(width: min(300, size.width * 0.36))
                }
            } else {
                VStack(spacing: 16) {
                    if state.shownDisplays.count > 1 { displayPicker(state, selection) }
                    preview(state, selection, display)
                    if !state.canArrangeWindows { MacPermissionBanner(compact: true) }
                    splitButton(state, selection)
                }
            }
        } else if let state = store.state, state.windows.count < 2, fallback == nil {
            QuietMessage(symbol: "rectangle.split.2x1", title: "Open a second window",
                         detail: "Split Screen puts two windows side by side.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Sideways: the display picker, the permission note and Split beside the picture.
    @ViewBuilder private func controls(_ state: DisplaysState, _ s: SplitSelection) -> some View {
        if state.shownDisplays.count > 1 { displayPicker(state, s) }
        if !state.canArrangeWindows { MacPermissionBanner(compact: true) }
        splitButton(state, s)
    }

    private func displayPicker(_ state: DisplaysState, _ s: SplitSelection) -> some View {
        Picker("Display", selection: Binding(get: { s.display }, set: { id in
            Haptics.shared.tap()
            var next = s
            next.display = id
            next.displayPicked = true
            withAnimation(.snappy(duration: 0.28)) { selection = next }
        })) {
            ForEach(state.shownDisplays) { d in
                Text(d.isBuiltIn ? "Built-in" : d.name).tag(d.id)
            }
        }
        .pickerStyle(.segmented)
    }

    private func splitButton(_ state: DisplaysState, _ s: SplitSelection) -> some View {
        Button {
            Haptics.shared.play(.click)
            store.split(s)
            dismiss()
        } label: {
            Text("Split").frame(maxWidth: .infinity)
        }
        .glassButton(prominent: true, accent: accent)
        .controlSize(.large)
        .disabled(!state.canArrangeWindows || state.commands(for: s) == nil)
    }

    // MARK: Picture

    private func preview(_ state: DisplaysState, _ s: SplitSelection, _ display: MacDisplay) -> some View {
        GeometryReader { geo in
            let map = DisplayMiniature(frames: [display.frame], fitting: geo.size, padding: 1)
            let screen = map.toView(display.frame)
            let halves = state.splitFrames(for: s)
            ZStack(alignment: .topLeading) {
                DisplayTile(display: display, rect: screen, scale: map.scale, highlighted: false, windowCount: 0)
                    .accessibilityHidden(true)
                if let halves {
                    half(state, s, left: true, rect: map.toView(halves.left), scale: map.scale)
                    half(state, s, left: false, rect: map.toView(halves.right), scale: map.scale)
                    swapButton(s)
                        .position(x: (map.toView(halves.left).maxX + map.toView(halves.right).minX) / 2,
                                  y: map.toView(halves.left).midY)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .aspectRatio(display.frame.width / max(1, display.frame.height), contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.28), value: display)
    }

    /// One half: the window that goes there. Tap for the list of windows.
    private func half(_ state: DisplaysState, _ s: SplitSelection, left: Bool, rect: CGRect, scale: CGFloat) -> some View {
        let id = left ? s.left : s.right
        let window = state.window(id)
        return Menu {
            Picker(left ? "Left" : "Right", selection: Binding(get: { id }, set: { new in
                Haptics.shared.tap()
                withAnimation(.snappy(duration: 0.28)) { selection = state.choosing(new, left: left, in: s) }
            })) {
                ForEach(state.splitChoices(keeping: id)) { w in
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
            SplitHalfCard(window: window, icon: window?.bundleID.flatMap { session.icons.image(for: $0) },
                          size: rect.size, scale: scale)
        }
        .buttonStyle(TileStyle())
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .accessibilityLabel(left ? "Left half" : "Right half")
        .accessibilityValue(window.map { w in w.title.map { $0.isEmpty || $0 == w.appName ? w.appName : "\(w.appName), \($0)" } ?? w.appName } ?? "")
        .accessibilityHint("Double tap to choose another window.")
    }

    private func swapButton(_ s: SplitSelection) -> some View {
        Button {
            Haptics.shared.tap()
            withAnimation(.snappy(duration: 0.28)) { selection = s.swapped }
        } label: {
            Image(systemName: "arrow.left.arrow.right")
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
        .accessibilityLabel("Swap Sides")
    }

    // MARK: State

    /// Upright: the title bar, the picker, the display at full width, the button.
    private var detentHeight: CGFloat {
        let width = UIScreen.main.bounds.width - 32
        guard let state = store.state, let s = selection, let d = state.display(s.display), d.frame.height > 0 else { return 420 }
        let picture = width * d.frame.height / d.frame.width
        let picker: CGFloat = state.shownDisplays.count > 1 ? 32 + 16 : 0
        let banner: CGFloat = state.canArrangeWindows ? 0 : 76
        return 56 + 8 + picker + picture + 16 + banner + 50 + 16 + 4
    }

    /// Starts from the front window, then keeps the choice as windows come and go.
    private func sync() {
        guard let state = store.state else { return }
        let next = selection.flatMap { state.refreshed($0) } ?? state.defaultSplit(left: startLeft)
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

/// A window on its half: the frame and title bar macOS draws, the app's icon and name.
private struct SplitHalfCard: View {
    @Environment(\.palette) private var palette
    let window: MacWindow?
    let icon: UIImage?
    let size: CGSize
    let scale: CGFloat

    var body: some View {
        let corner = min(max(4, 16 * scale), min(size.width, size.height) / 4)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let bar = min(size.height * 0.16, max(10, 28 * scale))
        let shade = palette.isDark ? palette.solidColor : palette.inkColor
        ZStack(alignment: .top) {
            shape.fill(palette.solidColor)
            shape.fill(palette.raisedColor)
            Rectangle()
                .fill(palette.inkColor.opacity(0.05))
                .frame(height: bar)
            lights(bar)
            label
                .padding(.horizontal, 8)
                .padding(.top, bar)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(palette.inkColor.opacity(0.18), lineWidth: 0.75))
        .frame(width: size.width, height: size.height)
        .shadow(color: shade.opacity(0.18), radius: 3, y: 1)
        .contentShape(shape)
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
        return VStack(spacing: 6) {
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
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.inkColor)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.inkSoftColor)
                    }
                    // Always a line for the name, so both halves line up.
                    let title = window.title.flatMap { $0.isEmpty || $0 == window.appName ? nil : $0 }
                    Text(title ?? " ")
                        .font(.caption)
                        .foregroundStyle(palette.inkSoftColor)
                        .accessibilityHidden(title == nil)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
        }
    }
}
