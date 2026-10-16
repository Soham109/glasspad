import SwiftUI
import GlasspadKit

/// One display's settings, calm and in the order System Settings uses: brightness, the
/// "Looks like" sizes, Night Shift, then (with more than one display) the main display,
/// mirroring and the arrangement. A new resolution or mirroring asks "Keep these display
/// settings?" and goes back by itself after 15 seconds.
struct DisplaySettingsSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State var displayID: UInt32
    var store = DisplaysStore.shared

    @State private var brightness: Double = 0
    @State private var editingBrightness = false
    @State private var heldUntil = Date.distantPast
    @State private var throttle = SliderThrottle()
    @State private var arranging = false

    init(displayID: UInt32) {
        _displayID = State(initialValue: displayID)
    }

    private var state: DisplaysState? { store.state }
    private var display: MacDisplay? { state?.display(displayID) }
    private var accent: Color { AppMode.displays.accent(palette) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let state, state.displays.count > 1 { picker(state) }
                    if let display { sections(display) }
                }
                .padding(16)
                .padding(.bottom, 140)
            }
            .background(SurfaceBackground())
            .navigationTitle(display?.name ?? "Display")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if #available(iOS 26.0, *) {
                        Button("Done", systemImage: "checkmark", role: .confirm) { dismiss() }
                    } else {
                        Button("Done") { dismiss() }.fontWeight(.semibold)
                    }
                }
            }
            .navigationDestination(isPresented: $arranging) { ArrangeDisplaysView() }
            .overlay(alignment: .bottom) {
                DisplaysNotices().padding(16)
            }
            .animation(.snappy(duration: 0.25), value: store.state?.pending)
            .animation(.snappy(duration: 0.25), value: store.notice)
        }
        .tint(palette.inkColor)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            syncBrightness()
            #if DEBUG
            if DisplaysDebug.openArrange {
                DisplaysDebug.openArrange = false
                arranging = true
            }
            #endif
        }
        .onChange(of: displayID) { syncBrightness(force: true) }
        .onChange(of: display?.brightness) { syncBrightness() }
        .onChange(of: state == nil) { _, gone in if gone { dismiss() } }
    }

    private func picker(_ state: DisplaysState) -> some View {
        Picker("Display", selection: $displayID) {
            ForEach(state.displays) { d in
                Text(d.isBuiltIn ? "Built-in" : d.name).tag(d.id)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder private func sections(_ d: MacDisplay) -> some View {
        if let master = d.mirrorOf.flatMap({ state?.display($0) }) {
            card {
                row(symbol: "rectangle.on.rectangle", title: "Mirroring \(master.name)",
                    detail: "This display shows the same picture.") {
                    Button("Stop") { run(.mirror(display: d.id, of: nil)) }
                        .glassButton()
                }
            }
        } else {
            if d.brightness != nil {
                card(spacing: 6) {
                    Text("Brightness")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.inkColor)
                        .accessibilityHidden(true)
                    LevelSlider(value: $brightness, low: "sun.min.fill", high: "sun.max.fill", label: "Brightness", enabled: true) { editing in
                        editingBrightness = editing
                        if !editing { heldUntil = Date().addingTimeInterval(0.8) }
                    } onChange: { value in
                        guard abs(value - (display?.brightness ?? -1)) > 0.001 else { return }
                        throttle.send("brightness.\(d.id)", value) { store.run(.brightness(display: d.id, value: $0)) }
                    }
                    .padding(.vertical, 4)
                }
            }
            if d.resolutions.count > 1 {
                card { ResolutionPicker(display: d, accent: accent) { run(.resolution(display: d.id, id: $0.id)) } }
            }
        }
        card {
            Toggle(isOn: Binding(get: { state?.nightShift ?? false }, set: { _ in
                Haptics.shared.tap()
                store.toggleNightShift()
            })) {
                Label("Night Shift", systemImage: "moon.fill")
                    .foregroundStyle(palette.inkColor)
            }
            .tint(accent)
        }
        if let state, state.displays.count > 1 { arrangement(d, state) }
    }

    /// Main display, mirroring and Arrange: only with more than one display.
    private func arrangement(_ d: MacDisplay, _ state: DisplaysState) -> some View {
        let main = state.displays.first(where: \.isMain)
        return card(spacing: 0) {
            if d.mirrorOf == nil {
                if d.isMain {
                    row(symbol: "menubar.rectangle", title: "Main Display", detail: "It has the menu bar.") {
                        Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(accent)
                    }
                } else {
                    Button { run(.makeMain(display: d.id)) } label: {
                        row(symbol: "menubar.rectangle", title: "Use as Main Display", detail: "Moves the menu bar here.") { EmptyView() }
                    }
                    .buttonStyle(.plain)
                }
                divider
            }
            if !d.isMain, let main {
                Toggle(isOn: Binding(get: { d.mirrorOf != nil }, set: { on in
                    run(.mirror(display: d.id, of: on ? main.id : nil))
                })) {
                    rowLabel(symbol: "rectangle.on.rectangle", title: "Mirror \(main.name)", detail: "Show the same picture on both.")
                }
                .tint(accent)
                .padding(.vertical, 10)
                divider
            }
            Button { arranging = true } label: {
                row(symbol: "rectangle.3.group", title: "Arrange Displays", detail: "Match how they sit on your desk.") {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(palette.inkSoftColor)
                }
            }
            .buttonStyle(.plain)
            .disabled(state.shownDisplays.count < 2)
        }
    }

    // MARK: Pieces

    private func card<Content: View>(spacing: CGFloat = 12, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: spacing) { content() }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(palette.raisedColor))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(palette.lineColor, lineWidth: 1))
    }

    private var divider: some View { Rectangle().fill(palette.lineColor).frame(height: 1) }

    private func rowLabel(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(palette.inkSoftColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).foregroundStyle(palette.inkColor)
                Text(detail).font(.footnote).foregroundStyle(palette.inkSoftColor)
            }
        }
    }

    private func row<Trailing: View>(symbol: String, title: String, detail: String,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            rowLabel(symbol: symbol, title: title, detail: detail)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func run(_ command: DisplayCommand) {
        Haptics.shared.tap()
        store.run(command)
    }

    private func syncBrightness(force: Bool = false) {
        guard force || (!editingBrightness && Date() >= heldUntil), let b = display?.brightness else { return }
        brightness = b
    }
}

// MARK: - Resolution

/// The "Looks like" sizes as System Settings shows them: a row of small displays, text larger
/// on the left and more space on the right, the one in use marked.
private struct ResolutionPicker: View {
    @Environment(\.palette) private var palette
    let display: MacDisplay
    let accent: Color
    let onPick: (DisplayResolution) -> Void

    var body: some View {
        let choices = display.resolutions
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Resolution").font(.body).foregroundStyle(palette.inkColor)
                Spacer()
                if let r = display.resolution {
                    Text("Looks like \(r.title)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(palette.inkSoftColor)
                        .contentTransition(.numericText())
                }
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(choices.enumerated()), id: \.element.id) { i, r in
                    Button { onPick(r) } label: { choice(r, index: i, count: choices.count) }
                        .buttonStyle(TileStyle())
                        .accessibilityLabel("Looks like \(r.width) by \(r.height)")
                        .accessibilityValue(caption(r, index: i, count: choices.count) ?? "")
                        .accessibilityAddTraits(r.id == display.resolutionID ? .isSelected : [])
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: display.resolutionID)
    }

    private func choice(_ r: DisplayResolution, index: Int, count: Int) -> some View {
        let selected = r.id == display.resolutionID
        let smallest = display.resolutions.map(\.width).min() ?? r.width
        // The same text drawn at each size: larger where the desktop is smaller.
        let textSize = 15 * CGFloat(smallest) / CGFloat(r.width)
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return VStack(spacing: 6) {
            ZStack {
                shape.fill(selected ? accent.opacity(0.16) : palette.inkColor.opacity(0.05))
                shape.strokeBorder(selected ? accent : palette.inkColor.opacity(0.18), lineWidth: selected ? 2 : 1)
                Text("Aa")
                    .font(.system(size: max(6, textSize), weight: .medium))
                    .foregroundStyle(selected ? accent : palette.inkSoftColor)
            }
            .aspectRatio(CGFloat(r.width) / CGFloat(r.height), contentMode: .fit)
            Text(caption(r, index: index, count: count) ?? " ")
                .font(.caption2)
                .foregroundStyle(selected ? palette.inkColor : palette.inkSoftColor)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    /// Words under the ends and the default, as macOS puts them.
    private func caption(_ r: DisplayResolution, index: Int, count: Int) -> String? {
        if r.isDefault { return "Default" }
        if index == 0 { return "Larger Text" }
        if index == count - 1 { return "More Space" }
        return nil
    }
}

// MARK: - Arrange

/// Drag displays to match the desk, like System Settings' Arrange: each snaps to the edge of
/// another and lines up when close. Nothing changes on the Mac until Apply.
private struct ArrangeDisplaysView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    var store = DisplaysStore.shared

    /// Where each display sits now on the phone (global coordinates), before Apply.
    @State private var frames: [UInt32: CGRect] = [:]
    @State private var dragging: (id: UInt32, translation: CGSize)?
    /// The scale stays put while dragging, so the other displays never jump.
    @State private var frozen: DisplayMiniature?

    private var displays: [MacDisplay] { store.state?.shownDisplays ?? [] }
    private var accent: Color { AppMode.displays.accent(palette) }

    private func frame(_ d: MacDisplay) -> CGRect { frames[d.id] ?? d.frame }

    private var changed: Bool { displays.contains { frame($0).origin != $0.frame.origin } }

    var body: some View {
        VStack(spacing: 16) {
            GeometryReader { geo in
                let map = frozen ?? DisplayMiniature(frames: displays.map(frame), fitting: geo.size, padding: 24)
                ZStack(alignment: .topLeading) {
                    ForEach(displays) { d in
                        tile(d, map: map)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(palette.raisedColor))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(palette.lineColor, lineWidth: 1))
            Text("Drag displays to match how they sit on your desk.")
                .font(.footnote)
                .foregroundStyle(palette.inkSoftColor)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .background(SurfaceBackground())
        .navigationTitle("Arrange Displays")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply") {
                    Haptics.shared.tap()
                    store.run(.arrange(displays.map { DisplayOrigin(display: $0.id, origin: frame($0).origin) }))
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(!changed)
            }
        }
        .animation(.snappy(duration: 0.25), value: frames)
    }

    private func tile(_ d: MacDisplay, map: DisplayMiniature) -> some View {
        let isDragging = dragging?.id == d.id
        let offset = isDragging ? dragging!.translation : .zero
        let r = map.toView(frame(d)).offsetBy(dx: offset.width, dy: offset.height)
        let shape = RoundedRectangle(cornerRadius: max(4, 10 * map.scale), style: .continuous)
        let menuBar = max(3, max(d.menuBarHeight, 24) * map.scale)
        return ZStack(alignment: .top) {
            shape.fill(palette.solidColor)
            shape.fill(palette.raisedPressedColor)
            shape.fill(LinearGradient(colors: [accent.opacity(palette.isDark ? 0.30 : 0.22), accent.opacity(0.06)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            if d.isMain {
                Rectangle().fill(palette.raisedColor.opacity(0.92)).frame(height: menuBar)
            }
            VStack(spacing: 2) {
                Text(d.name).font(.caption.weight(.semibold)).foregroundStyle(palette.inkColor)
                if let res = d.resolution {
                    Text(res.title).font(.caption2.monospacedDigit()).foregroundStyle(palette.inkSoftColor)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(isDragging ? accent : palette.inkColor.opacity(0.22), lineWidth: isDragging ? 2 : 1))
        .frame(width: r.width, height: r.height)
        .scaleEffect(isDragging ? 1.02 : 1)
        .position(x: r.midX, y: r.midY)
        .zIndex(isDragging ? 1 : 0)
        .gesture(DragGesture(minimumDistance: 2)
            .onChanged { v in
                if frozen == nil { frozen = map }
                dragging = (d.id, v.translation)
            }
            .onEnded { v in
                let moved = frame(d).offsetBy(dx: map.toGlobal(length: v.translation.width), dy: map.toGlobal(length: v.translation.height))
                let others = displays.filter { $0.id != d.id }.map(frame)
                frames[d.id] = CGRect(origin: DisplayGeometry.snap(moved, to: others), size: moved.size)
                dragging = nil
                frozen = nil
                Haptics.shared.play(.detent)
            })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(d.name)
        .accessibilityHint("Drag to move it next to another display.")
    }
}
