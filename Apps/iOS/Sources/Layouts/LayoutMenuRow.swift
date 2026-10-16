import GlasspadKit
import SwiftUI

/// The layouts in the mode menu, under the modes: one tap opens a layout, a long press
/// edits, copies or deletes it, and the last tile makes a new one. With no layouts yet it is
/// a single quiet "New Layout" button.
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
                Button(action: openGallery) {
                    Label("New Layout", systemImage: "rectangle.split.2x1")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.inkColor)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(palette.inkColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(TileStyle())
                .accessibilityHint("Puts two or three modes on one screen")
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(store.layouts) { layout in tile(layout) }
                        newTile
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .confirmationDialog(deleting.map { "Delete \($0.name)?" } ?? "",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { layout in
            Button("Delete Layout", role: .destructive) { store.delete(layout.id) }
        }
    }

    private var landscape: Bool { verticalSize == .compact }

    private func tile(_ layout: ScreenLayout) -> some View {
        let current = router.layoutID == layout.id
        return Button {
            Haptics.shared.tap()
            router.show(layout: layout)
            close()
        } label: {
            VStack(spacing: 6) {
                LayoutDiagram(layout: layout, landscape: landscape, showsSymbols: landscape)
                    .frame(height: landscape ? 24 : 34)
                    .frame(height: 34)
                Text(layout.name)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(palette.inkColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 6)
            .frame(width: 78, height: 68)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.inkColor.opacity(current ? 0.10 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.inkSoftColor)
                    .frame(height: 34)
                Text("New")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(palette.inkSoftColor)
            }
            .frame(width: 56, height: 68)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(palette.inkColor.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(TileStyle())
        .accessibilityLabel("Layouts")
        .accessibilityHint("Make a new layout or change your layouts")
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
        .background(palette.backgroundColor)
    }
}
