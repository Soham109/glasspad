import SwiftUI
import UniformTypeIdentifiers
import GlasspadKit

/// The page Actions is showing.
enum ActionsPage: Hashable {
    /// Buttons for whatever app is in front on the Mac (macro profile + linked Deck pages).
    case frontApp
    /// One Deck page (the Mac page, My Buttons, or one the user made).
    case deck(UUID)
    case clipboard
    case present
}

/// Actions: Deck, Macros, Clipboard and Present in one place. It opens on the page for the
/// app in front on the Mac and follows it as you switch apps. With `deckOnly` it is the
/// standalone Deck mode (for people who split Actions up in Settings).
struct ActionsMode: View {
    @Environment(\.palette) private var palette
    @Environment(\.verticalSizeClass) private var verticalSize
    @Bindable var settings = PhoneSettings.shared
    var session = MacSession.shared
    var router = AppRouter.shared
    var deckOnly = false

    private var compact: Bool { verticalSize == .compact }

    @State private var page: ActionsPage = .frontApp
    @State private var editing = false
    @State private var folderPath: [UUID] = []
    @State private var editorTarget: EditorTarget?
    @State private var confirming: DeckButton?
    @State private var dragging: UUID?
    @State private var showPages = false
    @State private var presenting = false

    private var accent: Color { AppMode.actions.accent(palette) }

    /// The Mac's Deck, or one page made from an older Mac's flat list.
    private var layout: DeckLayout? {
        if let l = session.deckLayout { return l }
        guard let flat = session.deckButtons else { return nil }
        return DeckLayout(pages: [DeckPage(title: "Buttons", buttons: flat)])
    }

    private var frontID: String? { session.frontmostBundleID ?? session.macroProfile?.bundleID }

    private var frontName: String {
        guard let id = frontID else { return "Front App" }
        return (session.dockApps + session.dockCatalog).first { $0.bundleID == id }?.name
            ?? (session.macroProfile?.bundleID == id ? session.macroProfile?.name : nil)
            ?? id.split(separator: ".").last.map(String.init)?.capitalized ?? "Front App"
    }

    var body: some View {
        GeometryReader { geo in
            let metrics = ActionGridMetrics.fit(width: geo.size.width - 32, scale: settings.deckTileScale)
            ZStack {
                if layout == nil && !session.isConnected && session.macroProfile == nil {
                    ModeOfflineMessage(mode: deckOnly ? .deck : .actions)
                } else {
                    VStack(spacing: 0) {
                        header
                            .padding(.horizontal, 16)
                            .padding(.top, settings.pillPosition == .top ? (compact ? 36 : 56) : 12)
                        pageChips
                            .padding(.top, 10)
                        content(metrics: metrics)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                notices
                if !deckOnly, page != .clipboard { MacroStatusBar(showsRecord: false) }
            }
            .padding(.bottom, settings.pillPosition == .bottom ? 56 : 0)
        }
        .onAppear {
            session.send(.deckRequest)
            if !deckOnly { session.send(.macro(.listMacros)) }
            if session.dockCatalog.isEmpty { session.send(.dockCatalogRequest) }
            if deckOnly || !settings.actionsFollowsApp, case .frontApp = page { page = firstDeckPage }
            #if DEBUG
            switch DebugLaunch.demoActionsPage {
            case "mac": page = .deck(DeckIDs.mac)
            case "mine": page = .deck(DeckIDs.mine)
            case "clipboard": page = .clipboard
            case "present": page = .present
            default: break
            }
            if DebugLaunch.demoEditing { editing = true }
            #endif
        }
        .onChange(of: frontID) { _, _ in
            guard !deckOnly, settings.actionsFollowsApp, !editing else { return }
            if page == .frontApp || isDeckPage(page) {
                withAnimation(.snappy) { page = .frontApp; folderPath = [] }
            }
        }
        .onChange(of: page) { folderPath = [] }
        .sheet(item: $editorTarget) { target in
            DeckButtonEditor(button: target.button, isNew: target.isNew, frontAppName: frontName) { saved in
                apply(target, saved)
            } onDelete: {
                edit { $0.remove(id: target.button.id) }
            }
            .environment(\.palette, palette)
        }
        .sheet(isPresented: $showPages) {
            DeckPagesSheet(layout: layout ?? DeckLayout(pages: [])) { session.saveDeck($0) }
                .environment(\.palette, palette)
        }
        .fullScreenCover(isPresented: $presenting, onDismiss: {
            router.presenting = false
            ScreenAwake.update()
        }) {
            PresenterCover()
                .environment(\.palette, palette)
        }
        .confirmationDialog(confirming.map { "\($0.title)?" } ?? "", isPresented: .init(get: { confirming != nil },
                                                                                        set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible, presenting: confirming) { button in
            Button(button.title, role: .destructive) {
                Haptics.shared.play(.click)
                session.runDeck(button.id, confirmed: true)
            }
        } message: { button in
            Text(button.action == .system(.emptyTrash) ? "Everything in the Mac's Trash is deleted for good." : "Your Mac goes to sleep now.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if !folderPath.isEmpty {
                Button {
                    Haptics.shared.tap()
                    withAnimation(.snappy) { _ = folderPath.removeLast() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .glassButton()
                .buttonBorderShape(.circle)
                .accessibilityLabel("Back")
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(compact ? .title2.bold() : .title.bold())
                    .foregroundStyle(palette.inkColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !compact {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(palette.inkSoftColor)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if editing {
                Button("Done") {
                    Haptics.shared.tap()
                    editing = false
                }
                .font(.body.weight(.semibold))
                .glassButton(prominent: true)
                .tint(accent)
            } else if canEditPage {
                menu
            }
        }
    }

    private var title: String {
        if let folder = folderPath.last, let b = layout?.button(id: folder) { return b.title }
        switch page {
        case .frontApp: return frontName
        case .deck(let id): return layout?.pages.first { $0.id == id }?.title ?? "Buttons"
        case .clipboard: return "Clipboard"
        case .present: return "Present"
        }
    }

    private var subtitle: String {
        switch page {
        case .frontApp: return session.isConnected ? "Follows the app in front on your Mac" : "Not connected"
        case .deck(let id):
            if id == DeckIDs.mac { return "Controls for your Mac" }
            if id == DeckIDs.mine { return "Your buttons and macros" }
            return "\(layout?.buttons(page: pageIndex ?? 0).count ?? 0) buttons"
        case .clipboard: return "Between this iPhone and your Mac"
        case .present: return "Slides, timer and laser pointer"
        }
    }

    private var menu: some View {
        Menu {
            Button("Edit Buttons", systemImage: "square.grid.3x3.square") { editing = true }
            Button("Add Button", systemImage: "plus") { addButton() }
            Button("Pages", systemImage: "rectangle.stack") { showPages = true }
            Divider()
            if !deckOnly {
                Toggle(isOn: $settings.actionsFollowsApp) {
                    Label("Follow the Front App", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            Toggle("Show Labels", isOn: $settings.deckShowsTitles)
            Picker("Tile Size", selection: $settings.deckTileScale) {
                Text("Small").tag(0.85)
                Text("Medium").tag(1.0)
                Text("Large").tag(1.3)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .glassButton()
        .buttonBorderShape(.circle)
        .accessibilityLabel("Actions options")
    }

    // MARK: Page chips

    private var chips: [(ActionsPage, String, String)] {
        var out: [(ActionsPage, String, String)] = []
        if !deckOnly { out.append((.frontApp, frontName, "app.badge.checkmark")) }
        for p in layout?.pages ?? [] where deckOnly || (p.appBundleIDs ?? []).isEmpty {
            out.append((.deck(p.id), p.title, p.symbol ?? (p.id == DeckIDs.mac ? "macbook" : "square.grid.2x2")))
        }
        if !deckOnly {
            out.append((.clipboard, "Clipboard", "doc.on.clipboard"))
            out.append((.present, "Present", "play.rectangle"))
        }
        return out
    }

    private var pageChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.0) { item in
                        chip(item.0, item.1, item.2).id(item.0)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .onChange(of: page) { _, p in withAnimation(.snappy) { proxy.scrollTo(p, anchor: .center) } }
        }
    }

    private func chip(_ target: ActionsPage, _ title: String, _ symbol: String) -> some View {
        let selected = page == target
        return Button {
            Haptics.shared.tap()
            withAnimation(.snappy) { page = target }
        } label: {
            HStack(spacing: 6) {
                if target == .frontApp, let id = frontID, let icon = session.icons.image(for: id) {
                    Image(uiImage: icon).resizable().interpolation(.high).frame(width: 20, height: 20)
                } else {
                    Image(systemName: symbol).font(.footnote.weight(.semibold))
                }
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .foregroundStyle(selected ? Color.white : palette.inkColor)
            .background {
                if selected { Capsule().fill(accent) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(ChipGlass(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Content

    @ViewBuilder private func content(metrics: ActionGridMetrics) -> some View {
        switch page {
        case .clipboard:
            ClipboardMode(embedded: true)
        case .present:
            presentCard
        default:
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !deckOnly, page == .frontApp { followTip }
                        pageBody(metrics: fillMetrics(base: metrics, width: geo.size.width - 32, height: geo.size.height - 14 - 16))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 16)
                }
            }
            .refreshable {
                session.send(.deckRequest)
                session.send(.macro(.listMacros))
            }
        }
    }

    @ViewBuilder private func pageBody(metrics: ActionGridMetrics) -> some View {
        switch page {
        case .frontApp: frontAppPage(metrics: metrics)
        case .deck(let id):
            if let index = layout?.pages.firstIndex(where: { $0.id == id }) {
                deckGrid(page: index, metrics: metrics)
                if id == DeckIDs.mine && folderPath.isEmpty && !deckOnly { macrosSection(session.allMacros ?? [], metrics: metrics, record: true) }
            } else {
                QuietMessage(symbol: "square.grid.2x2", title: "Page not found", detail: "Pull down to refresh.")
                    .frame(minHeight: 240)
            }
        default: EmptyView()
        }
    }

    /// Sizes tiles so everything on the page fills the screen (buttons, then macros under their
    /// heading); scrolls at the compact size when there is too much.
    private func fillMetrics(base: ActionGridMetrics, width: CGFloat, height: CGFloat) -> ActionGridMetrics {
        var sizes: [DeckButtonSize] = []
        var macroCount = 0
        if let index = pageIndex {
            sizes = (layout?.buttons(page: index, folder: folderPath.last) ?? []).map { $0.size ?? .regular }
            if editing { sizes.append(.regular) }
        }
        if folderPath.isEmpty {
            switch page {
            case .frontApp: macroCount = profileMacros.count
            case .deck(let id) where id == DeckIDs.mine && !deckOnly: macroCount = (session.allMacros ?? []).count + 1
            default: break
            }
        }
        guard !sizes.isEmpty || macroCount > 0 else { return base }
        var available = height
        if page == .frontApp && settings.actionsFollowsApp && !settings.seenTips.contains("actions.follow") { available -= 150 }
        if macroCount > 0 { available -= sizes.isEmpty ? 60 : 76 }
        // Two grids: fit them as if stacked, each starting on a new row.
        let m = ActionGridMetrics.filling(sizes + Array(repeating: .regular, count: macroCount), width: width,
                                          height: max(available, 120), scale: settings.deckTileScale)
        guard !sizes.isEmpty, macroCount > 0 else { return m }
        let rows = DeckGridPacking.place(sizes.map { (columns: $0.span.columns, rows: $0.span.rows) }, columns: m.columns).rows
            + Int((Double(macroCount) / Double(m.columns)).rounded(.up))
        let fitsHeight = CGFloat(rows) * m.cellHeight + CGFloat(rows - 1) * m.spacing <= available
        return fitsHeight ? m : ActionGridMetrics(columns: m.columns, cell: m.cell, cellHeight: m.cell, spacing: m.spacing)
    }

    // MARK: Front app page

    private var linkedPageIndex: Int? { layout?.pageIndex(forFrontmost: frontID) }

    private var profileMacros: [MacroSummary] {
        guard let p = session.macroProfile, p.profileID != nil, p.bundleID == nil || p.bundleID == frontID else { return [] }
        return p.macros
    }

    @ViewBuilder private func frontAppPage(metrics: ActionGridMetrics) -> some View {
        let macros = profileMacros
        if let index = linkedPageIndex {
            deckGrid(page: index, metrics: metrics)
        }
        if !macros.isEmpty && folderPath.isEmpty {
            macrosSection(macros, metrics: metrics, record: false,
                          title: linkedPageIndex == nil ? nil : "Macros for \(frontName)")
        }
        if linkedPageIndex == nil && macros.isEmpty {
            VStack(spacing: 14) {
                QuietMessage(symbol: "app.badge.checkmark", title: "Nothing for \(frontName) yet",
                             detail: "Buttons you add here show up by themselves whenever \(frontName) is in front on your Mac. Macros in a profile for this app appear here too.")
                    .frame(minHeight: 200)
                Button("Add a Button for \(frontName)", systemImage: "plus") { addButton() }
                    .glassButton(prominent: true)
                    .tint(accent)
                    .disabled(frontID == nil || !session.isConnected)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var followTip: some View {
        if settings.actionsFollowsApp && !settings.seenTips.contains("actions.follow") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title3)
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("This page follows your Mac").font(.subheadline.weight(.semibold))
                    Text("Switch apps on the Mac and these buttons change to match. Mac controls, your own buttons, Clipboard and Present are in the row above.")
                        .font(.footnote)
                        .foregroundStyle(palette.inkSoftColor)
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.snappy) { _ = settings.seenTips.insert("actions.follow") }
                } label: {
                    Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(palette.inkSoftColor)
                }
                .accessibilityLabel("Dismiss tip")
            }
            .foregroundStyle(palette.inkColor)
            .padding(14)
            .glassPanel(cornerRadius: 20)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: Grids

    private var pageIndex: Int? {
        switch page {
        case .deck(let id): return layout?.pages.firstIndex { $0.id == id }
        case .frontApp: return linkedPageIndex
        default: return nil
        }
    }

    @ViewBuilder private func deckGrid(page index: Int, metrics: ActionGridMetrics) -> some View {
        let buttons = layout?.buttons(page: index, folder: folderPath.last) ?? []
        if buttons.isEmpty && !editing {
            VStack(spacing: 14) {
                QuietMessage(symbol: folderPath.isEmpty ? "square.grid.2x2" : "folder",
                             title: folderPath.isEmpty ? "No buttons on this page" : "This folder is empty",
                             detail: "Add buttons that open apps, take screenshots, run Shortcuts and macros, type text and more.")
                    .frame(minHeight: 200)
                Button("Add Button", systemImage: "plus") { addButton() }
                    .glassButton(prominent: true)
                    .tint(accent)
            }
            .frame(maxWidth: .infinity)
        } else {
            PackedGrid(metrics: metrics) {
                ForEach(buttons) { button in
                    deckTile(button, page: index, siblings: buttons)
                        .tileSpan(button.size)
                }
                if editing {
                    ActionTile(title: "Add", symbol: "plus", tint: accent, showsTitle: true, style: .outlined) { addButton() }
                        .accessibilityLabel("Add button")
                }
            }
        }
    }

    private func deckTile(_ button: DeckButton, page index: Int, siblings: [DeckButton]) -> some View {
        var icon: UIImage?
        if case .openApp(let id) = button.action { icon = session.icons.image(for: id) }
        let tile = ActionTile(title: button.title, symbol: button.symbol, tint: button.tint, appIcon: icon,
                              size: button.size ?? .regular, showsTitle: settings.deckShowsTitles, badge: button.badge,
                              pending: session.deckPending.contains(button.id),
                              succeeded: session.deckOutcomes[button.id]?.ok == true, editing: editing) {
            tap(button)
        }
        .opacity(dragging == button.id ? 0.35 : 1)
        .accessibilityLabel(button.title)
        .accessibilityHint(editing ? "Edits this button" : button.action.spokenHint)
        .accessibilityAction(named: "Edit") { editorTarget = EditorTarget(button: button, isNew: false, page: index, folder: folderPath.last) }
        return Group {
            if editing {
                tile
                    .onDrag {
                        dragging = button.id
                        return NSItemProvider(object: button.id.uuidString as NSString)
                    }
                    .onDrop(of: [UTType.text], delegate: TileDropDelegate(target: button.id, siblings: siblings.map(\.id),
                                                                          dragging: $dragging) { id, to in
                        edit { $0.move(id: id, to: to, page: index, folder: folderPath.last) }
                    })
            } else {
                tile.contextMenu {
                    Button("Edit", systemImage: "pencil") {
                        editorTarget = EditorTarget(button: button, isNew: false, page: index, folder: folderPath.last)
                    }
                    Button("Edit Page", systemImage: "square.grid.3x3.square") { editing = true }
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        var copy = button
                        copy.id = UUID()
                        edit { $0.add(copy, page: index, folder: folderPath.last) }
                    }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) { edit { $0.remove(id: button.id) } }
                }
            }
        }
    }

    @ViewBuilder
    private func macrosSection(_ macros: [MacroSummary], metrics: ActionGridMetrics, record: Bool, title: String? = nil) -> some View {
        if !macros.isEmpty || record {
            ActionSectionHeader(title: title ?? "Macros", detail: record ? "Recorded steps you can replay. Record one from here." : nil)
                .padding(.top, 8)
            PackedGrid(metrics: metrics) {
                ForEach(macros) { macro in
                    ActionTile(title: macro.name, symbol: macro.symbol, tint: macro.tint, showsTitle: settings.deckShowsTitles,
                               badge: macro.usesScripts ? "terminal.fill" : "wand.and.stars",
                               pending: session.macroPendingID == macro.id,
                               progress: session.macroRunning?.macroID == macro.id ? session.macroRunning?.fraction : nil) {
                        Haptics.shared.play(.click)
                        session.runMacro(macro.id)
                    }
                    .accessibilityLabel(macro.name)
                    .accessibilityValue("Macro, \(macro.stepCount) steps")
                }
                if record {
                    ActionTile(title: session.isRecordingMacro ? "Recording" : "Record", symbol: "record.circle", tint: .red,
                               showsTitle: true, style: .outlined) {
                        Haptics.shared.tap()
                        if session.isRecordingMacro {
                            session.send(.macro(.recordStop))
                        } else {
                            session.send(.macro(.recordStart(windowRelative: false, keepTiming: true)))
                        }
                    }
                    .disabled(!session.isConnected)
                    .accessibilityHint("Records your keyboard and mouse on the Mac until you stop")
                }
            }
        }
    }

    // MARK: Present

    private var presentCard: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 14) {
                    Image(systemName: "play.rectangle.on.rectangle.fill")
                        .font(.system(size: 48, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppMode.present.accent(palette))
                    Text("Present from your iPhone")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(palette.inkColor)
                    Text("Big Next and Previous buttons, a timer, and a laser pad that shows a red dot on the Mac's screen. The screen stays on while you present.")
                        .font(.subheadline)
                        .foregroundStyle(palette.inkSoftColor)
                        .multilineTextAlignment(.center)
                    Button {
                        Haptics.shared.play(.click)
                        router.presenting = true
                        presenting = true
                        ScreenAwake.update()
                    } label: {
                        Label("Start Presenting", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: 280, minHeight: 32)
                    }
                    .glassButton(prominent: true)
                    .controlSize(.large)
                    .tint(AppMode.present.accent(palette))
                    .disabled(!session.isConnected)
                }
                .padding(24)
                .frame(maxWidth: 520)
                .glassPanel(cornerRadius: 28)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
        }
    }

    @ViewBuilder private var notices: some View {
        Group {
            if let failure = session.deckFailure {
                banner(failure.message, "exclamationmark.triangle.fill").id(failure.id)
            } else if let note = session.deckImageNotice {
                banner(note.message, "photo.on.rectangle").id(note.id)
            } else if let error = session.deckSaveError {
                banner(error, "exclamationmark.triangle.fill")
            }
        }
        .padding(.horizontal, 16)
        .animation(.snappy, value: session.deckFailure)
    }

    private func banner(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline)
            .foregroundStyle(palette.inkColor)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassCapsule()
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: Actions

    private var canEditPage: Bool {
        switch page {
        case .clipboard, .present: false
        case .frontApp: frontID != nil
        default: true
        }
    }

    private func isDeckPage(_ p: ActionsPage) -> Bool { if case .deck = p { true } else { false } }

    private var firstDeckPage: ActionsPage {
        layout?.pages.first { deckOnly || ($0.appBundleIDs ?? []).isEmpty }.map { .deck($0.id) } ?? .frontApp
    }

    private func tap(_ button: DeckButton) {
        if editing {
            editorTarget = EditorTarget(button: button, isNew: false, page: pageIndex ?? 0, folder: folderPath.last)
            return
        }
        if button.action == .folder {
            Haptics.shared.tap()
            withAnimation(.snappy) { folderPath.append(button.id) }
            return
        }
        if button.needsConfirmation {
            Haptics.shared.tap()
            confirming = button
            return
        }
        Haptics.shared.play(.click)
        session.runDeck(button.id)
    }

    private func addButton() {
        var target: Int? = pageIndex
        if target == nil, page == .frontApp, let id = frontID {
            // First button for this app: make its page, linked to the app.
            var l = layout ?? DeckLayout(pages: [])
            l.pages.append(DeckPage(title: frontName, symbol: "app", appBundleIDs: [id], buttons: []))
            session.saveDeck(l)
            target = l.pages.count - 1
        }
        guard let target else { return }
        let fresh = DeckButton(title: "", symbol: "bolt.fill", action: .system(.playPause), color: "#0A84FF")
        editorTarget = EditorTarget(button: fresh, isNew: true, page: target, folder: folderPath.last)
    }

    private func apply(_ target: EditorTarget, _ button: DeckButton) {
        edit { l in
            if target.isNew { l.add(button, page: target.page, folder: target.folder) } else { l.replace(button) }
        }
    }

    private func edit(_ change: (inout DeckLayout) -> Void) {
        guard var l = layout else { return }
        change(&l)
        session.saveDeck(l)
    }
}

/// Fixed ids of the Mac's two built-in pages (see DeckConfig on the Mac).
enum DeckIDs {
    static let mac = UUID(uuidString: "6D61632D-0000-4000-8000-000000000001")!
    static let mine = UUID(uuidString: "6D61632D-0000-4000-8000-000000000002")!
}

struct EditorTarget: Identifiable {
    var id: UUID { button.id }
    let button: DeckButton
    let isNew: Bool
    let page: Int
    let folder: UUID?
}

private struct ChipGlass: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        if selected { content } else { content.glassCapsule(interactive: true) }
    }
}

/// Live reordering of tiles while dragging in edit mode.
private struct TileDropDelegate: DropDelegate {
    let target: UUID
    let siblings: [UUID]
    @Binding var dragging: UUID?
    let move: (UUID, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target, let to = siblings.firstIndex(of: target) else { return }
        move(dragging, to)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Present, full screen, with a way back.
private struct PresenterCover: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            palette.backgroundColor.ignoresSafeArea()
            PresentMode()
            Button {
                MacSession.shared.laserOff()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .glassButton()
            .buttonBorderShape(.circle)
            .padding(.leading, 16)
            .padding(.top, 8)
            .accessibilityLabel("Stop presenting")
        }
        .persistentSystemOverlays(.hidden)
        .simultaneousGesture(TapGesture().onEnded { AppRouter.shared.noteActivity() })
    }
}
