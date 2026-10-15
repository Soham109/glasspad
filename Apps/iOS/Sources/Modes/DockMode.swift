import SwiftUI
import GlasspadKit

/// The Mac's Dock apps followed by its other running apps. Tap to open or switch.
struct DockMode: View {
    @Environment(\.palette) private var palette
    var session = MacSession.shared
    private let accent = AppMode.dock.accent(.paper)

    private let columns = [GridItem(.adaptive(minimum: 76, maximum: 96), spacing: 14, alignment: .top)]

    var body: some View {
        ZStack {
            if !session.isConnected && session.dockApps.isEmpty {
                ModeOfflineMessage(mode: .dock)
            } else if session.dockApps.isEmpty {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(session.dockApps, id: \.bundleID) { app in
                            DockTile(app: app, icon: session.icons.image(for: app.bundleID), accent: accent) {
                                Haptics.shared.tap()
                                session.send(.dockOpen(bundleID: app.bundleID))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 76)
                    .padding(.bottom, 32)
                }
                .refreshable { session.send(.dockRequest) }
            }
        }
        .onAppear { session.send(.dockRequest) }
    }
}

private struct DockTile: View {
    @Environment(\.palette) private var palette
    let app: DockApp
    let icon: UIImage?
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    if let icon {
                        Image(uiImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(palette.raisedColor)
                            .overlay(Text(app.name.prefix(1)).font(.title2.weight(.semibold)).foregroundStyle(palette.inkSoftColor))
                    }
                }
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(palette.isDark ? 0.35 : 0.1), radius: 6, y: 3)

                Text(app.name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(palette.inkColor)

                Circle()
                    .fill(app.active ? accent : palette.inkColor.opacity(0.45))
                    .frame(width: 5, height: 5)
                    .opacity(app.running ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TileStyle())
        .accessibilityLabel(app.name)
        .accessibilityValue(app.active ? "Frontmost" : (app.running ? "Running" : ""))
        .accessibilityHint(app.running ? "Switches to it on your Mac" : "Opens it on your Mac")
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

/// Dock icons by bundle id: kept in memory and in the Caches folder, because the Mac
/// only sends an icon the first time.
@MainActor
final class IconCache {
    private var memory: [String: UIImage] = [:]
    private let folder: URL? = {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let url = base.appendingPathComponent("DockIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func store(_ png: Data, for bundleID: String) {
        guard let image = UIImage(data: png, scale: 2) else { return }
        memory[bundleID] = image
        if let url = fileURL(bundleID) { try? png.write(to: url, options: .atomic) }
    }

    func image(for bundleID: String) -> UIImage? {
        if let image = memory[bundleID] { return image }
        guard let url = fileURL(bundleID), let data = try? Data(contentsOf: url),
              let image = UIImage(data: data, scale: 2) else { return nil }
        memory[bundleID] = image
        return image
    }

    private func fileURL(_ bundleID: String) -> URL? {
        let safe = bundleID.replacingOccurrences(of: "/", with: "_")
        return folder?.appendingPathComponent(safe + ".png")
    }
}
