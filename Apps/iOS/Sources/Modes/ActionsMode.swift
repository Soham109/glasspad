import SwiftUI
import UniformTypeIdentifiers
import GlasspadKit

/// Actions: one screen, no tabs.
///
/// 1. The app in front on the Mac, with its best buttons (at most eight): the buttons of the
///    Deck page linked to that app, then the macros of its macro profile. Which ones show, and
///    in what order, is the user's choice.
/// 2. Pinned: one grid of favourites. Mac controls, apps, websites, macros, Shortcuts and
///    keystrokes all look the same here. The + tile at the end opens the Library.
///
/// Both grids size their tiles from the space they get (`TileGrid`), so the screen works full
/// screen, sideways and in a split-screen pane. When there is room side by side (wider than
/// tall), the front app and Pinned sit in two columns.
///
/// Clipboard and Present are small tools in the mode menu now (or full modes when Actions is
/// split up in Settings). Deck mode, for people who split, is this same screen.
struct ActionsMode: View {
    @Environment(\.palette) private var palette
    @Environment(\.modeTopClearance) private var topClearance
    @Bindable var settings = PhoneSettings.shared
    var session = MacSession.shared
    var router = AppRouter.shared

    @State private var editing = false
    @State private var folderPath: [UUID] = []
    @State private var editorTarget: EditorTarget?
    @State private var confirming: DeckButton?
    @State private var showLibrary = false
    @State private var showFrontPicker = false
    @State private var confirmingReset = false
    /// Macro ids known when "Record New Macro" was tapped; the new one gets pinned.
    @State private var macrosBeforeRecording: Set<UUID>?
    /// While a tile is dragged in edit mode: which one, and the order shown so far. The order
    /// is saved once, when the tile is dropped, not on every step.
    @State private var dragging: String?
    @State private var draft: TileDraft?

    // MARK: Data

    /// Key for "this Mac's Deck was already moved to the one-screen layout".
    private var macKey: String { PairingStore.shared.selected?.macID.uuidString ?? "local" }

    private var isDemo: Bool {
        #if DEBUG
        session.isDemo
        #else
        false
        #endif
    }

    /// The Mac's Deck in the one-screen shape. Until the move is saved on the Mac it is shown
    /// moved anyway, so the screen looks the same before and after.
    private var layout: DeckLayout? {
        let raw: DeckLayout? = session.deckLayout
            ?? session.deckButtons.map { DeckLayout(pages: [DeckPage(title: "Buttons", buttons: $0)]) }
        guard let raw else { return nil }
        if settings.pinnedMigratedMacs.contains(macKey) && !isDemo { return raw }
        return PinnedDeck.migrated(raw, macros: session.allMacros ?? [])
    }

    private var frontID: String? { session.frontmostBundleID ?? session.macroProfile?.bundleID }

    private var frontName: String {
        guard let id = frontID else { return session.isConnected ? (session.macName ?? "Your Mac") : "Not Connected" }
        return (session.dockApps + session.dockCatalog).first { $0.bundleID == id }?.name
            ?? (session.macroProfile?.bundleID == id ? session.macroProfile?.name : nil)
            ?? id.split(separator: ".").last.map(String.init)?.capitalized ?? "App"
    }

    private var linkedPageIndex: Int? { layout?.pageIndex(forFrontmost: frontID) }

    private var profileMacros: [MacroSummary] {
        guard let p = session.macroProfile, p.profileID != nil, p.bundleID == nil || p.bundleID == frontID else { return [] }
        return p.macros
    }

    private var frontButtons: [DeckButton] { linkedPageIndex.map { layout?.pages[$0].buttons ?? [] } ?? [] }

    private var frontItems: [FrontAppItem] {
        let items = PinnedDeck.frontAppItems(buttons: frontButtons, macros: profileMacros,
                                             picks: frontID.flatMap { settings.frontAppPicks[$0] })
        return ordered(items, by: \.id, in: .front)
    }

    private var pinnedIndex: Int? { layout.flatMap(PinnedDeck.pinnedIndex(in:)) }

    private var pinnedButtons: [DeckButton] {
        guard let layout, let i = pinnedIndex else { return [] }
        return ordered(layout.buttons(page: i, folder: folderPath.last), by: \.id.uuidString, in: .pinned)
    }

    /// Items in the order being dragged, when a drag is under way in that section.
    private func ordered<T>(_ items: [T], by id: KeyPath<T, String>, in section: TileDraft.Section) -> [T] {
        guard let draft, draft.section == section else { return items }
        let rank = Dictionary(draft.order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return items.enumerated().sorted { a, b in
            (rank[a.element[keyPath: id]] ?? Int.max, a.offset) < (rank[b.element[keyPath: id]] ?? Int.max, b.offset)
        }.map(\.element)
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            // Two columns when the space is clearly wider than tall and each half still holds
            // a few tiles across (sideways, or a wide pane).
            let sideBySide = geo.size.width > geo.size.height * 1.15 && geo.size.width >= 560
            let margin: CGFloat = geo.size.width < 300 ? 12 : 16
            if layout == nil && !session.isConnected && session.macroProfile == nil {
                ModeOfflineMessage(mode: .actions)
            } else if sideBySide {
                // The columns scroll edge to edge and pad their content, so remove badges
                // and the wiggle are never clipped at a column's edge.
                HStack(alignment: .top, spacing: 0) {
                    column(compact: true, leading: margin, trailing: 14) { frontSection(compact: true) }
                    column(compact: true, leading: 14, trailing: margin) { pinnedSection }
                }
            } else {
                column(compact: geo.size.height < 500, leading: margin, trailing: margin) {
                    frontSection(compact: geo.size.height < 500)
                    pinnedSection
                        .padding(.top, 28)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                notices
                MacroStatusBar(showsRecord: false)
            }
            .padding(.bottom, settings.pillPosition == .bottom ? 56 : 0)
        }
        .onChange(of: editing) { _, on in
            if !on { commitDraft() }
        }
        .onAppear {
            session.send(.deckRequest)
            session.send(.macro(.listMacros))
            if session.dockCatalog.isEmpty { session.send(.dockCatalogRequest) }
            if session.deckCatalog == nil { session.send(.deckCatalogRequest) }
            askMissingIcons()
            saveMigrationIfNeeded()
            #if DEBUG
            if DebugLaunch.demoEditing { editing = true }
            if DebugLaunch.demoActionsPage == "library" { showLibrary = true }
            if DebugLaunch.demoActionsPage == "front" { showFrontPicker = true }
            if DebugLaunch.demoActionsPage == "editor", let b = pinnedButtons.first(where: { $0.action != .folder }) { open(b, page: pinnedIndex ?? 0) }
            if DebugLaunch.demoActionsPage == "website", let b = pinnedButtons.first(where: { $0.action.websiteLink != nil }) { open(b, page: pinnedIndex ?? 0) }
            if DebugLaunch.demoActionsPage == "newsite" {
                editorTarget = EditorTarget(button: DeckButton(title: "", symbol: "globe", action: .openURL("https://www.apple.com"), color: "#0A84FF"),
                                            isNew: true, page: pinnedIndex ?? 0, folder: nil, picksAction: false)
            }
            if DebugLaunch.demoActionsPage == "folder", let f = pinnedButtons.first(where: { $0.action == .folder && !($0.children ?? []).isEmpty }) {
                folderPath = [f.id]
            }
            #endif
        }
        .onChange(of: session.deckLayout) {
            saveMigrationIfNeeded()
            askMissingIcons()
            // A folder that is gone (deleted on the Mac, or from its editor) closes.
            if let open = folderPath.last, layout?.button(id: open) == nil { folderPath = [] }
        }
        .onChange(of: session.allMacros) {
            saveMigrationIfNeeded()
            pinRecordedMacros()
        }
        .onChange(of: session.isConnected) { saveMigrationIfNeeded() }
        .onChange(of: frontID) {
            // A drag in the front section belongs to the app that was in front.
            if draft?.section == .front { draft = nil; dragging = nil }
        }
        .sheet(item: $editorTarget) { target in
            DeckButtonEditor(button: target.button, isNew: target.isNew, frontAppName: frontName,
                             picksAction: target.isNew && target.picksAction) { saved in
                apply(target, saved)
            } onDelete: {
                edit { $0.remove(id: target.button.id) }
            }
        }
        .sheet(isPresented: $showLibrary) {
            ActionLibrary(layout: layout ?? DeckLayout(pages: []), folder: folderPath.last) { change in
                edit(change)
            } onCustom: { button in
                showLibrary = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    editorTarget = EditorTarget(button: button, isNew: true, page: pinnedIndex ?? 0, folder: folderPath.last,
                                                picksAction: false)
                }
            } onRecord: {
                macrosBeforeRecording = Set((session.allMacros ?? []).map(\.id))
            }
        }
        .sheet(isPresented: $showFrontPicker) {
            FrontAppButtonsSheet(appName: frontName, buttons: frontButtons, macros: profileMacros,
                                 picks: Binding(get: { frontID.flatMap { settings.frontAppPicks[$0] } },
                                                set: { if let id = frontID { settings.frontAppPicks[id] = $0 } })) { button in
                showFrontPicker = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    editFrontButton(button)
                }
            } onAdd: {
                showFrontPicker = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    addFrontButton()
                }
            }
        }
        .confirmationDialog("Reset Pinned?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset to Defaults", role: .destructive) {
                Haptics.shared.play(.snap)
                folderPath = []
                edit { $0 = PinnedDeck.resetPinned($0) }
                settings.seenTips.insert(Self.tidyTipID)
            }
        } message: {
            Text("Pinned goes back to six everyday Mac controls. Mac controls, apps and macros stay in the Library, ready to pin again. Folders and buttons you made yourself are deleted.")
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

    /// One scrolling column of sections, clear of the mode pill. A drop that lands between
    /// tiles still ends the drag and saves the order.
    private func column<Content: View>(compact: Bool, leading: CGFloat, trailing: CGFloat,
                                       @ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.leading, leading)
                .padding(.trailing, trailing)
                .padding(.top, topClearance ?? (settings.pillPosition == .top ? (compact ? 48 : 64) : 16))
                .padding(.bottom, 24)
                .animation(.snappy, value: editing)
                .animation(.snappy, value: folderPath)
                .animation(.snappy, value: draft)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            session.send(.deckRequest)
            session.send(.macro(.listMacros))
        }
        .onDrop(of: [UTType.text], delegate: EndDragDelegate { commitDraft() })
    }

    // MARK: Front app

    private func frontSection(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                frontGlyph(size: compact ? 36 : 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(frontName)
                        .font(compact ? .title3.bold() : .title2.bold())
                        .foregroundStyle(palette.inkColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.opacity)
                    Text(frontSubtitle)
                        .font(.footnote)
                        .foregroundStyle(palette.inkSoftColor)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                headerButton
            }
            .animation(.snappy, value: frontID)
            Tip(id: "actions.front", text: "The best buttons for the app in front on your Mac. They change when you switch apps.")
                .padding(.top, 10)
            let items = frontItems
            if items.isEmpty {
                frontEmpty.padding(.top, 14)
            } else {
                TileGrid(preferred: TileGrid.preferred(scale: settings.deckTileScale)) {
                    ForEach(items) { item in
                        frontTile(item).tileSpan(.regular)
                    }
                    if editing {
                        ActionTile(title: "Choose", face: TileFace(symbol: "checklist", tint: palette.inkColor),
                                   showsTitle: true, style: .outlined) {
                            showFrontPicker = true
                        }
                        .accessibilityLabel("Choose buttons for \(frontName)")
                    }
                }
                .padding(.top, 14)
            }
        }
    }

    private var frontSubtitle: String {
        if !session.isConnected { return "Buttons work again once your Mac is back" }
        if frontID == nil { return "Open an app on your Mac" }
        return "In front on \(session.macName ?? "your Mac")"
    }

    /// No buttons for the front app (or no app): a calm card that says why, with the way on.
    private var frontEmpty: some View {
        HStack(spacing: 12) {
            Text(frontID != nil ? "No buttons for \(frontName) yet. Add its menu commands or keys here."
                 : session.isConnected ? "Open an app on your Mac to see its buttons here."
                 : "The front app's buttons show here once your Mac is connected.")
                .font(.subheadline)
                .foregroundStyle(palette.inkSoftColor)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if frontID != nil {
                Button("Add", systemImage: "plus") { addFrontButton() }
                    .font(.subheadline.weight(.semibold))
                    .glassButton()
                    .disabled(!session.isConnected || layout == nil)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.raisedColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.lineColor))
    }

    @ViewBuilder private func frontGlyph(size: CGFloat) -> some View {
        if let id = frontID, let icon = session.icons.image(for: id) {
            Image(uiImage: icon)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 1.15, height: size * 1.15)
                .frame(width: size, height: size)
                .saturation(palette.monochrome ? 0 : 1)
                .accessibilityHidden(true)
        } else {
            Image(systemName: session.isConnected ? "macwindow" : "bolt.horizontal.circle")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(palette.inkSoftColor)
                .frame(width: size, height: size)
                .background(palette.raisedColor, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(palette.lineColor))
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func frontTile(_ item: FrontAppItem) -> some View {
        switch item {
        case .button(let button):
            deckTile(button, page: linkedPageIndex ?? 0, section: .front)
        case .macro(let macro):
            reorderable(ActionTile(title: macro.name, face: TileFace(symbol: macro.symbol, tint: macro.tint),
                                   showsTitle: settings.deckShowsTitles, badge: "wand.and.stars",
                                   pending: session.macroPendingID == macro.id,
                                   progress: session.macroRunning?.macroID == macro.id ? session.macroRunning?.fraction : nil,
                                   editing: editing) {
                if editing { showFrontPicker = true; return }
                Haptics.shared.play(.click)
                session.runMacro(macro.id)
            }
            .overlay(alignment: .topLeading) {
                if editing { RemoveBadge(label: "Hide \(macro.name)") { hideFront(item.id) } }
            }
            .accessibilityLabel(macro.name)
            .accessibilityValue("Macro, \(macro.stepCount) steps")
            .accessibilityHint(editing ? "Opens the list of buttons for \(frontName)" : "Runs a macro on your Mac"),
            id: item.id, section: .front) {
                Button("Choose Buttons for \(frontName)", systemImage: "checklist") { showFrontPicker = true }
                Button("Edit Actions", systemImage: "square.grid.3x3.square") { editing = true }
                Divider()
                Button("Hide Here", systemImage: "eye.slash", role: .destructive) { hideFront(item.id) }
            }
        }
    }

    private var headerButton: some View {
        Group {
            if editing {
                Button("Done") {
                    Haptics.shared.tap()
                    editing = false
                }
                .font(.subheadline.weight(.semibold))
                .glassButton(prominent: true)
                .controlSize(.large)
            } else {
                Button("Edit") {
                    Haptics.shared.tap()
                    editing = true
                }
                .font(.subheadline.weight(.medium))
                .glassButton()
                .controlSize(.large)
                .foregroundStyle(palette.inkColor)
                .disabled(layout == nil)
            }
        }
    }

    // MARK: Pinned

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let folder = folderPath.last.flatMap({ layout?.button(id: $0) }) {
                    Button {
                        Haptics.shared.tap()
                        commitDraft()
                        _ = folderPath.removeLast()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.body.weight(.semibold))
                            .frame(width: 30, height: 30)
                            .contentShape(Circle())
                    }
                    .glassButton()
                    .buttonBorderShape(.circle)
                    .foregroundStyle(palette.inkColor)
                    .accessibilityLabel("Back to Pinned")
                    Text(folder.title)
                        .font(.title3.bold())
                        .foregroundStyle(palette.inkColor)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    Text("Pinned")
                        .font(.title3.bold())
                        .foregroundStyle(palette.inkColor)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 8)
                if editing { optionsMenu }
            }
            .frame(minHeight: 36)
            if folderPath.isEmpty {
                Tip(id: "actions.pinned", text: "Your favourites. Tap + to add anything; touch and hold one to change it.")
                    .padding(.top, 8)
                if showsTidy { tidyCard.padding(.top, 10) }
            }
            let buttons = pinnedButtons
            TileGrid(preferred: TileGrid.preferred(scale: settings.deckTileScale)) {
                ForEach(buttons) { button in
                    deckTile(button, page: pinnedIndex ?? 0, section: .pinned)
                        .tileSpan(button.size)
                }
                ActionTile(title: "Add", face: TileFace(symbol: "plus", tint: palette.inkColor), showsTitle: true, style: .outlined) {
                    Haptics.shared.tap()
                    commitDraft()
                    showLibrary = true
                }
                .accessibilityLabel(folderPath.isEmpty ? "Add to Pinned" : "Add to this folder")
                .disabled(layout == nil)
            }
            .padding(.top, 14)
            if editing && folderPath.isEmpty {
                HStack {
                    Spacer()
                    Button("Reset to Defaults", role: .destructive) { confirmingReset = true }
                        .font(.footnote.weight(.medium))
                        .frame(minHeight: 44)
                    Spacer()
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: Tidy up

    private static let tidyTipID = "actions.tidy"

    /// Once, for a Pinned that grew long (often from older versions, which pinned every Mac
    /// control and macro): offer to keep only the essentials.
    private var showsTidy: Bool {
        !editing && !settings.seenTips.contains(Self.tidyTipID) && !isDemo
            && (layout.map { PinnedDeck.pinned(in: $0).count } ?? 0) > PinnedDeck.tidyThreshold
    }

    private var tidyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pinned has \(pinnedButtons.count) buttons. Keep just six everyday ones? Everything else stays in the Library.")
                .font(.subheadline)
                .foregroundStyle(palette.inkColor)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Tidy Up") { confirmingReset = true }
                    .font(.subheadline.weight(.semibold))
                    .glassButton(prominent: true)
                    .controlSize(.large)
                Button("Keep Mine") {
                    withAnimation(.snappy) { _ = settings.seenTips.insert(Self.tidyTipID) }
                }
                .font(.subheadline.weight(.medium))
                .glassButton()
                .controlSize(.large)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.raisedColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.lineColor))
        .transition(.opacity)
    }

    private var optionsMenu: some View {
        Menu {
            Button("New Folder", systemImage: "folder.badge.plus") { newFolder() }
            Button("Reset to Defaults", systemImage: "arrow.counterclockwise") { confirmingReset = true }
            Divider()
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
        .foregroundStyle(palette.inkColor)
        .accessibilityLabel("Pinned options")
    }

    // MARK: Tiles

    /// One Deck button, in the front section or in Pinned (or a Pinned folder).
    private func deckTile(_ button: DeckButton, page index: Int, section: TileDraft.Section) -> some View {
        let inPinned = section == .pinned
        let key = inPinned ? button.id.uuidString : FrontAppItem.button(button).id
        let folderFaces = button.action == .folder ? (button.children ?? []).prefix(4).map { $0.face(icons: session.icons) } : nil
        let tile = ActionTile(title: button.title, face: button.face(icons: session.icons), folder: folderFaces,
                              size: inPinned ? (button.size ?? .regular) : .regular, showsTitle: settings.deckShowsTitles,
                              badge: button.badge,
                              pending: session.deckPending.contains(button.id),
                              succeeded: session.deckOutcomes[button.id]?.ok == true, editing: editing) {
            tap(button, page: index)
        }
        .overlay(alignment: .topLeading) {
            if editing {
                RemoveBadge(label: inPinned ? "Remove \(button.title)" : "Hide \(button.title)") {
                    if inPinned { edit { $0.remove(id: button.id) } } else { hideFront(key) }
                }
            }
        }
        .accessibilityLabel(button.title)
        .accessibilityHint(editing ? "Edits this button" : button.action.spokenHint)
        .accessibilityAction(named: "Edit") { open(button, page: index) }
        return reorderable(tile, id: key, section: section) {
            Button("Edit", systemImage: "pencil") { open(button, page: index) }
            if inPinned {
                Button("Edit Pinned", systemImage: "square.grid.3x3.square") { editing = true }
                Button("Duplicate", systemImage: "plus.square.on.square") {
                    var copy = button
                    copy.id = UUID()
                    if copy.action == .folder { copy.children = [] }
                    edit { $0.add(copy, page: index, folder: folderPath.last) }
                }
                Divider()
                Button(button.action == .folder ? "Delete Folder" : "Unpin", systemImage: button.action == .folder ? "trash" : "pin.slash",
                       role: .destructive) { edit { $0.remove(id: button.id) } }
            } else {
                Button("Choose Buttons for \(frontName)", systemImage: "checklist") { showFrontPicker = true }
                Divider()
                Button("Hide Here", systemImage: "eye.slash", role: .destructive) { hideFront(key) }
            }
        }
    }

    /// In edit mode a tile can be dragged to a new place in its own section; otherwise
    /// touching and holding it shows its menu.
    @ViewBuilder
    private func reorderable<Tile: View, Items: View>(_ tile: Tile, id: String, section: TileDraft.Section,
                                                     @ViewBuilder menu: () -> Items) -> some View {
        if editing {
            tile
                .opacity(dragging == id ? 0.3 : 1)
                .onDrag {
                    dragging = id
                    draft = TileDraft(section: section, order: currentOrder(section))
                    return NSItemProvider(object: id as NSString)
                }
                .onDrop(of: [UTType.text], delegate: ReorderDropDelegate(target: id, section: section, dragging: $dragging,
                                                                         draft: $draft) { commitDraft() })
        } else {
            tile.contextMenu { menu() }
        }
    }

    private func currentOrder(_ section: TileDraft.Section) -> [String] {
        switch section {
        case .front: frontItems.map(\.id)
        case .pinned: pinnedButtons.map(\.id.uuidString)
        }
    }

    /// Saves the order a drag left behind: the front app's picks on the phone, or Pinned on
    /// the Mac (once, as one change).
    private func commitDraft() {
        dragging = nil
        guard let d = draft else { return }
        draft = nil
        switch d.section {
        case .front:
            guard let id = frontID else { return }
            let shown = PinnedDeck.frontAppItems(buttons: frontButtons, macros: profileMacros, picks: settings.frontAppPicks[id]).map(\.id)
            let order = d.order.filter(shown.contains)
            if order != shown { settings.frontAppPicks[id] = order }
        case .pinned:
            guard let page = pinnedIndex, let current = layout?.buttons(page: page, folder: folderPath.last).map(\.id.uuidString),
                  d.order != current else { return }
            let folder = folderPath.last
            edit { l in
                for (i, key) in d.order.enumerated() {
                    if let id = UUID(uuidString: key) { l.move(id: id, to: i, page: page, folder: folder) }
                }
            }
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

    // MARK: Doing things

    private func tap(_ button: DeckButton, page: Int) {
        // A drag that ended outside any drop target (so nothing reported it) ends here.
        if draft != nil { commitDraft() }
        if editing {
            open(button, page: page)
            return
        }
        if button.action == .folder {
            Haptics.shared.tap()
            folderPath.append(button.id)
            return
        }
        if !button.action.isSupported {
            session.deckNeedsUpdate()
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

    /// Icons for pinned apps that are not in the Mac's Dock arrive on request.
    private func askMissingIcons() {
        guard session.isConnected, let layout else { return }
        let ids = layout.allButtons.compactMap { b -> String? in
            if case .openApp(let id) = b.action, session.icons.image(for: id) == nil { return id }
            return nil
        }
        if !ids.isEmpty { session.send(.dockIconRequest(bundleIDs: Array(Set(ids)).sorted())) }
    }

    private func open(_ button: DeckButton, page: Int) {
        editorTarget = EditorTarget(button: button, isNew: false, page: page, folder: folderPath.last)
    }

    private func editFrontButton(_ button: DeckButton) {
        guard let i = linkedPageIndex else { return }
        editorTarget = EditorTarget(button: button, isNew: false, page: i, folder: nil)
    }

    /// Hides one front-app button here without deleting it (the picks remember the rest).
    private func hideFront(_ key: String) {
        guard let id = frontID else { return }
        let shown = PinnedDeck.frontAppItems(buttons: frontButtons, macros: profileMacros, picks: settings.frontAppPicks[id]).map(\.id)
        settings.frontAppPicks[id] = shown.filter { $0 != key }
    }

    /// A new button for the front app: on its linked page, made the first time.
    private func addFrontButton() {
        guard let id = frontID, var l = layout else { return }
        let index: Int
        if let i = l.pageIndex(forFrontmost: id) {
            index = i
        } else {
            l.pages.append(DeckPage(title: frontName, symbol: "app", appBundleIDs: [id], buttons: []))
            session.saveDeck(l)
            index = l.pages.count - 1
        }
        let fresh = DeckButton(title: "", symbol: "bolt.fill", action: .keystroke(Keystroke(key: .character("t"), modifiers: [.command])),
                               color: "#0A84FF")
        editorTarget = EditorTarget(button: fresh, isNew: true, page: index, folder: nil, front: true)
    }

    /// Pins the macro just recorded from the Library, once the Mac lists it.
    private func pinRecordedMacros() {
        guard let before = macrosBeforeRecording, let all = session.allMacros else { return }
        let fresh = all.filter { !before.contains($0.id) }
        guard !fresh.isEmpty else { return }
        macrosBeforeRecording = nil
        edit { l in
            for m in fresh where !PinnedDeck.isPinned(.runMacro(id: m.id), in: l) { l = PinnedDeck.pin(PinnedDeck.button(for: m), in: l) }
        }
    }

    private func newFolder() {
        let folder = DeckButton(title: "Folder", symbol: "folder.fill", action: .folder, color: "#8E8E93", children: [])
        editorTarget = EditorTarget(button: folder, isNew: true, page: pinnedIndex ?? 0, folder: folderPath.last, picksAction: false)
    }

    private func apply(_ target: EditorTarget, _ button: DeckButton) {
        edit { l in
            if target.isNew && target.front {
                l.add(button, page: target.page)
            } else if target.isNew {
                l = PinnedDeck.pin(button, in: l, folder: target.folder)
            } else {
                l.replace(button)
            }
        }
        // A new front-app button shows straight away, even when the user picked the set by hand.
        if target.isNew, target.front, let id = frontID, var picks = settings.frontAppPicks[id], picks.count < PinnedDeck.frontAppLimit {
            picks.append(FrontAppItem.button(button).id)
            settings.frontAppPicks[id] = picks
        }
        if case .openApp(let id) = button.action, session.icons.image(for: id) == nil {
            session.send(.dockIconRequest(bundleIDs: [id]))
        }
    }

    private func edit(_ change: (inout DeckLayout) -> Void) {
        guard var l = layout else { return }
        change(&l)
        session.saveDeck(l)
        markMigrated()
    }

    /// Saves the one-screen layout on the Mac once, when it is connected and both the Deck and
    /// the macro list have arrived (so no macro is left out).
    private func saveMigrationIfNeeded() {
        guard !isDemo, session.isConnected, let raw = session.deckLayout, session.allMacros != nil,
              !settings.pinnedMigratedMacs.contains(macKey), let moved = layout else { return }
        if moved != raw { session.saveDeck(moved) }
        markMigrated()
    }

    private func markMigrated() {
        guard !isDemo, session.isConnected else { return }
        settings.pinnedMigratedMacs.insert(macKey)
    }
}

/// A drag under way in edit mode: which section, and the order shown so far.
private struct TileDraft: Equatable {
    enum Section { case front, pinned }
    let section: Section
    var order: [String]
}

/// Live reordering while dragging in edit mode: the tile under the finger makes room. The
/// order is only shown until the drop, which saves it.
private struct ReorderDropDelegate: DropDelegate {
    let target: String
    let section: TileDraft.Section
    @Binding var dragging: String?
    @Binding var draft: TileDraft?
    let commit: () -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target, var d = draft, d.section == section,
              let from = d.order.firstIndex(of: dragging), let to = d.order.firstIndex(of: target) else { return }
        d.order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        Haptics.shared.tap()
        withAnimation(.snappy(duration: 0.25)) { draft = d }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        commit()
        return true
    }
}

/// Ends a drag that is dropped between tiles, keeping the order it reached.
private struct EndDragDelegate: DropDelegate {
    let commit: () -> Void
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        commit()
        return true
    }
}

/// The Home Screen style remove button on a tile in edit mode.
private struct RemoveBadge: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.shared.tap()
            withAnimation(.snappy) { action() }
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 22))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color(uiColor: .systemGray))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: -16, y: -16)
        .transition(.scale.combined(with: .opacity))
        .accessibilityLabel(label)
    }
}

/// A one-line first-run explanation with a close button. Gone for good once closed.
private struct Tip: View {
    @Environment(\.palette) private var palette
    var settings = PhoneSettings.shared
    let id: String
    let text: String

    var body: some View {
        if !settings.seenTips.contains(id) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(palette.inkSoftColor)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button {
                    withAnimation(.snappy) { _ = settings.seenTips.insert(id) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.inkSoftColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // A full-size target without pushing the text away.
                .padding(-8)
                .accessibilityLabel("Dismiss tip")
            }
            .transition(.opacity)
        }
    }
}

/// Fixed ids of the Mac's two built-in pages (see DeckConfig on the Mac).
enum DeckIDs {
    static let mac = PinnedDeck.macPageID
    static let mine = PinnedDeck.pinnedPageID
}

struct EditorTarget: Identifiable {
    var id: UUID { button.id }
    let button: DeckButton
    let isNew: Bool
    let page: Int
    let folder: UUID?
    /// A new button starts on the action list (false when the action is already chosen).
    var picksAction = true
    /// A new button for the front app's linked page.
    var front = false
}

/// Present, full screen, with a way back. Opened from the mode menu's Present tool.
struct PresenterCover: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            SurfaceBackground()
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
            .foregroundStyle(palette.inkColor)
            .padding(.leading, 16)
            .padding(.top, 8)
            .accessibilityLabel("Stop presenting")
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
        .simultaneousGesture(TapGesture().onEnded { AppRouter.shared.noteActivity() })
    }
}

/// Clipboard as a small tool: a sheet with a Done button.
struct ClipboardSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ClipboardMode(embedded: true)
                .background(SurfaceBackground())
                .navigationTitle("Clipboard")
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
        }
        .tint(palette.inkColor)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
