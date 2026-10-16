import GlasspadKit
import SwiftUI

/// Layouts, like a document app's template picker: your own layouts on top (open, edit,
/// copy, delete, reorder), then templates to start a new one from.
struct LayoutGallery: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSize
    var store = LayoutStore.shared
    var router = AppRouter.shared

    @State private var draft: LayoutDraft?
    @State private var deleting: ScreenLayout?

    var body: some View {
        NavigationStack {
            List {
                if !store.layouts.isEmpty {
                    Section("Your Layouts") {
                        ForEach(store.layouts) { layout in row(layout) }
                            .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                    }
                }
                Section {
                    templateGrid
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                } header: {
                    Text("New Layout")
                } footer: {
                    Text("Start from a template, then change any pane, drag the line between them, and give it a name.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.backgroundColor.ignoresSafeArea())
            .navigationTitle("Layouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !store.layouts.isEmpty { EditButton() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(item: $draft) { draft in
            LayoutEditor(draft: draft)
                .environment(\.palette, palette)
        }
        .confirmationDialog(deleting.map { "Delete \($0.name)?" } ?? "",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { layout in
            Button("Delete Layout", role: .destructive) { store.delete(layout.id) }
        }
        .presentationDragIndicator(.visible)
        .onAppear(perform: dismissKeyboard)
    }

    private var landscape: Bool { verticalSize == .compact }

    // MARK: Your layouts

    private func row(_ layout: ScreenLayout) -> some View {
        let current = router.layoutID == layout.id
        return Button {
            Haptics.shared.tap()
            router.show(layout: layout)
        } label: {
            HStack(spacing: 14) {
                LayoutDiagram(layout: layout, landscape: landscape, showsSymbols: landscape)
                    .frame(width: 58, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(layout.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.inkColor)
                    if layout.paneSummary != layout.name {
                        Text(layout.paneSummary)
                            .font(.footnote)
                            .foregroundStyle(palette.inkSoftColor)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if current {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.inkColor)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .listRowBackground(palette.raisedColor)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { deleting = layout } label: { Label("Delete", systemImage: "trash") }
            Button { draft = LayoutDraft(layout: layout, isNew: false) } label: { Label("Edit", systemImage: "slider.horizontal.3") }
        }
        .contextMenu {
            Button { draft = LayoutDraft(layout: layout, isNew: false) } label: { Label("Edit", systemImage: "slider.horizontal.3") }
            Button { store.duplicate(layout.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Divider()
            Button(role: .destructive) { deleting = layout } label: { Label("Delete", systemImage: "trash") }
        }
        .accessibilityAddTraits(current ? .isSelected : [])
        .accessibilityHint("Opens this layout")
    }

    // MARK: Templates

    private var templateGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 12)], spacing: 12) {
            ForEach(store.templates) { template in
                Button {
                    Haptics.shared.tap()
                    draft = router.newLayout(from: template)
                } label: {
                    TemplateCard(template: template)
                }
                .buttonStyle(TileStyle())
                .accessibilityLabel(template.name)
                .accessibilityHint("Starts a new layout from this template")
            }
        }
    }
}

/// A template drawn both ways up, so it is clear how it turns with the phone.
private struct TemplateCard: View {
    @Environment(\.palette) private var palette
    let template: LayoutTemplate

    var body: some View {
        let layout = template.makeLayout()
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                LayoutDiagram(layout: layout, landscape: false)
                    .frame(height: 84)
                LayoutDiagram(layout: layout, landscape: true)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 84)
            Text(template.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.inkColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.raisedColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.lineColor))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
