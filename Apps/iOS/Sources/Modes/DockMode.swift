import Photos
import SwiftUI
import UniformTypeIdentifiers
import GlasspadKit

/// The Mac's Dock on the phone: its apps in Dock order with running dots, then recently used
/// apps. Tap opens or switches; long press for Quit, Hide, Show in Finder and the phone's own
/// arrangement (keep, hide, reorder). Search finds any installed app.
struct DockMode: View {
    @Environment(\.palette) private var palette
    @Environment(\.verticalSizeClass) private var verticalSize
    @Bindable var settings = PhoneSettings.shared
    var session = MacSession.shared
    private let accent = AppMode.dock.accent(.paper)

    @State private var query = ""
    @State private var editing = false
    @State private var dragging: String?
    @State private var showHidden = false
    @FocusState private var searchFocused: Bool

    private var compact: Bool { verticalSize == .compact }

    private var arranged: DockArrangement.Arranged {
        settings.dockArrangement.arrange(session.dockApps, showRecent: settings.dockShowsRecent)
    }

    var body: some View {
        GeometryReader { geo in
            let margin: CGFloat = 16
            let width = geo.size.width - margin * 2
            let metrics = DockGridMetrics.fit(width: Double(width), density: settings.dockDensity,
                                              scale: settings.dockIconScale, spacing: 8)
            ZStack {
                if session.dockApps.isEmpty && !session.isConnected {
                    ModeOfflineMessage(mode: .dock)
                } else if session.dockApps.isEmpty {
                    loading
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: compact ? 14 : 20) {
                            if compact {
                                // Sideways: title, search and options share one row.
                                HStack(spacing: 16) {
                                    header.fixedSize(horizontal: true, vertical: false)
                                    searchField
                                }
                            } else {
                                header
                                searchField
                            }
                            if query.isEmpty {
                                grid(arranged.apps, metrics: metrics, reorderable: true)
                                if !arranged.recent.isEmpty && !editing {
                                    section("Recent")
                                    grid(arranged.recent, metrics: metrics, reorderable: false)
                                }
                                if editing { editFooter }
                            } else {
                                searchResults(metrics: metrics)
                            }
                        }
                        .padding(.horizontal, margin)
                        .padding(.top, settings.pillPosition == .top ? (compact ? 40 : 60) : 12)
                        .padding(.bottom, settings.pillPosition == .bottom ? 80 : 32)
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .refreshable { session.requestDock() }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .overlay(alignment: .bottom) { noticeBanner }
        .animation(.snappy(duration: 0.25), value: editing)
        .animation(.snappy(duration: 0.25), value: settings.dockArrangement)
        .onAppear { session.requestDock() }
        .onChange(of: query) { _, q in
            if !q.isEmpty, session.dockCatalog.isEmpty { session.send(.dockCatalogRequest) }
            requestMissingIcons()
        }
        .onChange(of: session.dockCatalog) { requestMissingIcons() }
        .sheet(isPresented: $showHidden) { HiddenAppsSheet().presentationDetents([.medium, .large]) }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Apps")
                    .font(compact ? .title.bold() : .largeTitle.bold())
                    .foregroundStyle(palette.inkColor)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(palette.inkSoftColor)
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
            if !compact { Spacer() }
            if editing {
                Button("Done") {
                    Haptics.shared.tap()
                    editing = false
                }
                .font(.body.weight(.semibold))
                .glassButton(prominent: true, accent: accent)
            } else {
                optionsMenu
            }
        }
    }

    private var subtitle: String {
        let running = session.dockApps.filter(\.running).count
        let name = session.macName ?? "Your Mac"
        guard session.isConnected else { return "\(name) · Not connected" }
        return running == 0 ? name : "\(name) · \(running) open"
    }

    private var optionsMenu: some View {
        Menu {
            Button("Edit Apps", systemImage: "square.grid.3x3.square") {
                searchFocused = false
                query = ""
                editing = true
            }
            if !settings.dockArrangement.hidden.isEmpty {
                Button("Hidden Apps", systemImage: "eye.slash") { showHidden = true }
            }
            Divider()
            Toggle(isOn: macDockBinding(\.hidden)) {
                Label("Hide Mac Dock", systemImage: "dock.rectangle")
            }
            Toggle(isOn: macDockBinding(\.hideWhileConnected)) {
                Label("Hide Mac Dock While Connected", systemImage: "link")
            }
            Divider()
            Picker("Icon Size", selection: $settings.dockDensity) {
                Text("Small").tag(DockDensity.compact)
                Text("Medium").tag(DockDensity.regular)
                Text("Large").tag(DockDensity.large)
            }
            Toggle("Show Names", isOn: $settings.dockShowsNames)
            Toggle("Show Recent Apps", isOn: $settings.dockShowsRecent)
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .glassButton()
        .buttonBorderShape(.circle)
        .accessibilityLabel("Apps options")
    }

    private func macDockBinding(_ key: WritableKeyPath<MacDockState, Bool>) -> Binding<Bool> {
        Binding {
            session.macDockState?[keyPath: key] ?? false
        } set: { on in
            var s = session.macDockState ?? MacDockState(hidden: false, hideWhileConnected: false)
            s[keyPath: key] = on
            Haptics.shared.tap()
            session.setMacDock(s)
        }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.inkSoftColor)
                .accessibilityHidden(true)
            TextField("Search apps on your Mac", text: $query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit {
                    if let first = searchMatches.first { open(first) }
                }
                .foregroundStyle(palette.inkColor)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.inkSoftColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .font(.body)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .glassCapsule()
        .opacity(editing ? 0.4 : 1)
        .disabled(editing)
    }

    private var searchMatches: [DockApp] {
        let pool = arranged.apps + arranged.recent + session.dockCatalog
        return DockArrangement.search(query, in: pool)
    }

    @ViewBuilder private func searchResults(metrics: DockGridMetrics) -> some View {
        let matches = searchMatches
        if matches.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(palette.inkSoftColor)
                Text(session.dockCatalog.isEmpty && session.isConnected ? "Searching…" : "No Results for \u{201C}\(query)\u{201D}")
                    .font(.headline)
                    .foregroundStyle(palette.inkColor)
                Text("Search looks at every app installed on your Mac.")
                    .font(.subheadline)
                    .foregroundStyle(palette.inkSoftColor)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
        } else {
            grid(Array(matches.prefix(60)), metrics: metrics, reorderable: false)
        }
    }

    private func requestMissingIcons() {
        guard !query.isEmpty else { return }
        let missing = searchMatches.prefix(40).filter { session.icons.image(for: $0.bundleID) == nil }.map(\.bundleID)
        if !missing.isEmpty { session.send(.dockIconRequest(bundleIDs: missing)) }
    }

    // MARK: Grid

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(palette.inkColor)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func grid(_ apps: [DockApp], metrics: DockGridMetrics, reorderable: Bool) -> some View {
        let columns = Array(repeating: GridItem(.fixed(metrics.cellWidth), spacing: metrics.spacing, alignment: .top),
                            count: metrics.columns)
        return LazyVGrid(columns: columns, spacing: settings.dockShowsNames ? 18 : 14) {
            ForEach(apps, id: \.bundleID) { app in
                tile(app, metrics: metrics, reorderable: reorderable, shown: apps.map(\.bundleID))
            }
        }
    }

    @ViewBuilder
    private func tile(_ app: DockApp, metrics: DockGridMetrics, reorderable: Bool, shown: [String]) -> some View {
        let base = DockTile(app: app, icon: session.icons.image(for: app.bundleID), iconSize: metrics.iconSize,
                            showsName: settings.dockShowsNames, accent: accent, editing: editing && reorderable,
                            kept: settings.dockArrangement.isKept(app.bundleID)) {
            if editing {
                if reorderable { hide(app) }
            } else {
                open(app)
            }
        }
        .frame(width: metrics.cellWidth)
        .opacity(dragging == app.bundleID ? 0.35 : 1)

        if editing && reorderable {
            base
                .onDrag {
                    dragging = app.bundleID
                    return NSItemProvider(object: app.bundleID as NSString)
                }
                .onDrop(of: [UTType.text], delegate: DockDropDelegate(target: app.bundleID, shown: shown,
                                                                       dragging: $dragging, settings: settings))
        } else {
            base.contextMenu {
                contextMenu(for: app)
            } preview: {
                DockIconPreview(app: app, icon: session.icons.image(for: app.bundleID))
            }
        }
    }

    @ViewBuilder private func contextMenu(for app: DockApp) -> some View {
        Button(app.running ? "Switch To" : "Open", systemImage: app.running ? "macwindow" : "arrow.up.forward.app") { open(app) }
        if app.running {
            if app.hidden == true {
                Button("Show", systemImage: "eye") { act(.unhide, app) }
            } else {
                Button("Hide", systemImage: "eye.slash") { act(.hide, app) }
            }
        }
        Button("Show in Finder", systemImage: "folder") { act(.revealInFinder, app) }
        Divider()
        let kept = settings.dockArrangement.isKept(app.bundleID)
        Button(kept ? "Remove from Phone Dock" : "Keep in Phone Dock", systemImage: kept ? "pin.slash" : "pin") {
            Haptics.shared.tap()
            settings.dockArrangement.setKept(app, !kept)
        }
        Button("Hide on iPhone", systemImage: "eye.slash.circle") { hide(app) }
        Button("Edit Apps", systemImage: "square.grid.3x3.square") { editing = true }
        if app.running {
            Divider()
            Button("Quit", systemImage: "xmark.circle", role: .destructive) { act(.quit, app) }
        }
    }

    private var editFooter: some View {
        VStack(spacing: 12) {
            Text("Drag to reorder. Tap an app to hide it on this iPhone; your Mac's Dock does not change.")
                .font(.footnote)
                .foregroundStyle(palette.inkSoftColor)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                if !settings.dockArrangement.hidden.isEmpty {
                    Button("Hidden Apps (\(settings.dockArrangement.hidden.count))") { showHidden = true }
                        .glassButton()
                }
                if !settings.dockArrangement.order.isEmpty {
                    Button("Use Mac Order") {
                        Haptics.shared.tap()
                        settings.dockArrangement.order = []
                    }
                    .glassButton()
                }
            }
            .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var loading: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("Getting your Mac's Dock")
                .font(.subheadline)
                .foregroundStyle(palette.inkSoftColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var noticeBanner: some View {
        if let notice = session.dockNotice {
            VStack(alignment: .leading, spacing: 2) {
                Label(notice.title, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                Text(notice.message)
                    .font(.footnote)
                    .foregroundStyle(palette.inkSoftColor)
            }
            .foregroundStyle(palette.inkColor)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: 420, alignment: .leading)
            .glassPanel(cornerRadius: 22)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(notice.id)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Actions

    private func open(_ app: DockApp) {
        Haptics.shared.tap()
        searchFocused = false
        session.openDockApp(app)
    }

    private func act(_ action: DockAppAction, _ app: DockApp) {
        Haptics.shared.tap()
        session.send(.dockAppAction(bundleID: app.bundleID, action: action))
    }

    private func hide(_ app: DockApp) {
        Haptics.shared.tap()
        settings.dockArrangement.hide(app.bundleID)
    }
}

/// Live reordering while dragging in edit mode.
private struct DockDropDelegate: DropDelegate {
    let target: String
    let shown: [String]
    @Binding var dragging: String?
    let settings: PhoneSettings

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        MainActor.assumeIsolated {
            settings.dockArrangement.move(dragging, before: target, shown: shown)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// One app: its full-resolution icon, a running dot under it like the Mac's Dock, its name.
private struct DockTile: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let app: DockApp
    let icon: UIImage?
    let iconSize: Double
    let showsName: Bool
    let accent: Color
    let editing: Bool
    let kept: Bool
    let action: () -> Void

    @State private var wiggle = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                DockIcon(app: app, icon: icon, size: iconSize)
                    .opacity(app.hidden == true ? 0.55 : 1)
                    .overlay(alignment: .topLeading) {
                        if editing {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 22))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color(uiColor: .systemGray))
                                .offset(x: -6, y: -6)
                                .transition(.scale.combined(with: .opacity))
                                .accessibilityHidden(true)
                        }
                    }
                    .rotationEffect(.degrees(editing && wiggle && !reduceMotion ? 1.6 : 0))
                Circle()
                    .fill(app.active ? accent : palette.inkColor.opacity(0.55))
                    .frame(width: 4, height: 4)
                    .opacity(app.running ? 1 : 0)
                    .accessibilityHidden(true)
                if showsName {
                    Text(app.name)
                        .font(.caption)
                        .foregroundStyle(palette.inkColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TileStyle())
        .onChange(of: editing, initial: true) { _, on in
            guard on, !reduceMotion else { wiggle = false; return }
            withAnimation(.easeInOut(duration: 0.13).repeatForever(autoreverses: true)) { wiggle = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.name)
        .accessibilityValue(statusText)
        .accessibilityHint(editing ? "Hides it on this iPhone" : (app.running ? "Switches to it on your Mac" : "Opens it on your Mac"))
        .accessibilityAddTraits(.isButton)
    }

    private var statusText: String {
        var parts: [String] = []
        if app.active { parts.append("Frontmost") } else if app.running { parts.append("Running") }
        if app.hidden == true { parts.append("Hidden") }
        if kept { parts.append("Kept on iPhone") }
        return parts.joined(separator: ", ")
    }
}

/// The app's icon at full resolution, or a calm placeholder until it arrives.
struct DockIcon: View {
    @Environment(\.palette) private var palette
    let app: DockApp
    let icon: UIImage?
    let size: Double

    var body: some View {
        Group {
            if let icon {
                Image(uiImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
            } else {
                // macOS icons sit inside a rounded square at about 82% of the canvas.
                RoundedRectangle(cornerRadius: size * 0.82 * 0.225, style: .continuous)
                    .fill(palette.raisedColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.82 * 0.225, style: .continuous)
                            .strokeBorder(palette.lineColor)
                    }
                    .overlay(Text(app.name.prefix(1)).font(.system(size: size * 0.34, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.inkSoftColor))
                    .padding(size * 0.09)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct DockIconPreview: View {
    @Environment(\.palette) private var palette
    let app: DockApp
    let icon: UIImage?
    var body: some View {
        VStack(spacing: 10) {
            DockIcon(app: app, icon: icon, size: 128)
            Text(app.name).font(.headline).foregroundStyle(palette.inkColor)
        }
        .padding(20)
        .background(palette.backgroundColor)
    }
}

/// Apps hidden on the phone, with a way back.
private struct HiddenAppsSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings = PhoneSettings.shared
    var session = MacSession.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(settings.dockArrangement.hidden.sorted(), id: \.self) { id in
                        let app = (session.dockApps + session.dockCatalog).first { $0.bundleID == id }
                            ?? DockApp(bundleID: id, name: id, running: false, active: false)
                        HStack(spacing: 12) {
                            DockIcon(app: app, icon: session.icons.image(for: id), size: 40)
                            Text(app.name).foregroundStyle(palette.inkColor)
                            Spacer()
                            Button("Show") {
                                Haptics.shared.tap()
                                settings.dockArrangement.unhide(id)
                            }
                            .glassButton()
                        }
                    }
                } footer: {
                    Text("Hidden apps stay in your Mac's Dock. They are only left out on this iPhone.")
                }
                .listRowBackground(palette.raisedColor)
            }
            .scrollContentBackground(.hidden)
            .background(palette.backgroundColor)
            .navigationTitle("Hidden Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: settings.dockArrangement.hidden.isEmpty) { _, empty in if empty { dismiss() } }
        }
    }
}

/// A gentle press-down for icon tiles, like the Home Screen.
struct TileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

/// Why a Dock tap did not work.
struct DockNotice: Equatable {
    let id = UUID()
    let title: String
    let message: String
}

/// Saves an image to Photos (add-only permission).
@MainActor
enum PhotoSaver {
    static func save(_ image: UIImage, done: @escaping @MainActor (Bool) -> Void) {
        guard let data = image.pngData() else { return done(false) }
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else { return done(false) }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                }
                done(true)
            } catch {
                done(false)
            }
        }
    }
}

/// Dock icons, kept in memory and in the Caches folder by icon key (bundle id + the app's
/// modification date), so each icon crosses the network once. Icons arrive at 256 px.
@MainActor
final class IconCache {
    private var memory: [String: UIImage] = [:]
    /// bundle id -> newest icon key.
    private var index: [String: String]
    private let folder: URL?
    private static let indexName = "index.json"

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let url = base?.appendingPathComponent("DockIcons256", isDirectory: true)
        if let url { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        folder = url
        index = url.flatMap { try? Data(contentsOf: $0.appendingPathComponent(Self.indexName)) }
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        // The 64 px cache from the first version is not used any more.
        if let old = base?.appendingPathComponent("DockIcons", isDirectory: true) { try? FileManager.default.removeItem(at: old) }
    }

    /// Icon keys this phone has on disk (sent to the Mac in `dockSync`).
    var knownKeys: [String] { Array(Set(index.values)).sorted() }

    func store(_ png: Data, key: String, bundleID: String) {
        guard let image = UIImage(data: png, scale: 3)?.preparingForDisplay() ?? UIImage(data: png, scale: 3) else { return }
        if let old = index[bundleID], old != key, let url = fileURL(old) {
            try? FileManager.default.removeItem(at: url)
            memory[old] = nil
        }
        memory[key] = image
        index[bundleID] = key
        if let url = fileURL(key) { try? png.write(to: url, options: .atomic) }
        saveIndex()
    }

    func image(for bundleID: String) -> UIImage? {
        guard let key = index[bundleID] else { return nil }
        if let image = memory[key] { return image }
        guard let url = fileURL(key), let data = try? Data(contentsOf: url),
              let image = UIImage(data: data, scale: 3)?.preparingForDisplay() else { return nil }
        memory[key] = image
        return image
    }

    private func saveIndex() {
        guard let folder, let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: folder.appendingPathComponent(Self.indexName), options: .atomic)
    }

    private func fileURL(_ key: String) -> URL? {
        let safe = key.replacingOccurrences(of: "/", with: "_")
        return folder?.appendingPathComponent(safe + ".png")
    }
}
