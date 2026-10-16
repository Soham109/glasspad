import ImageIO
import Photos
import SwiftUI
import UniformTypeIdentifiers
import GlasspadKit

/// The Mac's Dock on the phone, and nothing else: its apps and the running ones, in Dock order
/// with running dots. Tap opens or switches; long press for Quit, Hide, Show in Finder and the
/// phone's own arrangement (keep, hide, reorder). Apps that are not in the Dock are pinned in
/// Actions (Library > Apps lists every installed app).
struct DockMode: View {
    @Environment(\.palette) private var palette
    @Environment(\.modeTopClearance) private var topClearance
    @Environment(\.verticalSizeClass) private var verticalSize
    @Bindable var settings = PhoneSettings.shared
    var session = MacSession.shared
    private var accent: Color { AppMode.dock.accent(palette) }

    @State private var editing = false
    @State private var dragging: String?
    @State private var showHidden = false

    private var compact: Bool { verticalSize == .compact }

    private var arranged: DockArrangement.Arranged {
        settings.dockArrangement.arrange(session.dockApps, showRecent: false)
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
                            header
                            grid(arranged.apps, metrics: metrics, reorderable: true)
                            if editing { editFooter }
                        }
                        .padding(.horizontal, margin)
                        .padding(.top, topClearance ?? (settings.pillPosition == .top ? (compact ? 40 : 60) : 12))
                        .padding(.bottom, settings.pillPosition == .bottom ? 80 : 32)
                    }
                    .refreshable { session.requestDock() }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .overlay(alignment: .bottom) { noticeBanner }
        .animation(.snappy(duration: 0.25), value: editing)
        .animation(.snappy(duration: 0.25), value: settings.dockArrangement)
        .onAppear { session.requestDock() }
        .sheet(isPresented: $showHidden) { HiddenAppsSheet().presentationDetents([.medium, .large]) }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dock")
                    .font(compact ? .title.bold() : .largeTitle.bold())
                    .foregroundStyle(palette.inkColor)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(palette.inkSoftColor)
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
            Spacer()
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
            Button("Edit Dock", systemImage: "square.grid.3x3.square") {
                editing = true
            }
            if !settings.dockArrangement.hidden.isEmpty {
                Button("Hidden Apps", systemImage: "eye.slash") { showHidden = true }
            }
            Divider()
            Picker(selection: macDockHiding) {
                ForEach(MacDockHiding.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                Label("Hide Mac Dock", systemImage: "dock.rectangle")
            }
            .pickerStyle(.menu)
            Divider()
            Picker("Icon Size", selection: $settings.dockDensity) {
                Text("Small").tag(DockDensity.compact)
                Text("Medium").tag(DockDensity.regular)
                Text("Large").tag(DockDensity.large)
            }
            Toggle("Show Names", isOn: $settings.dockShowsNames)
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .glassButton()
        .buttonBorderShape(.circle)
        .accessibilityLabel("Dock options")
    }

    private var macDockHiding: Binding<MacDockHiding> {
        Binding {
            MacDockHiding(session.macDockState)
        } set: { choice in
            Haptics.shared.tap()
            session.setMacDock(choice.state)
        }
    }

    // MARK: Grid

    private func grid(_ apps: [DockApp], metrics: DockGridMetrics, reorderable: Bool) -> some View {
        BalancedRowsLayout(columns: metrics.columns, cellWidth: metrics.cellWidth, spacing: metrics.spacing,
                           rowSpacing: settings.dockShowsNames ? 18 : 14) {
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
        Button("Edit Dock", systemImage: "square.grid.3x3.square") { editing = true }
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

/// Cells of one width in balanced, centred rows (`BalancedRows`): 17 apps across 5 are
/// 5 + 4 + 4 + 4, never a last row of two. Each row is as tall as its tallest cell.
struct BalancedRowsLayout: Layout {
    let columns: Int
    let cellWidth: CGFloat
    let spacing: CGFloat
    let rowSpacing: CGFloat

    private func rows(_ subviews: Subviews) -> [Range<Int>] {
        var start = 0
        return BalancedRows.counts(items: subviews.count, maxPerRow: columns).map { n in
            defer { start += n }
            return start..<(start + n)
        }
    }

    private func heights(_ subviews: Subviews) -> [CGFloat] {
        rows(subviews).map { r in
            r.map { subviews[$0].sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height }.max() ?? 0
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let h = heights(subviews)
        let width = proposal.width ?? (CGFloat(columns) * cellWidth + CGFloat(columns - 1) * spacing)
        return CGSize(width: width, height: h.reduce(0, +) + CGFloat(max(0, h.count - 1)) * rowSpacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let h = heights(subviews)
        var y = bounds.minY
        for (r, range) in rows(subviews).enumerated() {
            let rowWidth = CGFloat(range.count) * cellWidth + CGFloat(range.count - 1) * spacing
            var x = bounds.minX + ((bounds.width - rowWidth) / 2).rounded(.down)
            for i in range {
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: cellWidth, height: h[r]))
                x += cellWidth + spacing
            }
            y += h[r] + rowSpacing
        }
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
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
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
                    // Mono has no colour anywhere, app icons included.
                    .saturation(palette.monochrome ? 0 : 1)
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
        .background(palette.solidColor)
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
            .background(SurfaceBackground())
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
/// modification date), so each icon crosses the network once. Icons arrive at 256 px or more
/// and are drawn from the full image, never stretched up from a small one.
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
        // Decoded icons are up to 1 MB each; under memory pressure drop them (they reload from disk).
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.memory.removeAll() }
        }
    }

    /// Icon keys this phone has on disk (sent to the Mac in `dockSync`).
    var knownKeys: [String] { Array(Set(index.values)).sorted() }

    /// Icons are decoded at most this many pixels on a side: sharp at 3x up to a 170 pt tile,
    /// however large the Mac sends them, without holding 1024 px bitmaps for every app.
    static let decodedPixels = 512

    /// Decodes at full resolution up to `decodedPixels` (scaled down by ImageIO, never up),
    /// at the screen's scale so a point of icon is a pixel of screen.
    static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: decodedPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg, scale: 3, orientation: .up)
    }

    func store(_ png: Data, key: String, bundleID: String) {
        guard let image = Self.decode(png) else { return }
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
              let image = Self.decode(data) else { return nil }
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
