import GlasspadKit
import SwiftUI
import UIKit

/// Makes or changes a layout. The drawing is the editor: tap a pane to choose what it shows,
/// drag the line to size it, drag the line off the edge to take a pane away. Upright and
/// Sideways show how it turns with the phone.
struct LayoutEditor: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSize
    var store = LayoutStore.shared
    var router = AppRouter.shared
    let isNew: Bool

    @State private var layout: ScreenLayout
    @State private var previewLandscape: Bool
    @State private var confirmDelete = false
    @FocusState private var naming: Bool

    init(draft: LayoutDraft) {
        isNew = draft.isNew
        var l = draft.layout
        // A pane folded away on the screen comes back while editing.
        if l.split <= 0 || l.split >= 1 { l.split = 0.5 }
        if l.innerSplit <= 0 || l.innerSplit >= 1 { l.innerSplit = 0.5 }
        _layout = State(initialValue: l)
        _previewLandscape = State(initialValue: OrientationLock.current.isLandscape)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let wide = geo.size.width > geo.size.height
                ScrollView {
                    if wide {
                        HStack(alignment: .top, spacing: 24) {
                            canvasBlock(height: geo.size.height - 40)
                            controls.frame(width: 300)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    } else {
                        VStack(spacing: 20) {
                            nameField
                            canvasBlock(height: min(440, geo.size.height * 0.56))
                            controls
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background { SurfaceBackground() }
            .navigationTitle(isNew ? "New Layout" : "Edit Layout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save", action: save)
                        .fontWeight(.semibold)
                }
            }
        }
        .confirmationDialog("Delete \(layout.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Layout", role: .destructive) {
                store.delete(layout.id)
                dismiss()
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            dismissKeyboard()
            previewLandscape = verticalSize == .compact
        }
        .interactiveDismissDisabled(naming)
    }

    // MARK: Pieces

    private var nameField: some View {
        TextField("Name", text: $layout.name)
            .font(.title3.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(palette.inkColor)
            .submitLabel(.done)
            .focused($naming)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(palette.raisedColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.lineColor))
            .accessibilityLabel("Layout name")
    }

    private func canvasBlock(height: CGFloat) -> some View {
        VStack(spacing: 14) {
            Picker("Preview", selection: $previewLandscape.animation(.spring(response: 0.4, dampingFraction: 0.85))) {
                Label("Upright", systemImage: "iphone").tag(false)
                Label("Sideways", systemImage: "iphone.landscape").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            EditorCanvas(layout: $layout, landscape: previewLandscape)
                .frame(height: max(160, height))
                .frame(maxWidth: .infinity)
            Text("Tap a pane to change it. Drag the line to resize, double tap it to even out, or drag it off the edge to remove a pane.")
                .font(.footnote)
                .foregroundStyle(palette.inkSoftColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            if verticalSize == .compact { nameField }
            VStack(alignment: .leading, spacing: 8) {
                Text("Split")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.inkSoftColor)
                Picker("Split", selection: $layout.direction.animation(.spring(response: 0.4, dampingFraction: 0.85))) {
                    Text("Automatic").tag(SplitDirection.automatic)
                    Text("Side by Side").tag(SplitDirection.sideBySide)
                    Text("Stacked").tag(SplitDirection.stacked)
                }
                .pickerStyle(.segmented)
                Text(directionDetail)
                    .font(.footnote)
                    .foregroundStyle(palette.inkSoftColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                if layout.panes.count > 1 {
                    Button {
                        Haptics.shared.tap()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { rotatePanes() }
                    } label: {
                        actionLabel("Swap", symbol: "arrow.triangle.swap")
                    }
                    .buttonStyle(TileStyle())
                    .accessibilityHint(layout.panes.count == 2 ? "Swaps the two panes" : "Moves each mode to the next pane")
                }
                if layout.panes.count < ScreenLayout.maxPanes {
                    Button {
                        Haptics.shared.tap()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            layout.addPane(candidates: AppMode.paneChoices.map(\.rawValue))
                        }
                    } label: {
                        actionLabel("Add Pane", symbol: "plus.rectangle")
                    }
                    .buttonStyle(TileStyle())
                }
            }

            if !isNew {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Text("Delete Layout")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .glassButton()
                .tint(palette.bad)
                .padding(.top, 8)
            }
        }
    }

    private var directionDetail: String {
        switch layout.direction {
        case .automatic: "Side by side when the phone is sideways, one above the other when it is upright."
        case .sideBySide: "Always side by side."
        case .stacked: "Always one above the other."
        }
    }

    private func actionLabel(_ title: String, symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(palette.inkColor)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(palette.inkColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Two panes swap; three move round one place.
    private func rotatePanes() {
        guard layout.panes.count > 1 else { return }
        for i in stride(from: layout.panes.count - 1, to: 0, by: -1) { layout.swapPanes(i, i - 1) }
    }

    private func save() {
        var saved = layout
        let trimmed = saved.name.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.name = trimmed.isEmpty ? store.uniqueName("Layout", ignoring: saved.id) : trimmed
        store.save(saved)
        Haptics.shared.play(.snap)
        // A new layout opens at once; an edited one refreshes if it is on screen.
        if isNew || router.layoutID == saved.id {
            router.show(layout: saved)
        }
        dismiss()
    }
}

// MARK: - Canvas

/// The layout drawn large, with panes you tap and lines you drag.
private struct EditorCanvas: View {
    @Environment(\.palette) private var palette
    @Binding var layout: ScreenLayout
    let landscape: Bool

    @State private var drag: (level: ScreenLayout.DividerFrame.Level, share: Double, grab: Double)?
    @State private var target: Double?

    private let gap: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let box = fitted(in: geo.size)
            let drawing = CGSize(width: box.width - gap * 2, height: box.height - gap * 2)
            let shown = displayed.arrangement(in: drawing, gap: gap)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(palette.inkColor.opacity(palette.isDark ? 0.10 : 0.07))
                    .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(palette.lineColor))
                ForEach(shown.panes, id: \.index) { pane in
                    paneMenu(pane.index, size: pane.rect.size)
                        .offset(x: pane.rect.minX + gap, y: pane.rect.minY + gap)
                }
                ForEach(Array(shown.dividers.enumerated()), id: \.offset) { _, divider in
                    line(divider, scale: screenPointsPerPoint(drawing, sideBySide: divider.sideBySide))
                }
            }
            .frame(width: box.width, height: box.height, alignment: .topLeading)
            .coordinateSpace(name: "canvas")
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: drag == nil)
        }
    }

    /// The phone shape, as large as fits.
    private func fitted(in size: CGSize) -> CGSize {
        let aspect = landscape ? LayoutDiagram.aspect : 1 / LayoutDiagram.aspect
        let width = min(size.width, size.height * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    private var displayed: ScreenLayout {
        guard let drag else { return layout }
        var l = layout
        if drag.level == .main { l.split = drag.share } else { l.innerSplit = drag.share }
        return l
    }

    private func paneMenu(_ index: Int, size: CGSize) -> some View {
        let current = layout.mode(at: index)
        let folding = foldingPanes.contains(index)
        return Menu {
            Section {
                ForEach(AppMode.paneChoices) { mode in
                    Button {
                        Haptics.shared.tap()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { layout.setMode(mode.rawValue, at: index) }
                    } label: {
                        if mode == current {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Label(mode.title, systemImage: mode.symbol)
                        }
                    }
                }
            }
            if layout.panes.count > 1 {
                Section {
                    Button(role: .destructive) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { layout.removePane(at: index) }
                    } label: {
                        Label("Remove Pane", systemImage: "minus.rectangle")
                    }
                }
            }
        } label: {
            PaneTile(mode: current, size: size, cornerRadius: 26, showsTitle: true)
                .opacity(folding ? 0.4 : 1)
                .scaleEffect(folding ? 0.94 : 1)
                .animation(.easeOut(duration: 0.18), value: folding)
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Pane \(index + 1), \(current.title)")
        .accessibilityHint("Choose what this pane shows")
    }

    private func line(_ divider: ScreenLayout.DividerFrame, scale k: Double) -> some View {
        let r = divider.rect.offsetBy(dx: gap, dy: gap)
        let across = divider.sideBySide
        let active = drag?.level == divider.level
        return Capsule()
            .fill(palette.inkColor.opacity(active ? 0.55 : 0.3))
            .frame(width: across ? 4 : 36, height: across ? 36 : 4)
            .frame(width: across ? r.width + 24 : r.width, height: across ? r.height : r.height + 24)
            .contentShape(Rectangle())
            .offset(x: across ? r.minX - 12 : r.minX, y: across ? r.minY : r.minY - 12)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("canvas"))
                    .onChanged { changed(divider, $0.location, scale: k) }
                    .onEnded { ended(divider, $0.location, scale: k) }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                Haptics.shared.tap()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { set(0.5, divider.level) }
            })
            .accessibilityElement()
            .accessibilityLabel("Divider")
            .accessibilityValue("\(Int((divider.share * 100).rounded())) percent")
            .accessibilityAdjustableAction { direction in
                let stops: [Double] = [1.0 / 3, 0.5, 2.0 / 3]
                let i = stops.enumerated().min { abs($0.element - divider.share) < abs($1.element - divider.share) }?.offset ?? 1
                set(stops[min(max(i + (direction == .increment ? 1 : -1), 0), 2)], divider.level)
            }
    }

    // MARK: Dragging

    /// The canvas is a small copy of the screen; drags are measured in real screen points so
    /// the line snaps and folds where it would on the phone itself.
    private func screenPointsPerPoint(_ drawing: CGSize, sideBySide: Bool) -> Double {
        let screen = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen.bounds.size
            ?? CGSize(width: 402, height: 874)
        let long = max(screen.width, screen.height), short = min(screen.width, screen.height)
        let real = landscape ? CGSize(width: long, height: short) : CGSize(width: short, height: long)
        let drawn = sideBySide ? drawing.width : drawing.height
        guard drawn > 0 else { return 1 }
        return Double((sideBySide ? real.width : real.height) / drawn)
    }

    private func changed(_ divider: ScreenLayout.DividerFrame, _ location: CGPoint, scale k: Double) {
        let length = Double(divider.sideBySide ? divider.span.width : divider.span.height) * k
        let raw = Double(divider.sideBySide ? location.x - gap - divider.span.minX : location.y - gap - divider.span.minY) * k
        if drag?.level != divider.level {
            drag = (divider.level, divider.share, raw - divider.share * length)
        }
        guard let grab = drag?.grab else { return }
        let p = raw - grab
        drag?.share = DividerMath.tracking(p, length: length)
        let landing = DividerMath.settle(p, length: length)
        let next: Double? = landing == 0 || landing == 1 ? landing : DividerMath.nearestSnap(p, length: length)
        if next != target {
            if next != nil { Haptics.shared.tap() }
            target = next
        }
    }

    private func ended(_ divider: ScreenLayout.DividerFrame, _ location: CGPoint, scale k: Double) {
        let length = Double(divider.sideBySide ? divider.span.width : divider.span.height) * k
        let raw = Double(divider.sideBySide ? location.x - gap - divider.span.minX : location.y - gap - divider.span.minY) * k
        let p = raw - (drag?.grab ?? 0)
        let landing = DividerMath.settle(p, length: length)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if landing == 0 || landing == 1 {
                fold(divider.level, toward: landing)
            } else {
                set(landing, divider.level)
            }
            drag = nil
        }
        target = nil
    }

    /// Panes that letting go now would take away.
    private var foldingPanes: Set<Int> {
        guard let drag, let target, target == 0 || target == 1 else { return [] }
        switch drag.level {
        case .main: return target == 0 ? [0] : Set(1..<layout.panes.count)
        case .inner: return target == 0 ? [1] : [2]
        }
    }

    /// In the editor, a pane pulled off the edge is removed (on the screen it only folds).
    private func fold(_ level: ScreenLayout.DividerFrame.Level, toward end: Double) {
        Haptics.shared.play(.snap)
        switch level {
        case .main:
            if end == 0 {
                layout.removePane(at: 0)
            } else {
                while layout.panes.count > 1 { layout.removePane(at: layout.panes.count - 1) }
            }
        case .inner:
            layout.removePane(at: end == 0 ? 1 : 2)
        }
    }

    private func set(_ share: Double, _ level: ScreenLayout.DividerFrame.Level) {
        if level == .main { layout.split = share } else { layout.innerSplit = share }
    }
}
