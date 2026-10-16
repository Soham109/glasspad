import SwiftUI
import GlasspadKit

// MARK: - Action catalog

/// Every action a button can do, grouped like the Shortcuts app's action library.
struct ActionTemplate: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let color: String
    let action: DeckAction

    static func make(_ id: String, _ title: String, _ detail: String, _ symbol: String, _ color: String, _ action: DeckAction) -> ActionTemplate {
        ActionTemplate(id: id, title: title, detail: detail, symbol: symbol, color: color, action: action)
    }
}

struct ActionCategory: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let items: [ActionTemplate]

    static let all: [ActionCategory] = {
        typealias T = ActionTemplate
        return [
            ActionCategory(id: "open", title: "Open", symbol: "arrow.up.forward.app", items: [
                T.make("app", "Open App", "Launch or switch to an app", "app.badge", "#0A84FF", .openApp(bundleID: "com.apple.Safari")),
                T.make("url", "Open Website", "A link in the Mac's browser", "safari", "#0A84FF", .openURL("https://")),
                T.make("file", "Open File or Folder", "Anything in Finder", "folder.fill", "#34C759", .openFile(path: "~/Downloads")),
                T.make("settings", "Open System Settings", "Go straight to a settings page", "gearshape.fill", "#8E8E93",
                       .openURL("x-apple.systempreferences:com.apple.Displays-Settings.extension")),
            ]),
            ActionCategory(id: "screen", title: "Screen", symbol: "camera.viewfinder", items: [
                T.make("shot", "Screenshot", "Captures every display at once", "camera.viewfinder", "#0A84FF", .screenshot(DeckScreenshot(area: .fullScreen))),
                T.make("window", "Window Screenshot", "Captures the front window", "macwindow", "#0A84FF", .screenshot(DeckScreenshot(area: .frontWindow))),
                T.make("area", "Area Screenshot", "Drag out an area on the Mac", "rectangle.dashed", "#0A84FF", .screenshot(DeckScreenshot(area: .selection))),
                T.make("record", "Screen Recording", "Tap to start, tap again to save", "record.circle", "#FF453A", .screenRecording),
            ]),
        ] + systemCategories + [
            ActionCategory(id: "keyboard", title: "Keyboard", symbol: "keyboard", items: [
                T.make("keys", "Keyboard Shortcut", "Press keys like ⌘C", "command", "#8A63E8",
                       .keystroke(Keystroke(key: .character("c"), modifiers: [.command]))),
                T.make("type", "Type Text", "Types words for you", "text.cursor", "#8A63E8", .typeText("")),
            ]),
            ActionCategory(id: "automation", title: "Automation", symbol: "wand.and.stars", items: [
                T.make("shortcut", "Run Shortcut", "Any shortcut on your Mac", "square.stack.3d.up.fill", "#FF2D55", .runShortcut(name: "")),
                T.make("macro", "Run Macro", "Recorded or built on the Mac", "wand.and.stars", "#12A594", .runMacro(id: UUID())),
            ]),
            ActionCategory(id: "organize", title: "Organize", symbol: "folder", items: [
                T.make("folder", "Folder", "Groups buttons; tap to open", "folder.fill", "#64D2FF", .folder),
            ]),
        ]
    }()

    /// Mac controls, one category per `DeckSystemGroup`, straight from `DeckSystemCatalog`,
    /// so a control added there shows up here (and in the Library) by itself. Sound also
    /// holds the output switcher.
    static let systemCategories: [ActionCategory] = DeckSystemGroup.allCases.map { group in
        var items = DeckSystemAction.allCases.filter { $0.group == group }.map { sys in
            ActionTemplate.make("sys.\(sys.rawValue)", sys.title, sys.detail, sys.symbol, sys.color, .system(sys))
        }
        if group == .sound {
            items.append(.make("output", "Sound Output", "Switch speakers or headphones", "hifispeaker.2.fill", "#FF9F0A", .setAudioOutput(name: "")))
        }
        return ActionCategory(id: group.rawValue, title: group.title, symbol: items.first?.symbol ?? "gearshape", items: items)
    }

    /// The template a saved action came from (for its name in the editor).
    static func template(for action: DeckAction) -> ActionTemplate? {
        let items = all.flatMap(\.items)
        switch action {
        case .openApp: return items.first { $0.id == "app" }
        case .openURL(let s): return items.first { $0.id == (s.hasPrefix("x-apple.systempreferences:") ? "settings" : "url") }
        case .openFile: return items.first { $0.id == "file" }
        case .screenshot(let s): return items.first { $0.id == ["fullScreen": "shot", "frontWindow": "window", "selection": "area"][s.area.rawValue] }
        case .screenRecording: return items.first { $0.id == "record" }
        case .system(let sys): return items.first { $0.action == .system(sys) }
        case .setAudioOutput: return items.first { $0.id == "output" }
        case .keystroke: return items.first { $0.id == "keys" }
        case .typeText: return items.first { $0.id == "type" }
        case .runShortcut: return items.first { $0.id == "shortcut" }
        case .runMacro: return items.first { $0.id == "macro" }
        case .folder: return items.first { $0.id == "folder" }
        case .shellScript, .unsupported: return nil
        }
    }
}

/// System Settings pages that open by URL.
enum SettingsPanes {
    static let all: [(String, String)] = [
        ("Wi-Fi", "com.apple.wifi-settings-extension"), ("Bluetooth", "com.apple.BluetoothSettings"),
        ("Displays", "com.apple.Displays-Settings.extension"), ("Sound", "com.apple.Sound-Settings.extension"),
        ("Battery", "com.apple.Battery-Settings.extension"), ("Focus", "com.apple.Focus-Settings.extension"),
        ("Notifications", "com.apple.Notifications-Settings.extension"), ("Desktop & Dock", "com.apple.Desktop-Settings.extension"),
        ("Keyboard", "com.apple.Keyboard-Settings.extension"), ("Trackpad", "com.apple.Trackpad-Settings.extension"),
        ("Privacy & Security", "com.apple.settings.PrivacySecurity.extension"), ("General", "com.apple.systempreferences.GeneralSettings"),
    ]
    static let prefix = "x-apple.systempreferences:"
}

// MARK: - Button editor

/// Add or edit one button: preview, label, symbol, colour, size and what it does.
struct DeckButtonEditor: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    var session = MacSession.shared
    @State var button: DeckButton
    let isNew: Bool
    let frontAppName: String
    let onSave: (DeckButton) -> Void
    let onDelete: () -> Void

    @State private var pickingAction: Bool
    @State private var confirmDelete = false

    /// `picksAction`: a new button opens on the action list first (false when the action is
    /// already chosen, as from the Library).
    init(button: DeckButton, isNew: Bool, frontAppName: String, picksAction: Bool? = nil,
         onSave: @escaping (DeckButton) -> Void, onDelete: @escaping () -> Void) {
        _button = State(initialValue: button)
        self.isNew = isNew
        self.frontAppName = frontAppName
        self.onSave = onSave
        self.onDelete = onDelete
        _pickingAction = State(initialValue: picksAction ?? isNew)
    }

    static let colors = ["#0A84FF", "#5E5CE6", "#BF5AF2", "#FF375F", "#FF453A", "#FF9F0A",
                         "#FFD60A", "#34C759", "#30B0C7", "#64D2FF", "#8E8E93", "#636366"]
    /// What VoiceOver says for each swatch.
    static let colorNames = ["#0A84FF": "Blue", "#5E5CE6": "Indigo", "#BF5AF2": "Purple", "#FF375F": "Pink",
                             "#FF453A": "Red", "#FF9F0A": "Orange", "#FFD60A": "Yellow", "#34C759": "Green",
                             "#30B0C7": "Teal", "#64D2FF": "Cyan", "#8E8E93": "Gray", "#636366": "Dark Gray"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ActionTile(title: button.title.isEmpty ? "Button" : button.title, face: button.face(icons: session.icons),
                                   folder: button.action == .folder ? (button.children ?? []).prefix(4).map { $0.face(icons: session.icons) } : nil,
                                   size: button.size ?? .regular, showsTitle: true, badge: button.badge) {}
                            .frame(width: previewSize.width, height: previewSize.height)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .animation(.snappy, value: button.size)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Action") {
                    Button {
                        pickingAction = true
                    } label: {
                        HStack(spacing: 12) {
                            let t = ActionCategory.template(for: button.action)
                            let newer = !button.action.isSupported
                            LibraryGlyph(symbol: t?.symbol ?? (newer ? DeckButton.newerSymbol : "terminal"), color: Color(hexString: t?.color) ?? .gray)
                            Text(t?.title ?? (newer ? "Newer Action" : "Shell Script")).foregroundStyle(palette.inkColor)
                            Spacer()
                            Text("Change").foregroundStyle(palette.inkSoftColor)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(palette.inkSoftColor)
                        }
                    }
                    ActionOptions(action: $button.action, title: $button.title)
                }
                .listRowBackground(palette.raisedColor)
                Section("Look") {
                    TextField("Label", text: $button.title)
                    NavigationLink {
                        SymbolPicker(symbol: $button.symbol, tint: button.tint)
                    } label: {
                        LabeledContent(button.action.websiteLink != nil ? "Icon When There's No Logo" : "Icon") {
                            Image(systemName: button.symbol).foregroundStyle(palette.tint(button.tint))
                        }
                    }
                    colorRow
                    Picker("Size", selection: Binding(get: { button.size ?? .regular }, set: { button.size = $0 == .regular ? nil : $0 })) {
                        Text("Small").tag(DeckButtonSize.regular)
                        Text("Wide").tag(DeckButtonSize.wide)
                        Text("Large").tag(DeckButtonSize.large)
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(palette.raisedColor)
                if !isNew {
                    Section {
                        Button("Delete Button", role: .destructive) { confirmDelete = true }
                    }
                    .listRowBackground(palette.raisedColor)
                }
            }
            .scrollContentBackground(.hidden)
            .background(SurfaceBackground())
            .navigationTitle(button.action == .folder ? (isNew ? "New Folder" : "Edit Folder") : (isNew ? "New Button" : "Edit Button"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // "apple.com" is saved as the link it means.
                        if let link = button.action.typedWebsite, let url = SiteInfo.webURL(link) {
                            button.action = .openURL(url.absoluteString)
                        }
                        if button.title.trimmingCharacters(in: .whitespaces).isEmpty {
                            button.title = ActionCategory.template(for: button.action)?.title ?? "Button"
                        }
                        Haptics.shared.play(.snap)
                        onSave(button)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .navigationDestination(isPresented: $pickingAction) {
                ActionPicker { template in
                    let wasDefault = button.title.isEmpty || ActionCategory.all.flatMap(\.items).contains { $0.title == button.title }
                    button.action = template.action
                    button.symbol = template.symbol
                    button.color = template.color
                    if wasDefault { button.title = template.title }
                    if template.action == .folder, button.children == nil { button.children = [] }
                    pickingAction = false
                }
            }
            .confirmationDialog("Delete this button?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            }
            .onAppear {
                if session.deckCatalog == nil { session.send(.deckCatalogRequest) }
                if session.dockCatalog.isEmpty { session.send(.dockCatalogRequest) }
            }
        }
        .tint(palette.inkColor)
    }

    private var previewSize: CGSize {
        switch button.size ?? .regular {
        case .regular: CGSize(width: 104, height: 104)
        case .wide: CGSize(width: 218, height: 104)
        case .large: CGSize(width: 168, height: 168)
        }
    }

    /// A Website button needs a real web address.
    private var canSave: Bool {
        if let link = button.action.typedWebsite { return SiteInfo.webURL(link) != nil }
        return true
    }

    private var colorRow: some View {
        // Two even rows of six, so every swatch shows whole at any width.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
            ForEach(Self.colors, id: \.self) { hex in
                let selected = (button.color ?? "").uppercased() == hex
                Button {
                    Haptics.shared.tap()
                    button.color = hex
                } label: {
                    Circle()
                        .fill(Color(hexString: hex) ?? .gray)
                        .frame(width: 30, height: 30)
                        .overlay { if selected { Circle().strokeBorder(.white, lineWidth: 2.5).padding(2) } }
                        .overlay { Circle().strokeBorder(palette.lineColor) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.colorNames[hex] ?? "Color")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

/// The settings each action needs (which app, which link, which keys...).
private struct ActionOptions: View {
    @Environment(\.palette) private var palette
    var session = MacSession.shared
    @Binding var action: DeckAction
    @Binding var title: String
    /// The label last filled in from a website, so it can follow a changed link.
    @State private var autoTitle: String?

    var body: some View {
        switch action {
        case .openApp(let id):
            NavigationLink {
                AppPickerList(selected: id) { app in
                    action = .openApp(bundleID: app.bundleID)
                    title = app.name
                    session.send(.dockIconRequest(bundleIDs: [app.bundleID]))
                }
            } label: {
                LabeledContent("App", value: appName(id))
            }
        case .openURL(let s) where s.hasPrefix(SettingsPanes.prefix):
            Picker("Page", selection: Binding(get: { String(s.dropFirst(SettingsPanes.prefix.count)) },
                                              set: { action = .openURL(SettingsPanes.prefix + $0) })) {
                ForEach(SettingsPanes.all, id: \.1) { Text($0.0).tag($0.1) }
            }
        case .openURL(let s):
            HStack(spacing: 12) {
                WebsiteLogo(link: s, tint: Color(uiColor: .systemBlue), size: 30)
                TextField("apple.com", text: Binding(get: { s == "https://" ? "" : s }, set: { action = .openURL($0) }))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
            }
            // Names the button after the site while the user has not named it.
            .task(id: s) { await nameAfterSite(s) }
            if !s.isEmpty, s != "https://", action.typedWebsite != nil, SiteInfo.webURL(s) == nil {
                Text("Type a web address, like apple.com.").font(.footnote).foregroundStyle(palette.inkSoftColor)
            }
        case .openFile(let path):
            TextField("~/Documents", text: Binding(get: { path }, set: { action = .openFile(path: $0) }))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Picker("Common", selection: Binding(get: { path }, set: { action = .openFile(path: $0) })) {
                ForEach(["~/Desktop", "~/Documents", "~/Downloads", "~", "/Applications", path].uniqued(), id: \.self) { Text($0).tag($0) }
            }
        case .screenshot(var shot):
            Picker("Capture", selection: Binding(get: { shot.area }, set: { shot.area = $0; action = .screenshot(shot) })) {
                Text("Whole Screen").tag(DeckCaptureArea.fullScreen)
                Text("Front Window").tag(DeckCaptureArea.frontWindow)
                Text("Area You Drag").tag(DeckCaptureArea.selection)
            }
            Picker("Send to iPhone", selection: Binding(get: { shot.sendToPhone }, set: { shot.sendToPhone = $0; action = .screenshot(shot) })) {
                Text("Off").tag(DeckImageDestination?.none)
                Text("Save to Photos").tag(DeckImageDestination?.some(.photos))
                Text("Copy to Clipboard").tag(DeckImageDestination?.some(.clipboard))
            }
            Toggle("Copy to Mac Clipboard", isOn: Binding(get: { shot.copyToMacClipboard ?? false },
                                                          set: { shot.copyToMacClipboard = $0; action = .screenshot(shot) }))
            Text("Saved where your Mac saves screenshots, right away, without the screenshot toolbar.")
                .font(.footnote).foregroundStyle(palette.inkSoftColor)
        case .setAudioOutput(let name):
            if let outputs = session.deckCatalog?.audioOutputs, !outputs.isEmpty {
                Picker("Output", selection: Binding(get: { name }, set: { action = .setAudioOutput(name: $0) })) {
                    ForEach((outputs + [name]).uniqued().filter { !$0.isEmpty }, id: \.self) { Text($0).tag($0) }
                }
            } else {
                TextField("Output name", text: Binding(get: { name }, set: { action = .setAudioOutput(name: $0) }))
            }
        case .runShortcut(let name):
            if let names = session.deckCatalog?.shortcuts, !names.isEmpty {
                Picker("Shortcut", selection: Binding(get: { name }, set: { action = .runShortcut(name: $0) })) {
                    ForEach((names + [name]).uniqued().filter { !$0.isEmpty }, id: \.self) { Text($0).tag($0) }
                }
            }
            TextField("Shortcut name", text: Binding(get: { name }, set: { action = .runShortcut(name: $0) }))
        case .runMacro(let id):
            let macros = session.allMacros ?? []
            if macros.isEmpty {
                Text("No macros yet. To record one, tap + in Actions, then Record New Macro.").foregroundStyle(palette.inkSoftColor)
            } else {
                Picker("Macro", selection: Binding(get: { id }, set: { new in
                    action = .runMacro(id: new)
                    if let m = macros.first(where: { $0.id == new }) { title = m.name }
                })) {
                    if !macros.contains(where: { $0.id == id }) { Text("Choose").tag(id) }
                    ForEach(macros) { Text($0.name).tag($0.id) }
                }
            }
        case .keystroke(let k):
            KeystrokeEditor(keystroke: Binding(get: { k }, set: { action = .keystroke($0) }))
        case .typeText(let text):
            TextField("Text to type", text: Binding(get: { text }, set: { action = .typeText($0) }), axis: .vertical)
                .lineLimit(1...4)
        case .folder:
            Text("Save, then tap the folder and add buttons inside it.")
                .font(.footnote).foregroundStyle(palette.inkSoftColor)
        case .shellScript:
            Text("Shell scripts are set up and allowed on the Mac only.")
                .font(.footnote).foregroundStyle(palette.inkSoftColor)
        case .unsupported:
            Text(DeckAction.updateToUse).font(.footnote).foregroundStyle(palette.inkSoftColor)
        case .system(let s):
            if s.needsConfirmation {
                Text("You will be asked to confirm each time.").font(.footnote).foregroundStyle(palette.inkSoftColor)
            }
        case .screenRecording:
            Text("Tap once to start recording the screen, again to stop. The movie is saved with your screenshots.")
                .font(.footnote).foregroundStyle(palette.inkSoftColor)
        }
    }

    /// Fills the label from the site (its own name, else one from the address) unless the
    /// user typed a label of their own.
    private func nameAfterSite(_ link: String) async {
        guard let url = SiteInfo.webURL(link), let host = SiteInfo.key(for: url) else { return }
        let generic = ["", "Open Website", "Website", autoTitle ?? ""]
        guard generic.contains(title.trimmingCharacters(in: .whitespaces)) else { return }
        let quick = SiteInfo.name(fromHost: host)
        title = quick
        autoTitle = quick
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled, let fetched = await WebsiteIcons.shared.title(for: link),
              title == quick, !Task.isCancelled else { return }
        title = fetched
        autoTitle = fetched
    }

    private func appName(_ id: String) -> String {
        (session.dockApps + session.dockCatalog).first { $0.bundleID == id }?.name ?? id
    }
}

private struct KeystrokeEditor: View {
    @Environment(\.palette) private var palette
    @Binding var keystroke: Keystroke

    private static let specials: [(String, SpecialKey)] = [
        ("Return", .returnKey), ("Tab", .tab), ("Space", .space), ("Delete", .delete), ("Escape", .escape),
        ("Left", .left), ("Right", .right), ("Up", .up), ("Down", .down), ("Page Up", .pageUp), ("Page Down", .pageDown),
    ]

    var body: some View {
        HStack(spacing: 8) {
            modifier("command", .command)
            modifier("shift", .shift)
            modifier("option", .option)
            modifier("control", .control)
        }
        Picker("Key", selection: Binding(get: { keyTag }, set: { setKey($0) })) {
            ForEach("abcdefghijklmnopqrstuvwxyz0123456789".map(String.init), id: \.self) { Text($0.uppercased()).tag($0) }
            ForEach(Self.specials, id: \.0) { Text($0.0).tag("special:" + $0.1.rawValue) }
        }
    }

    private var keyTag: String {
        switch keystroke.key {
        case .character(let c): c.lowercased()
        case .special(let s): "special:" + s.rawValue
        }
    }

    private func setKey(_ tag: String) {
        if tag.hasPrefix("special:"), let s = SpecialKey(rawValue: String(tag.dropFirst(8))) {
            keystroke.key = .special(s)
        } else {
            keystroke.key = .character(tag)
        }
    }

    private func modifier(_ symbol: String, _ m: KeyModifiers) -> some View {
        let on = keystroke.modifiers.contains(m)
        return Button {
            if on { keystroke.modifiers.remove(m) } else { keystroke.modifiers.insert(m) }
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 36)
                .foregroundStyle(on ? palette.solidColor : palette.inkColor)
                .background(on ? palette.inkColor : palette.raisedPressedColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Every action, by category, with search.
struct ActionPicker: View {
    @Environment(\.palette) private var palette
    let onPick: (ActionTemplate) -> Void
    @State private var query = ""

    private var categories: [ActionCategory] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return ActionCategory.all }
        return ActionCategory.all.compactMap { c in
            let items = c.items.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.detail.localizedCaseInsensitiveContains(q)
                || c.title.localizedCaseInsensitiveContains(q) }
            return items.isEmpty ? nil : ActionCategory(id: c.id, title: c.title, symbol: c.symbol, items: items)
        }
    }

    var body: some View {
        List {
            ForEach(categories) { category in
                Section(category.title) {
                    ForEach(category.items) { item in
                        Button {
                            Haptics.shared.tap()
                            onPick(item)
                        } label: {
                            HStack(spacing: 12) {
                                LibraryGlyph(symbol: item.symbol, color: Color(hexString: item.color) ?? .gray)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title).foregroundStyle(palette.inkColor)
                                    if !item.detail.isEmpty {
                                        Text(item.detail).font(.footnote).foregroundStyle(palette.inkSoftColor)
                                    }
                                }
                            }
                        }
                    }
                }
                .listRowBackground(palette.raisedColor)
            }
            if categories.isEmpty {
                Text("No actions match \u{201C}\(query)\u{201D}.").foregroundStyle(palette.inkSoftColor)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(SurfaceBackground())
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search actions")
        .navigationTitle("Choose an Action")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Installed Mac apps with search.
private struct AppPickerList: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    var session = MacSession.shared
    let selected: String
    let onPick: (DockApp) -> Void
    @State private var query = ""

    private var apps: [DockApp] {
        let pool = session.dockApps + session.dockCatalog
        if query.isEmpty {
            var seen = Set<String>()
            return pool.filter { seen.insert($0.bundleID).inserted }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return DockArrangement.search(query, in: pool)
    }

    var body: some View {
        List(apps, id: \.bundleID) { app in
            Button {
                onPick(app)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    DockIcon(app: app, icon: session.icons.image(for: app.bundleID), size: 34)
                    Text(app.name).foregroundStyle(palette.inkColor)
                    Spacer()
                    if app.bundleID == selected { Image(systemName: "checkmark").fontWeight(.semibold) }
                }
            }
            .listRowBackground(palette.raisedColor)
        }
        .overlay {
            if apps.isEmpty {
                QuietMessage(symbol: "app.dashed", title: session.dockCatalog.isEmpty ? "Loading apps" : "No apps found",
                             detail: "Apps come from your Mac.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(SurfaceBackground())
        .searchable(text: $query, prompt: "Search apps")
        .navigationTitle("Choose an App")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if session.dockCatalog.isEmpty { session.send(.dockCatalogRequest) } }
    }
}

/// A curated set of SF Symbols, with search over their names.
struct SymbolPicker: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Binding var symbol: String
    let tint: Color
    @State private var query = ""

    static let symbols: [String] = [
        "bolt.fill", "star.fill", "heart.fill", "flag.fill", "bookmark.fill", "tag.fill", "bell.fill", "pin.fill",
        "camera.viewfinder", "camera.fill", "macwindow", "rectangle.dashed", "record.circle", "video.fill", "photo.fill",
        "lock.fill", "moon.fill", "sun.max.fill", "sun.min.fill", "circle.lefthalf.filled", "powersleep", "power",
        "speaker.plus.fill", "speaker.minus.fill", "speaker.slash.fill", "mic.fill", "mic.slash.fill", "headphones",
        "hifispeaker.2.fill", "playpause.fill", "forward.fill", "backward.fill", "music.note", "airplayaudio",
        "safari", "globe", "link", "envelope.fill", "message.fill", "phone.fill", "calendar", "clock.fill", "alarm.fill",
        "folder.fill", "doc.fill", "doc.text.fill", "tray.full.fill", "archivebox.fill", "trash.fill", "externaldrive.fill", "eject.fill",
        "keyboard", "command", "option", "control", "return", "delete.left.fill", "text.cursor", "textformat",
        "wand.and.stars", "sparkles", "square.stack.3d.up.fill", "gearshape.fill", "slider.horizontal.3", "wrench.and.screwdriver.fill",
        "hammer.fill", "terminal.fill", "chevron.left.forwardslash.chevron.right", "paintbrush.fill", "pencil", "scissors",
        "rectangle.3.group", "menubar.dock.rectangle", "square.grid.3x3", "rectangle.stack", "macbook", "display", "iphone",
        "cursorarrow.click", "hand.tap.fill", "magnifyingglass", "eye.fill", "bubble.left.fill", "person.fill", "house.fill",
        "cart.fill", "creditcard.fill", "chart.bar.fill", "lightbulb.fill", "leaf.fill", "flame.fill", "cloud.fill", "wifi",
        "arrow.clockwise", "arrow.uturn.backward", "arrow.up.forward.app", "plus.circle.fill", "checkmark.circle.fill", "xmark.circle.fill",
    ]

    private var shown: [String] {
        query.isEmpty ? Self.symbols : Self.symbols.filter { $0.localizedCaseInsensitiveContains(query) }
            + (UIImage(systemName: query.lowercased()) != nil && !Self.symbols.contains(query.lowercased()) ? [query.lowercased()] : [])
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
                ForEach(shown, id: \.self) { name in
                    Button {
                        Haptics.shared.tap()
                        symbol = name
                        dismiss()
                    } label: {
                        let t = palette.tint(tint)
                        Image(systemName: name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(name == symbol ? (palette.monochrome ? palette.backgroundColor : Color.white) : t)
                            .frame(width: 52, height: 52)
                            .background(name == symbol ? t : palette.raisedColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name.replacingOccurrences(of: ".", with: " "))
                }
            }
            .padding(16)
        }
        .background(SurfaceBackground())
        .searchable(text: $query, prompt: "Search symbols")
        .navigationTitle("Icon")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Pages

/// Rename, reorder, add, delete pages and link them to Mac apps.
struct DeckPagesSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    var session = MacSession.shared
    @State var layout: DeckLayout
    let onSave: (DeckLayout) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($layout.pages) { $page in
                        NavigationLink {
                            PageEditor(page: $page)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: page.symbol ?? "square.grid.2x2").frame(width: 26)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(page.title)
                                    Text(pageDetail(page)).font(.footnote).foregroundStyle(palette.inkSoftColor)
                                }
                            }
                        }
                    }
                    .onMove { layout.pages.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { layout.pages.remove(atOffsets: $0) }
                    Button("Add Page", systemImage: "plus") {
                        layout.pages.append(DeckPage(title: "New Page", symbol: "square.grid.2x2", buttons: []))
                    }
                } footer: {
                    Text("A page linked to apps shows up by itself in Actions while one of those apps is in front on your Mac.")
                }
                .listRowBackground(palette.raisedColor)
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(SurfaceBackground())
            .navigationTitle("Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(layout)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(palette.inkColor)
    }

    private func pageDetail(_ p: DeckPage) -> String {
        let n = "\(p.buttons.count) button\(p.buttons.count == 1 ? "" : "s")"
        guard let ids = p.appBundleIDs, !ids.isEmpty else { return n }
        let names = ids.map { id in (session.dockApps + session.dockCatalog).first { $0.bundleID == id }?.name ?? id }
        return "\(n) · for \(names.joined(separator: ", "))"
    }
}

private struct PageEditor: View {
    @Environment(\.palette) private var palette
    var session = MacSession.shared
    @Binding var page: DeckPage

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $page.title)
            }
            .listRowBackground(palette.raisedColor)
            Section {
                ForEach(page.appBundleIDs ?? [], id: \.self) { id in
                    let app = (session.dockApps + session.dockCatalog).first { $0.bundleID == id }
                    HStack(spacing: 12) {
                        DockIcon(app: app ?? DockApp(bundleID: id, name: id, running: false, active: false),
                                 icon: session.icons.image(for: id), size: 28)
                        Text(app?.name ?? id)
                    }
                }
                .onDelete { page.appBundleIDs?.remove(atOffsets: $0) }
                NavigationLink("Link an App") {
                    AppPickerList(selected: "") { app in
                        var ids = page.appBundleIDs ?? []
                        if !ids.contains(app.bundleID) { ids.append(app.bundleID) }
                        page.appBundleIDs = ids
                    }
                }
            } header: {
                Text("Show For")
            } footer: {
                Text("Linked pages appear on the front-app page in Actions.")
            }
            .listRowBackground(palette.raisedColor)
        }
        .scrollContentBackground(.hidden)
        .background(SurfaceBackground())
        .navigationTitle(page.title)
    }
}

extension DeckAction {
    /// What the user typed for a Website button (not a System Settings page), even when it is
    /// not a full link yet. Other kinds of links ("mailto:", "slack://") are kept as they are.
    var typedWebsite: String? {
        guard case .openURL(let s) = self, !s.hasPrefix(SettingsPanes.prefix) else { return nil }
        if let scheme = URL(string: s)?.scheme?.lowercased(), scheme != "http", scheme != "https",
           SiteInfo.webURL(s) == nil { return nil }
        return s
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
