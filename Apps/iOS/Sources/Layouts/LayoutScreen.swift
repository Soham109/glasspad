import GlasspadKit
import SwiftUI
import UIKit

/// A layout on screen: its panes, each a full mode, with a line between them to drag.
///
/// Dragging the line resizes the panes the way iPad split view does: while the finger is
/// down each pane shows a calm placeholder and the modes keep their size, then they lay out
/// once at the new size. The line rests on thirds and the middle with a light tick, a pane
/// pulled past the edge folds away (its line stays at the edge to pull it back), and a double
/// tap puts the line back in the middle.
///
/// The screen lays itself out edge to edge and gives each pane the safe area of the screen
/// edges it touches, so the trackpad runs to the glass while other modes keep clear of the
/// Dynamic Island and the home indicator. The keyboard is handled here too: the panes share
/// what is left above it.
struct LayoutScreen: View {
    @Environment(\.palette) private var palette
    let layout: ScreenLayout
    /// The screen's safe area, read outside this view (which ignores it).
    let safeArea: EdgeInsets
    var router = AppRouter.shared
    var store = LayoutStore.shared
    var session = MacSession.shared

    @State private var drag: DividerDrag?
    @State private var keyboard = KeyboardHeight()

    static let gap: CGFloat = 8
    static let corner: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let full = geo.size
            let keyboardHeight = keyboard.height
            let area = CGSize(width: full.width, height: max(0, full.height - keyboardHeight))
            let committed = layout.arrangement(in: area, gap: Self.gap)
            let shown = displayed.arrangement(in: area, gap: Self.gap)
            let split = shown.panes.count > 1
            ZStack(alignment: .topLeading) {
                // The gap between panes.
                (split ? wellColor : palette.backgroundColor)
                    .frame(width: full.width, height: full.height)
                ForEach(shown.panes, id: \.index) { pane in
                    let mode = layout.mode(at: pane.index)
                    let resting = committed.panes.first { $0.index == pane.index }?.rect
                    LayoutPane(mode: mode,
                               frame: pane.rect,
                               contentSize: resting?.size,
                               insets: insets(for: pane.rect, in: area, keyboardUp: keyboardHeight > 0),
                               rounded: split,
                               resizing: drag != nil,
                               folding: drag?.folds(pane: pane.index, in: layout) ?? false)
                        .offset(x: pane.rect.minX, y: pane.rect.minY)
                }
                ForEach(Array(shown.dividers.enumerated()), id: \.offset) { _, divider in
                    DividerHandle(divider: placed(divider, in: area),
                                  active: drag?.level == divider.level,
                                  onChange: { dragged(divider, to: $0) },
                                  onEnd: { released(divider, at: $0) },
                                  onReset: { reset(divider) },
                                  onStep: { step(divider, by: $0) })
                }
            }
            .frame(width: full.width, height: full.height, alignment: .topLeading)
            .coordinateSpace(name: LayoutCoordinates.name)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: drag == nil)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: layout)
            .animation(.easeOut(duration: 0.25), value: keyboardHeight)
        }
        .ignoresSafeArea()
        #if DEBUG
        .onAppear {
            // -GPLayoutDragDemo <share>: shows the main line held there, for screenshots.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-GPLayoutDragDemo"), i + 1 < args.count, let share = Double(args[i + 1]) {
                drag = DividerDrag(level: .main, share: share, fromFold: false, grab: 0, target: nil,
                                   foldTarget: share < 0.1 ? 0 : share > 0.9 ? 1 : nil)
            }
        }
        #endif
        // The Mac follows one pane; a Dock pane it does not follow asks for the list again
        // every few seconds, so running apps stay current. Stops when the pane or link goes.
        // A Mac that reads `modesShown` pushes Dock changes to every pane, so it needs no asking.
        .task(id: refreshesDock && session.isConnected) {
            guard refreshesDock && session.isConnected else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.dockRefresh))
                guard !Task.isCancelled else { return }
                session.requestDock()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) {
            keyboard.update($0)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboard.height = 0
        }
    }

    /// Seconds between Dock list requests for a Dock pane the Mac does not follow.
    static let dockRefresh: Double = 3

    private var refreshesDock: Bool {
        LayoutWirePlan(modes: layout.shownModes.map(\.wireMode)).refreshesDock
            && session.macStatus?.followsAllPanes != true
    }

    /// Light: a soft grey line. Dark: the panes sit a shade apart on a slightly lighter well.
    private var wellColor: Color { palette.isDark ? palette.raisedColor : palette.raisedPressedColor }

    /// The layout with the line under the finger where the finger has it.
    private var displayed: ScreenLayout {
        guard let drag else { return layout }
        var l = layout
        switch drag.level {
        case .main: l.split = drag.share
        case .inner: l.innerSplit = drag.share
        }
        return l
    }

    /// Screen safe area for a pane: only on the screen edges it touches. With the keyboard up,
    /// the bottom edge is the keyboard's, which needs no extra room.
    private func insets(for rect: CGRect, in area: CGSize, keyboardUp: Bool) -> EdgeInsets {
        let e: CGFloat = 0.5
        return EdgeInsets(top: rect.minY <= e ? safeArea.top : 0,
                          leading: rect.minX <= e ? safeArea.leading : 0,
                          bottom: rect.maxY >= area.height - e && !keyboardUp ? safeArea.bottom : 0,
                          trailing: rect.maxX >= area.width - e ? safeArea.trailing : 0)
    }

    /// A folded pane's line, moved in from the very edge so it stays clear of the Dynamic
    /// Island, the mode pill's touch strip and the home indicator.
    private func placed(_ divider: ScreenLayout.DividerFrame, in area: CGSize) -> ScreenLayout.DividerFrame {
        guard divider.share <= 0 || divider.share >= 1 else { return divider }
        var d = divider
        let start = divider.share <= 0
        if divider.sideBySide {
            if start, d.rect.minX <= 0.5 { d.rect.origin.x += safeArea.leading }
            if !start, d.rect.maxX >= area.width - 0.5 { d.rect.origin.x -= safeArea.trailing }
        } else {
            if start, d.rect.minY <= 0.5 { d.rect.origin.y += max(safeArea.top, 24) }
            if !start, d.rect.maxY >= area.height - 0.5 { d.rect.origin.y -= safeArea.bottom }
        }
        return d
    }

    // MARK: Dragging

    /// `location` is the finger along the divider's span, from its start.
    private func dragged(_ divider: ScreenLayout.DividerFrame, to location: CGFloat) {
        let length = Double(divider.sideBySide ? divider.span.width : divider.span.height)
        if drag?.level != divider.level {
            // Where on the line the finger landed, so the line does not jump under it.
            drag = DividerDrag(level: divider.level, share: divider.share,
                               fromFold: divider.share <= 0 || divider.share >= 1,
                               grab: Double(location) - divider.share * length)
        }
        guard var d = drag else { return }
        let p = Double(location) - d.grab
        d.share = DividerMath.tracking(p, length: length, resists: !d.fromFold || isBetweenMinimums(p, length))
        if d.fromFold && isBetweenMinimums(p, length) { d.fromFold = false }
        // A light tick when the line reaches a resting place: a third, the middle, or a fold.
        let landing = DividerMath.settle(p, length: length)
        let target: Double? = landing == 0 || landing == 1 ? landing : DividerMath.nearestSnap(p, length: length)
        if target != d.target {
            if target != nil { Haptics.shared.tap() }
            d.target = target
        }
        d.foldTarget = landing == 0 || landing == 1 ? landing : nil
        drag = d
    }

    private func isBetweenMinimums(_ p: Double, _ length: Double) -> Bool {
        p >= min(DividerMath.minimumPane, length / 2) && p <= max(length - DividerMath.minimumPane, length / 2)
    }

    private func released(_ divider: ScreenLayout.DividerFrame, at location: CGFloat) {
        let length = Double(divider.sideBySide ? divider.span.width : divider.span.height)
        let wasFold = divider.share <= 0 || divider.share >= 1
        let p = Double(location) - (drag?.grab ?? 0)
        var final = DividerMath.settle(p, length: length)
        // Pulled only a little out of a fold: it stays folded.
        if wasFold, final != 0, final != 1, abs(p - divider.share * length) < DividerMath.minimumPane * 0.5 {
            final = divider.share
        }
        commit(final, divider)
        drag = nil
    }

    private func reset(_ divider: ScreenLayout.DividerFrame) {
        Haptics.shared.tap()
        commit(0.5, divider)
    }

    /// VoiceOver: swipe up or down to move the line between its resting places.
    private func step(_ divider: ScreenLayout.DividerFrame, by direction: Int) {
        let stops: [Double] = [0, 1.0 / 3, 0.5, 2.0 / 3, 1]
        let current = stops.enumerated().min { abs($0.element - divider.share) < abs($1.element - divider.share) }?.offset ?? 2
        let next = stops[min(max(current + direction, 0), stops.count - 1)]
        commit(next, divider)
    }

    private func commit(_ share: Double, _ divider: ScreenLayout.DividerFrame) {
        let before = layout.visiblePaneIndices
        store.setShare(share, level: divider.level, of: layout.id)
        if store.layout(layout.id)?.visiblePaneIndices != before { router.layoutPanesChanged() }
    }
}

/// The line being dragged.
private struct DividerDrag: Equatable {
    var level: ScreenLayout.DividerFrame.Level
    var share: Double
    /// Started from a folded edge: moves freely until it is a real pane again.
    var fromFold: Bool
    /// The finger's distance from the line when it landed.
    var grab: Double
    /// The resting place the line would land on now, for the tick.
    var target: Double?
    /// 0 or 1 when letting go now would fold a side away.
    var foldTarget: Double?

    /// Whether letting go now folds this pane away.
    func folds(pane index: Int, in layout: ScreenLayout) -> Bool {
        guard let foldTarget else { return false }
        switch level {
        case .main:
            // Share 0 folds the first pane; share 1 folds everything after it.
            return foldTarget == 0 ? index == 0 : index != 0
        case .inner:
            return foldTarget == 0 ? index == 1 : index == 2
        }
    }
}

/// The keyboard's height over the bottom of the screen.
private struct KeyboardHeight: Equatable {
    var height: CGFloat = 0

    @MainActor mutating func update(_ note: Notification) {
        guard let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let screen = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first?.screen
        else { return }
        let overlap = max(0, screen.bounds.maxY - end.minY)
        // A floating or undocked keyboard does not reach the bottom edge; leave the panes alone.
        height = end.maxY >= screen.bounds.maxY - 1 ? overlap : 0
    }
}

// MARK: - Pane

/// One pane: the mode itself, clipped to its frame, with the mode's extras (the trackpad's
/// connection status, Present's dimming).
private struct LayoutPane: View {
    @Environment(\.palette) private var palette
    let mode: AppMode
    let frame: CGRect
    /// The size the mode was laid out at before the drag started (nil for a pane coming back
    /// out of a fold, which shows only its placeholder until the drag ends).
    let contentSize: CGSize?
    let insets: EdgeInsets
    let rounded: Bool
    let resizing: Bool
    let folding: Bool
    var router = AppRouter.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: rounded ? LayoutScreen.corner : 0, style: .continuous)
        ZStack(alignment: .topLeading) {
            SurfaceBackground()
            if let contentSize {
                content
                    .frame(width: resizing ? contentSize.width : frame.width,
                           height: resizing ? contentSize.height : frame.height)
            }
            if resizing || contentSize == nil {
                placeholder
                    .transition(.opacity)
            }
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .clipShape(shape)
        .contentShape(shape)
        .opacity(folding ? 0.55 : 1)
        .scaleEffect(folding ? 0.97 : 1)
        .animation(.easeOut(duration: 0.18), value: folding)
    }

    private var content: some View {
        ZStack {
            ModeScreen(mode: mode)
            if mode == .trackpad {
                TrackpadStatus()
                TrackpadNotices()
            }
            if mode == .present && router.isDimmed {
                Color.black.opacity(0.6)
                    .onTapGesture { router.noteActivity() }
                    .transition(.opacity)
                    .accessibilityLabel("Screen dimmed. Double tap to wake.")
            }
        }
        .safeAreaPadding(insets)
        .environment(\.inLayoutPane, true)
        // Only a pane along the top edge sits under the mode pill: it keeps the screen's room
        // for it (set by RootView); any other pane starts near its own top.
        .transformEnvironment(\.modeTopClearance) { if !(insets.top > 0 || frame.minY <= 0.5) { $0 = 14 } }
        // Size classes follow the pane, not the phone: a short pane wide enough for two
        // columns lays out the way the mode does sideways, any other the way it does upright.
        .environment(\.verticalSizeClass, compact ? .compact : .regular)
        .environment(\.horizontalSizeClass, .compact)
        .id(mode)
    }

    /// The Keyboard's short layout (one row of keys) suits any short pane, since the system
    /// keyboard takes the space below it anyway.
    private var compact: Bool {
        if mode == .keys { return frame.height < 420 }
        return frame.height < 500 && frame.width >= 560
    }

    /// What a pane shows while it is being resized: its mode's symbol on the surface.
    private var placeholder: some View {
        ZStack {
            SurfaceBackground()
            mode.accent(palette).opacity(palette.isDark ? 0.10 : 0.06)
            VStack(spacing: 8) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(mode.accent(palette))
                Text(mode.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.inkSoftColor)
            }
            .opacity(min(frame.width, frame.height) > 90 ? 1 : 0)
        }
        .frame(width: frame.width, height: frame.height)
        .accessibilityHidden(true)
    }
}

// MARK: - Divider

/// The line between two panes: a small grabber in a gap, with a wider touch area.
private struct DividerHandle: View {
    @Environment(\.palette) private var palette
    let divider: ScreenLayout.DividerFrame
    let active: Bool
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat) -> Void
    let onReset: () -> Void
    let onStep: (Int) -> Void

    /// Touches this far either side of the line still grab it.
    private let reach: CGFloat = 12

    var body: some View {
        let r = divider.rect
        let across = divider.sideBySide
        let folded = divider.share <= 0 || divider.share >= 1
        Capsule()
            .fill(palette.inkColor.opacity(active ? 0.55 : (folded ? 0.38 : 0.26)))
            .frame(width: across ? (active ? 5 : 4) : (active ? 56 : 40),
                   height: across ? (active ? 56 : 40) : (active ? 5 : 4))
            .frame(width: r.width, height: r.height)
            .frame(width: across ? r.width + reach * 2 : r.width, height: across ? r.height : r.height + reach * 2)
            .contentShape(Rectangle())
            .offset(x: across ? r.minX - reach : r.minX, y: across ? r.minY : r.minY - reach)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(LayoutCoordinates.name))
                    .onChanged { onChange(position($0.location)) }
                    .onEnded { onEnd(position($0.predictedEndLocation.blended(with: $0.location))) }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { onReset() })
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: active)
            .accessibilityElement()
            .accessibilityLabel("Divider")
            .accessibilityValue(folded ? "One side folded away" : "\(Int((divider.share * 100).rounded())) percent")
            .accessibilityHint("Swipe up or down to resize. Double tap to make both sides even.")
            .accessibilityAdjustableAction { direction in
                onStep(direction == .increment ? 1 : -1)
            }
            .accessibilityAction { onReset() }
    }

    /// The finger's place along the span, from its start, centred on the line.
    private func position(_ location: CGPoint) -> CGFloat {
        divider.sideBySide ? location.x - divider.span.minX : location.y - divider.span.minY
    }
}

/// The coordinate space dividers measure drags in (the whole layout).
enum LayoutCoordinates {
    static let name = "layout"
}

private extension CGPoint {
    /// A little of the flick's momentum, so a quick throw toward an edge folds the pane.
    func blended(with other: CGPoint) -> CGPoint {
        CGPoint(x: other.x + (x - other.x) * 0.25, y: other.y + (y - other.y) * 0.25)
    }
}
