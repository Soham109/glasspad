import AppKit
import GlasspadMacCore
import GlasspadMacros
import SwiftUI
import UniformTypeIdentifiers

/// Settings > Macros: the macro library (record, rename, icon and colour, steps, scripts) and
/// the per-app profiles that decide which buttons the phone shows.
struct MacrosSettings: View {
    @EnvironmentObject private var controller: GlasspadController
    @State private var page = Page.macros

    enum Page: Hashable { case macros, profiles }

    var body: some View {
        MacrosSettingsContent(macros: controller.macros, page: $page)
    }
}

private struct MacrosSettingsContent: View {
    @ObservedObject var macros: MacroCoordinator
    @Binding var page: MacrosSettings.Page

    var body: some View {
        VStack(spacing: 0) {
            if macros.isRecording {
                RecordingBanner(macros: macros)
                Divider()
            }
            Picker("Show", selection: $page) {
                Text("Macros").tag(MacrosSettings.Page.macros)
                Text("App Profiles").tag(MacrosSettings.Page.profiles)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, 10)
            Divider()
            switch page {
            case .macros: MacroLibrary(macros: macros)
            case .profiles: ProfileLibrary(macros: macros)
            }
            if let error = macros.lastError {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.callout)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Dismiss") { macros.clearError() }
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }
}

/// Shown at the top of the Macros pane while recording, alongside the floating indicator.
struct RecordingBanner: View {
    @ObservedObject var macros: MacroCoordinator

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "record.circle.fill")
                .foregroundStyle(.red)
                .symbolEffect(.pulse, options: .repeating)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text("Recording your keyboard and mouse")
                    .font(.headline)
                Text("Press ⌃⌥⌘. or click Stop when you are done. Password fields are never recorded.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Stop") { macros.stopRecording(fromMacMenu: true) }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.08))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Macro library

private struct MacroLibrary: View {
    @ObservedObject var macros: MacroCoordinator
    @State private var selection: UUID?
    @State private var confirmDelete: Macro?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(macros.macros) { macro in
                        MacroRow(macro: macro)
                            .tag(macro.id)
                            .contextMenu {
                                Button("Run Now") { Task { await macros.run(macro.id) } }
                                Divider()
                                Button("Delete…", role: .destructive) { confirmDelete = macro }
                            }
                    }
                }
                .listStyle(.sidebar)
                .overlay {
                    if macros.macros.isEmpty {
                        ContentUnavailableView("No Macros", systemImage: "wand.and.stars",
                                               description: Text("Record one, or add one with +."))
                    }
                }
                Divider()
                HStack(spacing: 2) {
                    Menu {
                        Button("New Macro") { newMacro() }
                        Button("Record New Macro…") { macros.startRecording() }
                            .disabled(macros.isRecording)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Add a macro")
                    Button {
                        if let id = selection, let m = macros.macro(id) { confirmDelete = m }
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selection == nil)
                    .help("Delete the selected macro")
                    Spacer()
                    Button {
                        if macros.isRecording { macros.stopRecording(fromMacMenu: true) } else { macros.startRecording() }
                    } label: {
                        Image(systemName: macros.isRecording ? "stop.circle.fill" : "record.circle")
                            .foregroundStyle(macros.isRecording ? .red : .primary)
                    }
                    .help(macros.isRecording ? "Stop recording" : "Record a new macro")
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 220)
            Divider()
            Group {
                if let id = selection, let macro = macros.macro(id) {
                    MacroEditor(macros: macros, original: macro)
                        .id(macro.id)
                } else {
                    ContentUnavailableView("No Macro Selected", systemImage: "wand.and.stars",
                                           description: Text("Pick a macro to edit its steps, icon and colour."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: macros.lastRecordedID) { _, id in if let id { selection = id } }
        .onAppear { if selection == nil { selection = macros.macros.first?.id } }
        .confirmationDialog("Delete “\(confirmDelete?.name ?? "")”?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }
        ), presenting: confirmDelete) { macro in
            Button("Delete", role: .destructive) {
                do {
                    try macros.delete(macro.id)
                    if selection == macro.id { selection = macros.macros.first?.id }
                } catch {}
            }
        } message: { _ in
            Text("The macro is removed from every profile. This cannot be undone.")
        }
    }

    private func newMacro() {
        let m = Macro(name: uniqueName("New Macro"), steps: [], origin: .user)
        try? macros.save(m)
        selection = m.id
    }

    private func uniqueName(_ base: String) -> String {
        let names = Set(macros.macros.map(\.name))
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}

private struct MacroRow: View {
    let macro: Macro

    var body: some View {
        HStack(spacing: 8) {
            MacroIcon(symbol: macro.symbol, color: macro.color, size: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(macro.name)
                    .lineLimit(1)
                Text(macro.steps.count == 1 ? "1 step" : "\(macro.steps.count) steps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The macro's SF Symbol on its colour, as the phone draws the button.
struct MacroIcon: View {
    let symbol: String
    let color: String
    let size: CGFloat

    var body: some View {
        Image(systemName: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil ? "questionmark" : symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: color) ?? .accentColor, in: .rect(cornerRadius: size * 0.24))
            .accessibilityHidden(true)
    }
}

// MARK: - Macro editor

private struct MacroEditor: View {
    @ObservedObject var macros: MacroCoordinator
    let original: Macro
    @State private var draft: Macro
    @State private var editing: StepEdit?
    @State private var saveTask: Task<Void, Never>?
    @State private var confirmDelete = false

    struct StepEdit: Identifiable {
        let id = UUID()
        /// nil appends a new step.
        var index: Int?
        var step: MacroStep
    }

    init(macros: MacroCoordinator, original: Macro) {
        self.macros = macros
        self.original = original
        _draft = State(initialValue: original)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name)
                LabeledContent("Icon") {
                    SymbolPicker(symbol: $draft.symbol, color: draft.color)
                }
                ColorPicker("Colour", selection: colorBinding, supportsOpacity: false)
            }

            Section {
                if draft.steps.isEmpty {
                    Text("No steps yet. Add one below, or record a new macro.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(draft.steps.enumerated()), id: \.offset) { index, step in
                    StepRow(index: index, step: step)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { editing = StepEdit(index: index, step: step) }
                        .contextMenu { stepMenu(index, step) }
                        .overlay(alignment: .trailing) {
                            Menu {
                                stepMenu(index, step)
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .accessibilityLabel("Step \(index + 1) actions")
                        }
                }
            } header: {
                Text("Steps")
            } footer: {
                HStack {
                    Menu("Add Step") {
                        ForEach(StepKind.addable, id: \.self) { kind in
                            Button {
                                editing = StepEdit(index: nil, step: kind.template)
                            } label: {
                                Label(kind.title, systemImage: kind.symbol)
                            }
                        }
                    }
                    .fixedSize()
                    Spacer()
                    Text("Double-click a step to edit it.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section {
                TextField("Phone gestures", text: gestureText, prompt: Text("e.g. fourFingerTap"))
                LabeledContent("Mac hotkey", value: draft.hotkey?.displayString ?? "None")
            } header: {
                Text("Triggers")
            } footer: {
                Text("Separate several gesture names with commas. A gesture runs the macro from the phone's trackpad.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Allow scripts", isOn: $draft.allowScripts)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shell commands and AppleScript can do anything you can do on this Mac, including deleting files and reading your documents. Turn this on only for steps you wrote yourself or fully understand.")
                    if draft.needsScriptPermission && !draft.allowScripts {
                        Label("This macro has script steps, so it will not run until scripts are allowed.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button {
                        flushSave()
                        Task { await macros.run(draft.id) }
                    } label: {
                        Label("Run Now", systemImage: "play.fill")
                    }
                    .disabled(draft.steps.isEmpty || macros.runningMacroID != nil)
                    if macros.runningMacroID == draft.id {
                        Button("Stop") { macros.cancelRun() }
                        if let p = macros.lastProgress, p.macroID == draft.id {
                            ProgressView(value: p.fraction)
                                .frame(width: 80)
                        }
                    }
                    Spacer()
                    Button("Delete Macro…", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: draft) { _, _ in scheduleSave() }
        .onDisappear { flushSave() }
        .sheet(item: $editing) { edit in
            StepEditorSheet(step: edit.step, isNew: edit.index == nil) { step in
                if let i = edit.index, draft.steps.indices.contains(i) {
                    draft.steps[i] = step
                } else {
                    draft.steps.append(step)
                }
            }
        }
        .confirmationDialog("Delete “\(draft.name)”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                saveTask?.cancel()
                saveTask = nil
                try? macros.delete(draft.id)
            }
        } message: {
            Text("The macro is removed from every profile. This cannot be undone.")
        }
    }

    @ViewBuilder
    private func stepMenu(_ index: Int, _ step: MacroStep) -> some View {
        Button("Edit…") { editing = StepEdit(index: index, step: step) }
        Button("Duplicate") { draft.steps.insert(step, at: index + 1) }
        Divider()
        Button("Move Up") { draft.steps.swapAt(index, index - 1) }
            .disabled(index == 0)
        Button("Move Down") { draft.steps.swapAt(index, index + 1) }
            .disabled(index >= draft.steps.count - 1)
        Divider()
        Button("Delete Step", role: .destructive) { draft.steps.remove(at: index) }
    }

    private var colorBinding: Binding<Color> {
        Binding(get: { Color(hex: draft.color) ?? .accentColor },
                set: { draft.color = $0.hexString ?? draft.color })
    }

    private var gestureText: Binding<String> {
        Binding(get: { draft.gestureTriggers.joined(separator: ", ") },
                set: { text in
                    draft.gestureTriggers = text.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                })
    }

    /// Edits save on their own, shortly after the last change.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = draft
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            save(snapshot)
        }
    }

    private func flushSave() {
        guard saveTask != nil else { return }
        saveTask?.cancel()
        saveTask = nil
        save(draft)
    }

    private func save(_ macro: Macro) {
        // Deleted meanwhile (from here or the list): do not bring it back.
        guard let current = macros.macro(macro.id), macro != current else { return }
        var m = macro
        if m.name.trimmingCharacters(in: .whitespaces).isEmpty { m.name = original.name }
        try? macros.save(m)
    }
}

private struct StepRow: View {
    let index: Int
    let step: MacroStep

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
            Image(systemName: StepKind(step).symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(step.summary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 28)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Symbols and colours

/// A small grid of SF Symbols that read well on a phone button.
struct SymbolPicker: View {
    @Binding var symbol: String
    let color: String
    @State private var open = false

    static let symbols = [
        "bolt.fill", "wand.and.stars", "star.fill", "heart.fill", "flag.fill", "bookmark.fill",
        "play.fill", "pause.fill", "forward.fill", "backward.fill", "speaker.wave.2.fill", "music.note",
        "safari", "globe", "envelope.fill", "message.fill", "phone.fill", "video.fill",
        "doc.fill", "folder.fill", "tray.full.fill", "archivebox.fill", "paperclip", "link",
        "camera.fill", "photo.fill", "paintbrush.fill", "pencil", "scissors", "eyedropper",
        "terminal.fill", "chevron.left.forwardslash.chevron.right", "hammer.fill", "wrench.fill", "gearshape.fill", "cpu",
        "keyboard", "command", "option", "return", "delete.left.fill", "escape",
        "xmark.square.fill", "plus.square.fill", "arrow.clockwise", "arrow.uturn.backward", "magnifyingglass", "lock.fill",
        "rectangle.split.2x1.fill", "macwindow", "dock.rectangle", "menubar.rectangle", "display", "lightbulb.fill",
        "moon.fill", "sun.max.fill", "cup.and.saucer.fill", "gamecontroller.fill", "airplane", "cart.fill",
    ]

    var body: some View {
        Button {
            open.toggle()
        } label: {
            HStack(spacing: 6) {
                MacroIcon(symbol: symbol, color: color, size: 20)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Icon, \(symbol)")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 6), count: 6), spacing: 6) {
                    ForEach(Self.symbols, id: \.self) { name in
                        Button {
                            symbol = name
                            open = false
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 15))
                                .frame(width: 32, height: 32)
                                .background(name == symbol ? Color.accentColor.opacity(0.25) : .clear,
                                            in: .rect(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help(name)
                        .accessibilityLabel(name)
                    }
                }
                .padding(10)
            }
            .frame(width: 250, height: 260)
        }
    }
}

extension Color {
    /// `#RRGGBB` (or `RRGGBB`) in sRGB.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(.sRGB, red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255, opacity: 1)
    }

    var hexString: String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        func byte(_ x: CGFloat) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}

// MARK: - Profiles

private struct ProfileLibrary: View {
    @ObservedObject var macros: MacroCoordinator
    @State private var selection: UUID?
    @State private var confirmRestore = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(macros.profiles) { profile in
                        HStack(spacing: 8) {
                            Image(systemName: profile.symbol)
                                .frame(width: 20)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(profile.name)
                                    .lineLimit(1)
                                Text(profile.isFallback ? "Everywhere else" : appsSummary(profile))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if macros.activeProfile.profileID == profile.id {
                                Image(systemName: "iphone")
                                    .foregroundStyle(.tint)
                                    .help("On the phone now")
                            }
                        }
                        .tag(profile.id)
                    }
                }
                .listStyle(.sidebar)
                .overlay {
                    if macros.profiles.isEmpty {
                        ContentUnavailableView("No Profiles", systemImage: "rectangle.stack",
                                               description: Text("Without profiles the phone shows every macro."))
                    }
                }
                Divider()
                HStack(spacing: 2) {
                    Button {
                        add()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add a profile")
                    Button {
                        remove()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selection == nil)
                    .help("Delete the selected profile")
                    Spacer()
                    Menu {
                        Button("Restore Starter Macros and Profiles…") { confirmRestore = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 220)
            Divider()
            Group {
                if let id = selection, let profile = macros.profiles.first(where: { $0.id == id }) {
                    ProfileEditor(macros: macros, original: profile)
                        .id(profile.id)
                } else {
                    ContentUnavailableView("No Profile Selected", systemImage: "rectangle.stack",
                                           description: Text("A profile picks the phone's buttons while its apps are in front."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { if selection == nil { selection = macros.activeProfile.profileID ?? macros.profiles.first?.id } }
        .confirmationDialog("Restore the starter macros and profiles?", isPresented: $confirmRestore) {
            Button("Restore") { try? macros.restoreStarters() }
        } message: {
            Text("Starters you edited or deleted come back as shipped. Your own macros and profiles are not touched.")
        }
    }

    private func appsSummary(_ p: ContextProfile) -> String {
        let names = p.bundleIDs.map(AppInfo.name(for:))
        return names.isEmpty ? "No apps" : names.joined(separator: ", ")
    }

    private func add() {
        let p = ContextProfile(name: "New Profile", symbol: "app.dashed", bundleIDs: [], macroIDs: [])
        try? macros.save(profiles: macros.profiles + [p])
        selection = p.id
    }

    private func remove() {
        guard let id = selection else { return }
        try? macros.save(profiles: macros.profiles.filter { $0.id != id })
        selection = macros.profiles.first?.id
    }
}

private struct ProfileEditor: View {
    @ObservedObject var macros: MacroCoordinator
    let original: ContextProfile
    @State private var draft: ContextProfile

    init(macros: MacroCoordinator, original: ContextProfile) {
        self.macros = macros
        self.original = original
        _draft = State(initialValue: original)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name)
                LabeledContent("Icon") {
                    SymbolPicker(symbol: $draft.symbol, color: "#8E8E93")
                }
                Toggle("Use everywhere else", isOn: $draft.isFallback)
            } footer: {
                if draft.isFallback {
                    Text("This profile's buttons show whenever no other profile matches the app in front.")
                        .foregroundStyle(.secondary)
                }
            }

            if !draft.isFallback {
                Section("Apps") {
                    if draft.bundleIDs.isEmpty {
                        Text("Add the apps this profile is for.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(draft.bundleIDs, id: \.self) { id in
                        HStack(spacing: 8) {
                            Image(nsImage: AppInfo.icon(for: id))
                                .resizable()
                                .frame(width: 18, height: 18)
                            Text(AppInfo.name(for: id))
                            Text(id)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Spacer()
                            Button {
                                draft.bundleIDs.removeAll { $0 == id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(AppInfo.name(for: id))")
                        }
                    }
                    Button("Add App…") { chooseApp() }
                }
            }

            Section {
                if draft.macroIDs.isEmpty {
                    Text("No buttons yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(draft.macroIDs.enumerated()), id: \.offset) { index, id in
                    HStack(spacing: 8) {
                        if let m = macros.macro(id) {
                            MacroIcon(symbol: m.symbol, color: m.color, size: 20)
                            Text(m.name)
                        } else {
                            Image(systemName: "questionmark.square.dashed")
                            Text("Missing macro").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { draft.macroIDs.swapAt(index, index - 1) } label: { Image(systemName: "chevron.up") }
                            .disabled(index == 0)
                            .accessibilityLabel("Move up")
                        Button { draft.macroIDs.swapAt(index, index + 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(index >= draft.macroIDs.count - 1)
                            .accessibilityLabel("Move down")
                        Button { draft.macroIDs.remove(at: index) } label: { Image(systemName: "minus.circle") }
                            .accessibilityLabel("Remove button")
                    }
                    .buttonStyle(.borderless)
                }
                let available = macros.macros.filter { !draft.macroIDs.contains($0.id) }
                Menu("Add Button") {
                    ForEach(available) { m in
                        Button(m.name) { draft.macroIDs.append(m.id) }
                    }
                }
                .disabled(available.isEmpty)
                .fixedSize()
            } header: {
                Text("Phone Buttons")
            } footer: {
                Text("In this order on the phone's Macros screen.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: draft) { _, new in
            var all = macros.profiles
            guard let i = all.firstIndex(where: { $0.id == new.id }), all[i] != new else { return }
            all[i] = new
            if new.isFallback {       // only one fallback
                for j in all.indices where j != i { all[j].isFallback = false }
            }
            try? macros.save(profiles: all)
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !draft.bundleIDs.contains(id) { draft.bundleIDs.append(id) }
        }
    }
}

enum AppInfo {
    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }
}
