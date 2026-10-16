import SwiftUI
import GlasspadKit

/// Everything that can be pinned, grouped and searchable. Tapping a ready item pins it (or
/// unpins it, when it is already pinned); items that need a detail first (a link, some text,
/// a custom keystroke) open the button editor.
struct ActionLibrary: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    var session = MacSession.shared
    @State var layout: DeckLayout
    /// The Pinned folder that is open, if any: new items go into it.
    let folder: UUID?
    let onChange: ((inout DeckLayout) -> Void) -> Void
    let onCustom: (DeckButton) -> Void
    var onRecord: () -> Void = {}

    @State private var query = ""
    @State private var appQuery = ""
    /// Apps whose icon was already asked for, so scrolling does not ask twice.
    @State private var askedIcons: Set<String> = []

    init(layout: DeckLayout, folder: UUID?, onChange: @escaping ((inout DeckLayout) -> Void) -> Void,
         onCustom: @escaping (DeckButton) -> Void, onRecord: @escaping () -> Void = {}) {
        _layout = State(initialValue: layout)
        self.folder = folder
        self.onChange = onChange
        self.onCustom = onCustom
        self.onRecord = onRecord
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty { pinnedPreview }
                if query.isEmpty { recordRow }
                ForEach(groups) { group in
                    Section(group.title) {
                        if group.id == "apps" && query.isEmpty { allAppsLink }
                        ForEach(group.items) { item in row(item) }
                    }
                    .listRowBackground(palette.raisedColor)
                }
                if groups.isEmpty {
                    Text("Nothing matches \u{201C}\(query)\u{201D}.")
                        .foregroundStyle(palette.inkSoftColor)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.backgroundColor.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
            .navigationTitle("Library")
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
            .onAppear {
                if session.dockCatalog.isEmpty { session.send(.dockCatalogRequest) }
                if session.deckCatalog == nil { session.send(.deckCatalogRequest) }
            }
        }
        .tint(palette.inkColor)
    }

    // MARK: Rows

    /// What is pinned (or in the open folder) right now, small, so each tap shows where it
    /// went. Tiles are faces only, in balanced rows.
    @ViewBuilder private var pinnedPreview: some View {
        let buttons = folder.map { id in PinnedDeck.pinned(in: layout).flattenedDeck.first { $0.id == id }?.children ?? [] }
            ?? PinnedDeck.pinned(in: layout)
        Section {
            if buttons.isEmpty {
                Text("Nothing yet. Tap something below to pin it.")
                    .font(.subheadline)
                    .foregroundStyle(palette.inkSoftColor)
            } else {
                TileGrid(preferred: 50) {
                    ForEach(buttons) { b in
                        ActionTile(title: b.title, face: b.face(icons: session.icons),
                                   folder: b.action == .folder ? (b.children ?? []).prefix(4).map { $0.face(icons: session.icons) } : nil,
                                   showsTitle: false) {}
                            .allowsHitTesting(false)
                            .accessibilityLabel(b.title)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.vertical, 6)
                .animation(.snappy, value: buttons.map(\.id))
            }
        } header: {
            Text(folder == nil ? "Pinned" : "In This Folder")
        } footer: {
            Text("Tap + to pin, tap the check to unpin.")
        }
        .listRowBackground(palette.raisedColor)
    }

    private var recordRow: some View {
        Section {
            Button {
                Haptics.shared.play(.click)
                if session.isRecordingMacro {
                    session.send(.macro(.recordStop))
                } else {
                    onRecord()
                    session.send(.macro(.recordStart(windowRelative: false, keepTiming: true)))
                }
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    LibraryGlyph(symbol: session.isRecordingMacro ? "stop.fill" : "record.circle", color: Color(uiColor: .systemRed))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.isRecordingMacro ? "Stop Recording" : "Record New Macro")
                            .foregroundStyle(palette.inkColor)
                        Text("Do the steps on your Mac; the macro is pinned here.")
                            .font(.footnote)
                            .foregroundStyle(palette.inkSoftColor)
                    }
                }
            }
            .disabled(!session.isConnected)
        }
        .listRowBackground(palette.raisedColor)
    }

    /// Every app installed on the Mac, not only the ones in its Dock.
    private var allAppsLink: some View {
        NavigationLink {
            allAppsPage
        } label: {
            HStack(spacing: 12) {
                LibraryGlyph(symbol: "square.grid.3x3.fill", color: Color(uiColor: .systemBlue))
                VStack(alignment: .leading, spacing: 1) {
                    Text("All Apps on Your Mac").foregroundStyle(palette.inkColor)
                    Text(session.dockCatalog.isEmpty ? "Search every installed app" : "\(session.dockCatalog.count) apps, searchable")
                        .font(.footnote).foregroundStyle(palette.inkSoftColor)
                }
            }
        }
    }

    private var allAppsPage: some View {
        let q = appQuery.trimmingCharacters(in: .whitespaces)
        let catalog = session.dockCatalog.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let apps = q.isEmpty ? catalog : DockArrangement.search(q, in: catalog)
        return List {
            Section {
                ForEach(apps, id: \.bundleID) { app in
                    row(.app(app))
                        .onAppear { askIcon(app.bundleID) }
                }
            } footer: {
                Text("Tap an app to pin it. Its tile opens it on your Mac.")
            }
            .listRowBackground(palette.raisedColor)
            if session.dockCatalog.isEmpty {
                Text(session.isConnected ? "Asking your Mac for its apps…" : "Connect to your Mac to see its apps.")
                    .foregroundStyle(palette.inkSoftColor)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.backgroundColor.ignoresSafeArea())
        .searchable(text: $appQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Apps")
        .navigationTitle("All Apps")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if session.dockCatalog.isEmpty { session.send(.dockCatalogRequest) } }
    }

    private func askIcon(_ id: String) {
        guard session.icons.image(for: id) == nil, askedIcons.insert(id).inserted else { return }
        session.send(.dockIconRequest(bundleIDs: [id]))
    }

    private func row(_ item: LibraryItem) -> some View {
        let pinned = item.isReady && PinnedDeck.isPinned(item.button.action, in: layout)
        return Button {
            pick(item, pinned: pinned)
        } label: {
            HStack(spacing: 12) {
                if let id = item.appID {
                    DockIcon(app: DockApp(bundleID: id, name: item.title, running: false, active: false),
                             icon: session.icons.image(for: id), size: 30)
                } else if let link = item.button.action.websiteLink {
                    WebsiteLogo(link: link, tint: item.button.tint, size: 30)
                } else {
                    LibraryGlyph(symbol: item.button.symbol, color: Color(hexString: item.button.color) ?? .gray)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).foregroundStyle(palette.inkColor)
                    if !item.detail.isEmpty {
                        Text(item.detail).font(.footnote).foregroundStyle(palette.inkSoftColor).lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                trailing(item, pinned: pinned)
            }
            .contentShape(Rectangle())
        }
        .accessibilityValue(pinned ? "Pinned" : "")
        .accessibilityHint(item.isReady ? (pinned ? "Unpins it" : "Pins it") : "Opens the editor")
    }

    @ViewBuilder private func trailing(_ item: LibraryItem, pinned: Bool) -> some View {
        if !item.isReady {
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.inkSoftColor)
        } else if pinned {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(palette.inkColor)
                .contentTransition(.symbolEffect(.replace))
        } else {
            Image(systemName: "plus.circle")
                .font(.title3)
                .foregroundStyle(palette.inkSoftColor)
                .contentTransition(.symbolEffect(.replace))
        }
    }

    private func pick(_ item: LibraryItem, pinned: Bool) {
        guard item.isReady else {
            Haptics.shared.tap()
            onCustom(item.button)
            return
        }
        Haptics.shared.play(.snap)
        let change: (inout DeckLayout) -> Void
        if pinned {
            let action = item.button.action
            change = { l in
                if let b = PinnedDeck.pinned(in: l).flattenedDeck.first(where: { $0.action == action }) { l.remove(id: b.id) }
            }
        } else {
            let button = DeckButton(title: item.button.title, symbol: item.button.symbol, action: item.button.action,
                                    color: item.button.color)
            let folder = folder
            change = { l in l = PinnedDeck.pin(button, in: l, folder: folder) }
        }
        withAnimation(.snappy) { change(&layout) }
        onChange(change)
    }

    // MARK: Groups

    private var groups: [LibraryGroup] {
        let all = allGroups
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.compactMap { g in
            let items: [LibraryItem]
            if g.id == "apps" {
                items = DockArrangement.search(q, in: session.dockApps + session.dockCatalog).prefix(30).map(LibraryItem.app)
            } else {
                items = g.items.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.detail.localizedCaseInsensitiveContains(q)
                    || g.title.localizedCaseInsensitiveContains(q) }
            }
            return items.isEmpty ? nil : LibraryGroup(id: g.id, title: g.title, items: items)
        }
    }

    private var allGroups: [LibraryGroup] {
        let templates = Dictionary(ActionCategory.all.map { ($0.id, $0.items) }, uniquingKeysWith: { a, _ in a })
        func from(_ ids: [String]) -> [LibraryItem] {
            ids.flatMap { templates[$0] ?? [] }.map { t in
                let ready: Bool = switch t.action {
                case .setAudioOutput, .runShortcut(name: ""): false
                default: true
                }
                return LibraryItem(id: "t.\(t.id)", title: t.title, detail: t.detail, isReady: ready,
                                   button: DeckButton(title: t.title, symbol: t.symbol, action: t.action, color: t.color))
            }
        }
        var seen = Set<String>()
        let apps = session.dockApps.filter { seen.insert($0.bundleID).inserted }.map(LibraryItem.app)
        let macros = (session.allMacros ?? []).map { m in
            LibraryItem(id: "m.\(m.id)", title: m.name, detail: "\(m.stepCount) step\(m.stepCount == 1 ? "" : "s")", isReady: true,
                        button: PinnedDeck.button(for: m))
        }
        let shortcuts = (session.deckCatalog?.shortcuts ?? []).map { name in
            LibraryItem(id: "s.\(name)", title: name, detail: "", isReady: true,
                        button: DeckButton(title: name, symbol: "square.stack.3d.up.fill", action: .runShortcut(name: name), color: "#FF2D55"))
        } + [LibraryItem(id: "s.other", title: "Other Shortcut", detail: "Type its name", isReady: false,
                         button: DeckButton(title: "", symbol: "square.stack.3d.up.fill", action: .runShortcut(name: ""), color: "#FF2D55"))]
        let keys = LibraryItem.keystrokes + [
            LibraryItem(id: "k.custom", title: "Custom Keystroke", detail: "Any keys, like ⌥⌘N", isReady: false,
                        button: DeckButton(title: "", symbol: "command", action: .keystroke(Keystroke(key: .character("n"), modifiers: [.command, .option])),
                                           color: "#5E5CE6")),
        ]
        let text = [LibraryItem(id: "x.type", title: "Type Text", detail: "A signature, an address, a reply", isReady: false,
                                button: DeckButton(title: "", symbol: "text.cursor", action: .typeText(""), color: "#5E5CE6"))]
        let open = [
            LibraryItem(id: "o.url", title: "Website", detail: "Opens in the Mac's browser, with the site's logo", isReady: false,
                        button: DeckButton(title: "", symbol: "globe", action: .openURL("https://"), color: "#0A84FF")),
            LibraryItem(id: "o.file", title: "File or Folder", detail: "Anything in Finder", isReady: false,
                        button: DeckButton(title: "", symbol: "folder.fill", action: .openFile(path: "~/Downloads"), color: "#34C759")),
        ] + SettingsPanes.all.map { name, pane in
            LibraryItem(id: "o.pane.\(pane)", title: "\(name) Settings", detail: "", isReady: true,
                        button: DeckButton(title: name, symbol: "gearshape.fill", action: .openURL(SettingsPanes.prefix + pane), color: "#8E8E93"))
        }
        let organize = [LibraryItem(id: "f.new", title: "New Folder", detail: "Group pinned buttons", isReady: false,
                                    button: DeckButton(title: "Folder", symbol: "folder.fill", action: .folder, color: "#8E8E93", children: []))]
        let all: [LibraryGroup] = [
            LibraryGroup(id: "apps", title: "Apps", items: apps),
        ] + DeckSystemGroup.allCases.map { g in
            // Mac controls, grouped the way the catalog groups them.
            LibraryGroup(id: "sys.\(g.rawValue)", title: g == .mac ? "Mac Controls" : g.title, items: from([g.rawValue]))
        } + [
            LibraryGroup(id: "macros", title: "Macros", items: macros),
            LibraryGroup(id: "shortcuts", title: "Shortcuts", items: shortcuts),
            LibraryGroup(id: "keys", title: "Keystrokes", items: keys),
            LibraryGroup(id: "text", title: "Text", items: text),
            LibraryGroup(id: "shots", title: "Screenshots", items: from(["screen"])),
            LibraryGroup(id: "open", title: "Open", items: open),
            LibraryGroup(id: "organize", title: "Organize", items: organize),
        ]
        return all.filter { !$0.items.isEmpty || $0.id == "apps" }
    }
}

struct LibraryGroup: Identifiable {
    let id: String
    let title: String
    let items: [LibraryItem]
}

struct LibraryItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    /// Pinned with one tap. Otherwise the editor opens to finish it.
    let isReady: Bool
    let button: DeckButton
    var appID: String? = nil

    static func app(_ app: DockApp) -> LibraryItem {
        LibraryItem(id: "a.\(app.bundleID)", title: app.name, detail: "", isReady: true,
                    button: DeckButton(title: app.name, symbol: "app", action: .openApp(bundleID: app.bundleID), color: "#0A84FF"),
                    appID: app.bundleID)
    }

    static let keystrokes: [LibraryItem] = {
        func k(_ title: String, _ symbol: String, _ key: Key, _ mods: KeyModifiers, _ shown: String) -> LibraryItem {
            LibraryItem(id: "k.\(title)", title: title, detail: shown, isReady: true,
                        button: DeckButton(title: title, symbol: symbol, action: .keystroke(Keystroke(key: key, modifiers: mods)), color: "#5E5CE6"))
        }
        return [
            k("Copy", "doc.on.doc", .character("c"), [.command], "⌘C"),
            k("Paste", "doc.on.clipboard", .character("v"), [.command], "⌘V"),
            k("Undo", "arrow.uturn.backward", .character("z"), [.command], "⌘Z"),
            k("Redo", "arrow.uturn.forward", .character("z"), [.command, .shift], "⇧⌘Z"),
            k("Select All", "selection.pin.in.out", .character("a"), [.command], "⌘A"),
            k("Find", "magnifyingglass", .character("f"), [.command], "⌘F"),
            k("Spotlight", "magnifyingglass.circle", .special(.space), [.command], "⌘Space"),
            k("New Tab", "plus.square.on.square", .character("t"), [.command], "⌘T"),
            k("Close Window", "xmark.square", .character("w"), [.command], "⌘W"),
            k("Switch Apps", "rectangle.2.swap", .special(.tab), [.command], "⌘Tab"),
        ]
    }()
}

/// The small rounded-square symbol Settings uses for rows.
struct LibraryGlyph: View {
    @Environment(\.palette) private var palette
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: UIImage(systemName: symbol) == nil ? "square.dashed" : symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(palette.monochrome ? palette.backgroundColor : .white)
            .frame(width: 30, height: 30)
            .background(palette.tint(color), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Which of the front app's buttons show in Actions, and in what order. Also where the app's
/// own buttons are added and edited.
struct FrontAppButtonsSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    var session = MacSession.shared
    let appName: String
    let buttons: [DeckButton]
    let macros: [MacroSummary]
    @Binding var picks: [String]?
    let onEdit: (DeckButton) -> Void
    let onAdd: () -> Void

    @State private var shown: [FrontAppItem] = []
    @State private var loaded = false

    private var all: [FrontAppItem] { PinnedDeck.allFrontAppItems(buttons: buttons, macros: macros) }
    private var hidden: [FrontAppItem] { all.filter { item in !shown.contains { $0.id == item.id } } }
    private var full: Bool { shown.count >= PinnedDeck.frontAppLimit }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(shown) { item in row(item, shown: true) }
                        .onMove { shown.move(fromOffsets: $0, toOffset: $1); save() }
                        .onDelete { shown.remove(atOffsets: $0); save() }
                    if shown.isEmpty {
                        Text("Nothing shows for \(appName).").foregroundStyle(palette.inkSoftColor)
                    }
                } header: {
                    Text("Shown")
                } footer: {
                    Text("Up to \(PinnedDeck.frontAppLimit). Drag to reorder.")
                }
                .listRowBackground(palette.raisedColor)
                if !hidden.isEmpty {
                    Section("More for \(appName)") {
                        ForEach(hidden) { item in row(item, shown: false) }
                    }
                    .listRowBackground(palette.raisedColor)
                }
                Section {
                    Button("New Button for \(appName)", systemImage: "plus") { onAdd() }
                        .disabled(!session.isConnected)
                } footer: {
                    Text("Buttons made here belong to \(appName) and only show while it is in front on your Mac. Macros come from the app's macro profile on the Mac.")
                }
                .listRowBackground(palette.raisedColor)
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(palette.backgroundColor.ignoresSafeArea())
            .navigationTitle(appName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        picks = nil
                        shown = PinnedDeck.frontAppItems(buttons: buttons, macros: macros, picks: nil)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if #available(iOS 26.0, *) {
                        Button("Done", systemImage: "checkmark", role: .confirm) { dismiss() }
                    } else {
                        Button("Done") { dismiss() }.fontWeight(.semibold)
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                shown = PinnedDeck.frontAppItems(buttons: buttons, macros: macros, picks: picks)
            }
            // The Mac's buttons and macros can arrive after the sheet opened. Until the user
            // has picked, follow the default list, the same one the screen shows.
            .onChange(of: all.map(\.id)) {
                if picks == nil { shown = PinnedDeck.frontAppItems(buttons: buttons, macros: macros, picks: nil) }
            }
        }
        .tint(palette.inkColor)
    }

    private func row(_ item: FrontAppItem, shown isShown: Bool) -> some View {
        HStack(spacing: 12) {
            if !isShown {
                Button {
                    Haptics.shared.tap()
                    withAnimation(.snappy) { shown.append(item) }
                    save()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(uiColor: .systemGreen))
                }
                .buttonStyle(.plain)
                .disabled(full)
                .accessibilityLabel("Show \(title(item))")
            }
            LibraryGlyph(symbol: symbol(item), color: tint(item))
            VStack(alignment: .leading, spacing: 1) {
                Text(title(item)).foregroundStyle(palette.inkColor)
                Text(kind(item)).font(.footnote).foregroundStyle(palette.inkSoftColor)
            }
            Spacer(minLength: 8)
            if case .button(let b) = item {
                Button {
                    onEdit(b)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundStyle(palette.inkSoftColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(b.title)")
            }
        }
    }

    private func save() { picks = shown.map(\.id) }

    private func title(_ item: FrontAppItem) -> String {
        switch item {
        case .button(let b): b.title
        case .macro(let m): m.name
        }
    }

    private func symbol(_ item: FrontAppItem) -> String {
        switch item {
        case .button(let b): b.symbol
        case .macro(let m): m.symbol
        }
    }

    private func tint(_ item: FrontAppItem) -> Color {
        switch item {
        case .button(let b): b.tint
        case .macro(let m): m.tint
        }
    }

    private func kind(_ item: FrontAppItem) -> String {
        switch item {
        case .button(let b): ActionCategory.template(for: b.action)?.title ?? "Button"
        case .macro(let m): "Macro, \(m.stepCount) step\(m.stepCount == 1 ? "" : "s")"
        }
    }
}
