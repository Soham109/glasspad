import GlasspadKit
import SwiftUI

/// The layouts in the mode menu, under the modes: one tap opens a layout, a long press
/// edits, copies or deletes it, and the + at the end of the "Layouts" line makes a new one
/// (a tile for it would sit alone on a row after five). With no layouts yet it is a single
/// quiet "New Layout" tile. The tiles are the menu's own (`MenuTile`).
struct LayoutMenuRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.verticalSizeClass) private var verticalSize
    var store = LayoutStore.shared
    var router = AppRouter.shared
    let close: () -> Void

    @State private var deleting: ScreenLayout?

    var body: some View {
        Group {
            if store.layouts.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: ModeSwitcher.tileSpacing), count: Self.columns),
                          spacing: ModeSwitcher.tileSpacing) {
                    newTile
                }
            } else {
                VStack(spacing: 2) {
                    header
                    if store.layouts.count <= Self.columns * 2 {
                        // In the modes' five columns: one row, or two.
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: ModeSwitcher.tileSpacing), count: Self.columns),
                                  spacing: ModeSwitcher.tileSpacing) {
                            ForEach(store.layouts) { layout in tile(layout, width: nil) }
                        }
                    } else {
                        // Many layouts scroll sideways; the last one showing is cut by the edge,
                        // which says there are more.
                        ScrollView(.horizontal) {
                            HStack(spacing: ModeSwitcher.tileSpacing) {
                                ForEach(store.layouts) { layout in tile(layout, width: Self.scrollingWidth) }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .scrollBounceBehavior(.basedOnSize)
                    }
                }
            }
        }
        .confirmationDialog(deleting.map { "Delete \($0.name)?" } ?? "",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { layout in
            Button("Delete Layout", role: .destructive) { store.delete(layout.id) }
        }
    }

    private var landscape: Bool { verticalSize == .compact }

    /// The modes' columns, so each layout sits under a mode.
    static let columns = 5
    /// Tile width when scrolling: four and a half show.
    static let scrollingWidth: CGFloat = (ModeSwitcher.contentWidth - ModeSwitcher.tileSpacing * 4) / 4.5

    private func tile(_ layout: ScreenLayout, width: CGFloat?) -> some View {
        let current = router.layoutID == layout.id
        return Button {
            Haptics.shared.tap()
            router.show(layout: layout)
            close()
        } label: {
            MenuTile(title: layout.name, selected: current) {
                // Drawn the way the screen splits now, in the modes' colours.
                LayoutDiagram(layout: layout, landscape: landscape, showsSymbols: false, vivid: true)
                    .frame(height: landscape ? 22 : 30)
            }
            .frame(width: width)
        }
        .buttonStyle(TileStyle())
        .contextMenu {
            Button { edit(layout) } label: { Label("Edit", systemImage: "slider.horizontal.3") }
            Button {
                Haptics.shared.tap()
                store.duplicate(layout.id)
            } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Divider()
            Button(role: .destructive) { deleting = layout } label: { Label("Delete", systemImage: "trash") }
        } preview: {
            LayoutPreviewCard(layout: layout)
                .environment(\.palette, palette)
        }
        .accessibilityLabel("\(layout.name) layout")
        .accessibilityValue(layout.paneSummary)
        .accessibilityAddTraits(current ? .isSelected : [])
        .accessibilityHint("Touch and hold to edit")
        .accessibilityAction(named: "Edit") { edit(layout) }
    }

    private var newTile: some View {
        Button(action: openGallery) {
            MenuTile(title: "New Layout", soft: true) {
                Image(systemName: "plus")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(palette.inkSoftColor)
            }
        }
        .buttonStyle(TileStyle())
        .accessibilityLabel("New Layout")
        .accessibilityHint("Puts two or three modes on one screen")
    }

    /// "Layouts", with a small + at its end for a new one.
    private var header: some View {
        HStack {
            Text("Layouts")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.inkSoftColor)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button(action: openGallery) {
                Image(systemName: "plus")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.inkColor)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(palette.inkColor.opacity(palette.isDark ? 0.14 : 0.07)))
                    .frame(width: 44, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TileStyle())
            .accessibilityLabel("New Layout")
            .accessibilityHint("Make a new layout or change your layouts")
        }
        // The word lines up with the round button in the menu's top corner, the + with the one
        // at the other end.
        .padding(.leading, 4)
    }

    private func openGallery() {
        Haptics.shared.tap()
        close()
        router.showLayouts = true
        ScreenAwake.update()
    }

    private func edit(_ layout: ScreenLayout) {
        close()
        router.layoutDraft = LayoutDraft(layout: layout, isNew: false)
        ScreenAwake.update()
    }
}

/// The long-press preview: the layout drawn large, in both orientations.
struct LayoutPreviewCard: View {
    @Environment(\.palette) private var palette
    let layout: ScreenLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 14) {
                LayoutDiagram(layout: layout, landscape: false)
                    .frame(height: 150)
                LayoutDiagram(layout: layout, landscape: true)
                    .frame(width: 170)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(layout.name)
                    .font(.headline)
                    .foregroundStyle(palette.inkColor)
                Text(layout.paneSummary)
                    .font(.footnote)
                    .foregroundStyle(palette.inkSoftColor)
            }
        }
        .padding(18)
        .background { SurfaceBackground() }
    }
}
