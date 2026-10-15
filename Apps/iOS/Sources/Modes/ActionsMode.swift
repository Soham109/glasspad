import SwiftUI
import UniformTypeIdentifiers
import GlasspadKit

/// Actions: one screen, no tabs.
///
/// 1. The app in front on the Mac, with its best buttons (at most eight): the buttons of the
///    Deck page linked to that app, then the macros of its macro profile. Which ones show, and
///    in what order, is the user's choice.
/// 2. Pinned: one grid of favourites. Mac controls, apps, macros, Shortcuts and keystrokes all
///    look the same here. The + tile at the end opens the Library.
///
/// Clipboard and Present are small tools in the mode menu now (or full modes when Actions is
/// split up in Settings). Deck mode, for people who split, is this same screen.
struct ActionsMode: View {
    @Environment(\.palette) private var palette
    @Environment(\.verticalSizeClass) private var verticalSize
    @Bindable var settings = PhoneSettings.shared
    var session = MacSession.shared
    var router = AppRouter.shared

    private var compact: Bool { verticalSize == .compact }

    @State private var editing = false
    @State private var folderPath: [UUID] = []
    @State private var editorTarget: EditorTarget?
    @State private var confirming: DeckButton?
    @State private var dragging: UUID?
    @State private var showLibrary = false
    @State private var showFrontPicker = false
    /// Macro ids known when "Record New Macro" was tapped; the new one gets pinned.
    @State private var macrosBeforeRecording: Set<UUID>?

    private var accent: Color { AppMode.actions.accent(palette) }

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
        guard let id = frontID else { return "No App" }
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
        PinnedDeck.frontAppItems(buttons: frontButtons, macros: profileMacros,
                                 picks: frontID.flatMap { settings.frontAppPicks[$0] })
    }

    private var pinnedIndex: Int? { layout.flatMap(PinnedDeck.pinnedIndex(in:)) }

    private var pinnedButtons: [DeckButton] {
        guard let layout, let i = pinnedIndex else { return [] }
        return layout.buttons(page: i, folder: folderPath.last)
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let metrics = ActionGridMetrics.fit(width: geo.size.width - 32, scale: settings.deckTileScale)
            if layout == nil && !session.isConnected && session.macroProfile == nil {
                ModeOfflineMessage(mode: .actions)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        frontSection(metrics: metrics)
                        pinnedSection(metrics: metrics)
                            .padding(.top, compact ? 22 : 30)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, settings.pillPosition == .top ? (compact ? 44 : 64) : 16)
                    .padding(.bottom, 24)
                    .animation(.snappy, value: editing)
                    .animation(.snappy, value: folderPath)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    session.send(.deckRequest)
                    session.send(.macro(.listMacros))
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
        .onAppear {
            session.send(.deckRequest)
            session.send(.macro(.listMacros))
            if session.dockCatalog.isEmpty { session.send(.dockCatalogRequest) }
            if session.deckCatalog == nil { session.send(.deckCatalogRequest) }
            saveMigrationIfNeeded()
            #if DEBUG
            if DebugLaunch.demoEditing { editing = true }
            if DebugLaunch.demoActionsPage == "library" { showLibrary = true }
            if DebugLaunch.demoActionsPage == "front" { showFrontPicker = true }
            if DebugLaunch.demoActionsPage == "editor", let b = pinnedButtons.first(where: { $0.action != .folder }) { open(b, page: pinnedIndex ?? 0) }
            if DebugLaunch.demoActionsPage == "folder", let f = pinnedButtons.first(where: { $0.action == .folder && !($0.children ?? []).isEmpty }) {
                folderPath = [f.id]
            }
            #endif
        }
        .onChange(of: session.deckLayout) { saveMigrationIfNeeded() }
        .onChange(of: session.allMacros) {
            saveMigrationIfNeeded()
            pinRecordedMacros()
        }
        .onChange(of: session.isConnected) { saveMigrationIfNeeded() }
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

    // MARK: Front app

    private func frontSection(metrics: ActionGridMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .center, spacing: 12) {
            frontGlyph
            Text(frontName)
                .font(compact ? .title2.bold() : .title.bold())
                .foregroundStyle(palette.inkColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            headerButton
        }
        Tip(id: "actions.front", text: "The best buttons for the app in front on your Mac. They change when you switch apps.")
            .padding(.top, 8)
        let items = frontItems
        if items.isEmpty {
            HStack(spacing: 12) {
                Text(frontID == nil ? "Open an app on your Mac to see its buttons here." : "No buttons for \(frontName) yet.")
                    .font(.subheadline)
                    .foregroundStyle(palette.inkSoftColor)
                Spacer(minLength: 8)
                if frontID != nil {
                    Button("Add", systemImage: "plus") { addFrontButton() }
                        .font(.subheadline.weight(.semibold))
                        .glassButton()
                        .disabled(!session.isConnected)
                }
            }
            .padding(.top, 14)
        } else {
            PackedGrid(metrics: metrics) {
                ForEach(items) { item in
                    frontTile(item).tileSpan(.regular)
                }
                if editing {
                    ActionTile(title: "Choose", symbol: "checklist", tint: palette.inkColor, showsTitle: true, style: .outlined) {
                        showFrontPicker = true
                    }
                    .accessibilityLabel("Choose buttons for \(frontName)")
                }
            }
            .padding(.top, 14)
        }
        }
    }

    @ViewBuilder private var frontGlyph: some View {
        if let id = frontID, let icon = session.icons.image(for: id) {
            Image(uiImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: compact ? 28 : 34, height: compact ? 28 : 34)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "macwindow")
                .font(.title3.weight(.medium))
                .foregroundStyle(palette.inkSoftColor)
                .frame(width: compact ? 28 : 34, height: compact ? 28 : 34)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func frontTile(_ item: FrontAppItem) -> some View {
        switch item {
        case .button(let button):
            deckTile(button, page: linkedPageIndex ?? 0, siblings: nil)
        case .macro(let macro):
            ActionTile(title: macro.name, symbol: macro.symbol, tint: macro.tint, showsTitle: settings.deckShowsTitles,
                       pending: session.macroPendingID == macro.id,
                       progress: session.macroRunning?.macroID == macro.id ? session.macroRunning?.fraction : nil,
                       editing: editing) {
                if editing { showFrontPicker = true; return }
                Haptics.shared.play(.click)
                session.runMacro(macro.id)
            }
            .overlay(alignment: .topLeading) {
                if editing { RemoveBadge(label: "Hide \(macro.name)") { hideFront(FrontAppItem.macro(macro).id) } }
            }
            .accessibilityLabel(macro.name)
            .accessibilityValue("Macro, \(macro.stepCount) steps")
            .contextMenu {
                Button("Choose Buttons for \(frontName)", systemImage: "checklist") { showFrontPicker = true }
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
                .font(.body.weight(.semibold))
                .glassButton(prominent: true)
            } else {
                Button("Edit") {
                    Haptics.shared.tap()
                    editing = true
                }
                .font(.body.weight(.medium))
                .glassButton()
                .foregroundStyle(palette.inkColor)
                .disabled(layout == nil)
            }
        }
    }

    // MARK: Pinned

    private func pinnedSection(metrics: ActionGridMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 10) {
            if let folder = folderPath.last.flatMap({ layout?.button(id: $0) }) {
                Button {
                    Haptics.shared.tap()
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
        if folderPath.isEmpty {
            Tip(id: "actions.pinned", text: "Your favourites. Tap + to add anything; touch and hold one to change it.")
                .padding(.top, 8)
        }
        let buttons = pinnedButtons
        PackedGrid(metrics: metrics) {
            ForEach(buttons) { button in
                deckTile(button, page: pinnedIndex ?? 0, siblings: buttons.map(\.id))
                    .tileSpan(button.size)
            }
            ActionTile(title: "Add", symbol: "plus", tint: palette.inkSoftColor, showsTitle: true, style: .outlined) {
                Haptics.shared.tap()
                showLibrary = true
            }
            .accessibilityLabel(folderPath.isEmpty ? "Add to Pinned" : "Add to this folder")
        }
        .padding(.top, 14)
        }
    }

    private var optionsMenu: some View {
        Menu {
            Button("New Folder", systemImage: "folder.badge.plus") { newFolder() }
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
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .glassButton()
        .buttonBorderShape(.circle)
        .foregroundStyle(palette.inkColor)
        .accessibilityLabel("Pinned options")
    }

    // MARK: Tiles

    /// One Deck button. `siblings` enables drag to reorder in edit mode (Pinned only).
    private func deckTile(_ button: DeckButton, page index: Int, siblings: [UUID]?) -> some View {
        var icon: UIImage?
        if case .openApp(let id) = button.action { icon = session.icons.image(for: id) }
        let tile = ActionTile(title: button.title, symbol: button.symbol, tint: button.tint, appIcon: icon,
                              size: button.size ?? .regular, showsTitle: settings.deckShowsTitles,
                              badge: button.action == .folder ? "folder.fill" : nil,
                              pending: session.deckPending.contains(button.id),
                              succeeded: session.deckOutcomes[button.id]?.ok == true, editing: editing) {
            tap(button, page: index, inPinned: siblings != nil)
        }
        .overlay(alignment: .topLeading) {
            if editing {
                RemoveBadge(label: siblings == nil ? "Hide \(button.title)" : "Remove \(button.title)") {
                    if siblings == nil { hideFront(FrontAppItem.button(button).id) } else { edit { $0.remove(id: button.id) } }
                }
            }
        }
        .opacity(dragging == button.id ? 0.35 : 1)
        .accessibilityLabel(button.title)
        .accessibilityHint(editing ? "Edits this button" : button.action.spokenHint)
        .accessibilityAction(named: "Edit") { open(button, page: index) }
        return Group {
            if editing, let siblings {
                tile
                    .onDrag {
                        dragging = button.id
                        return NSItemProvider(object: button.id.uuidString as NSString)
                    }
                    .onDrop(of: [UTType.text], delegate: TileDropDelegate(target: button.id, siblings: siblings, dragging: $dragging) { id, to in
                        edit { $0.move(id: id, to: to, page: index, folder: folderPath.last) }
                    })
            } else {
                tile.contextMenu {
                    Button("Edit", systemImage: "pencil") { open(button, page: index) }
                    if siblings != nil {
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
                        Button("Hide Here", systemImage: "eye.slash", role: .destructive) { hideFront(FrontAppItem.button(button).id) }
                    }
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

    private func tap(_ button: DeckButton, page: Int, inPinned: Bool) {
        if editing {
            open(button, page: page)
            return
        }
        if button.action == .folder {
            Haptics.shared.tap()
            folderPath.append(button.id)
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
        settings.frontAppPicks[id] = frontItems.map(\.id).filter { $0 != key }
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
        .offset(x: -18, y: -18)
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
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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

/// Present, full screen, with a way back. Opened from the mode menu's Present tool.
struct PresenterCover: View {
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
                .background(palette.backgroundColor.ignoresSafeArea())
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
